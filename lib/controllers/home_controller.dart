import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import '../controllers/auth_controller.dart';
import '../controllers/doctor_search_controller.dart';
import '../controllers/voice_controller.dart';
import '../models/doctor_model.dart';
import '../routes/app_routes.dart';
import '../services/location_service.dart';
import '../services/local_storage_service.dart';
import '../services/places_service.dart';
import '../widgets/gps_off_dialog.dart' as gps;

/// Drives the PATIENT home screen: location/GPS (fetch, permission
/// prompts, GPS-off popup) and the top-rated-doctors section. It is
/// deliberately created ONLY on the patient side (the patient MainShell)
/// — the doctor dashboard never instantiates it, so doctors are never
/// asked for location permission.
class HomeController extends GetxController {
  final AuthController _authController = Get.find<AuthController>();
  final LocationService _locationService = LocationService();
  final LocalStorageService _storage = LocalStorageService();
  final RxString currentLocation = 'Fetching location...'.obs;
  final Rx<String?> currentLatLng = Rx<String?>(null);
  final RxBool isLoadingLocation = true.obs;

  /// Track the current failure reason so the UI can show appropriate actions
  final Rx<LocationFailureReason?> locationFailureReason =
      Rx<LocationFailureReason?>(null);

  Timer? _locationTimer;
  bool _hasShownLocationDialog = false;

  /// Test hook — replaces the real GPS-service probe (a platform call that
  /// throws MissingPluginException on bare test bindings) with a fake.
  @visibleForTesting
  Future<bool> Function()? isGpsEnabledOverride;

  /// Test hook — replaces the real location fetch (a platform call that
  /// throws MissingPluginException on bare test bindings) so tests can
  /// simulate a disabled GPS service deterministically.
  @visibleForTesting
  Future<LocationResult> Function()? fetchLocationOverride;

  /// Whether the automatic GPS-off popup has been shown this session — the
  /// popup fires once per app run (it would otherwise nag on every 60s
  /// location refresh while GPS stays off).
  bool _hasShownGpsOffPopup = false;

  // ── Top Rated Doctors ───────────────────────────────────────────
  final RxList<DoctorModel> topDoctors = <DoctorModel>[].obs;
  final RxBool isLoadingTopDoctors = false.obs;
  DateTime? _lastTopDoctorFetch;

  @override
  void onInit() {
    super.onInit();
    _initializeLocation();
    _startPeriodicLocationRefresh();
  }

  @override
  void onClose() {
    _locationTimer?.cancel();
    super.onClose();
  }

  Future<void> _initializeLocation() async {
    await _checkAndShowLocationPermission();
    await _fetchLocation();
  }

  Future<void> _checkAndShowLocationPermission() async {
    if (_hasShownLocationDialog) return;
    // Patient-only: if this process is now a doctor session (shared device
    // where a patient's controller outlived their session), never ask.
    if (_authController.isDoctor) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _hasShownLocationDialog = true;
        await Future.delayed(const Duration(milliseconds: 500));

        // Guard: only show the dialog if the navigator is ready. The
        // HomeController is created by the patient shell (MainShell) after
        // runApp, so the tree always exists here — kept as a safety net
        // (the controller may outlive the shell across logout/login).
        if (Get.key.currentState == null) return;

        Get.dialog(
          AlertDialog(
            title: const Text('Location Permission'),
            content: const Text(
              'Please allow location access to find nearby doctors and hospitals. '
              'Your location is used only for finding healthcare providers near you.',
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('Later'),
              ),
              TextButton(
                onPressed: () async {
                  Get.back();
                  await _locationService.requestPermission();
                  await _fetchLocation();
                },
                child: const Text('Allow'),
              ),
            ],
          ),
          barrierDismissible: false,
        );
      }
    } catch (_) {
      // Geolocator may throw MissingPluginException on some platforms
      // or during first launch.  Silently skip — the splash screen
      // will handle location checks, and the home UI shows a
      // location-off indicator.
    }
  }

  void _startPeriodicLocationRefresh() {
    _locationTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      // Patient-only: a doctor session on this device (e.g. after a
      // patient logged out and a doctor logged in on the same shared
      // phone) must not keep fetching the patient's location.
      if (_authController.isDoctor) return;
      _fetchLocation();
    });
  }

  /// Resolve the location result — real service, or the test override when
  /// one is installed.
  Future<LocationResult> _fetchLocationResult() {
    final override = fetchLocationOverride;
    if (override != null) return override();
    return _locationService.fetchLocation();
  }

  Future<void> _fetchLocation() async {
    // Patient-only: never fetch/refresh location (or the top-doctors
    // section) while a doctor session is active on this device.
    if (_authController.isDoctor) return;
    isLoadingLocation.value = true;
    locationFailureReason.value = null;
    try {
      final result = await _fetchLocationResult();
      if (result.success && result.address != null) {
        currentLocation.value = result.address!;
        locationFailureReason.value = null;
        if (result.position != null) {
          final lat = result.position!.latitude.toStringAsFixed(4);
          final lng = result.position!.longitude.toStringAsFixed(4);
          currentLatLng.value = '$lat, $lng';

          // Requirement: on every app open, capture current GPS fix and
          // persist lat/lng so it can be reused across screens/sessions.
          await _storage.saveLastLatLng(
            result.position!.latitude,
            result.position!.longitude,
          );
        }
        // Successfully fetched location — no need to fetch nearby clinics
      } else {
        // Fall back to the last saved GPS fix so searches still have a
        // location bias even when a fresh fix can't be obtained.
        final lastSaved = _storage.getLastLatLng();
        if (lastSaved != null && lastSaved.length == 2) {
          currentLatLng.value =
              '${lastSaved[0].toStringAsFixed(4)}, ${lastSaved[1].toStringAsFixed(4)}';
        } else {
          currentLatLng.value = null;
        }
        switch (result.reason) {
          case LocationFailureReason.serviceDisabled:
            currentLocation.value = 'GPS is off';
            locationFailureReason.value = LocationFailureReason.serviceDisabled;
            // The patient landed on the home page with GPS off — show the
            // GPS-off popup (dismissible, with an Open-Settings action) so
            // they know why nothing can be found nearby and how to fix it.
            // Once per session: a dismissed prompt is not re-shown by the
            // periodic refresh.
            unawaited(_maybeShowGpsOffPopup());
            break;
          case LocationFailureReason.permissionDenied:
          case LocationFailureReason.permissionDeniedForever:
            currentLocation.value = 'Location unavailable';
            locationFailureReason.value = result.reason;
            break;
          case LocationFailureReason.positionUnavailable:
            currentLocation.value = "Couldn't get location";
            locationFailureReason.value =
                LocationFailureReason.positionUnavailable;
            break;
          default:
            currentLocation.value = 'Location unavailable';
            locationFailureReason.value = result.reason;
        }
      }
    } catch (_) {
      currentLocation.value = 'Location unavailable';
      locationFailureReason.value = LocationFailureReason.positionUnavailable;
      currentLatLng.value = null;
    } finally {
      isLoadingLocation.value = false;
    }
    // Fetch top-rated doctors once location resolves (even if failed)
    fetchTopDoctors();
  }

  /// Fetch top-rated doctors nearby — populates [topDoctors] with up to
  /// 6 highly-rated results.  Called automatically after location loads.
  /// Only re-fetches if at least 10 minutes have passed to avoid excessive
  /// Google Places API calls.
  Future<void> fetchTopDoctors() async {
    if (isLoadingTopDoctors.value) return;
    if (_lastTopDoctorFetch != null &&
        DateTime.now().difference(_lastTopDoctorFetch!).inMinutes < 10) {
      return;
    }
    isLoadingTopDoctors.value = true;

    try {
      var lat = _locationService.currentPosition?.latitude;
      var lng = _locationService.currentPosition?.longitude;
      // Fall back to the last saved GPS fix if a fresh one isn't available.
      if (lat == null || lng == null) {
        final saved = _storage.getLastLatLng();
        if (saved != null && saved.length == 2) {
          lat = saved[0];
          lng = saved[1];
        }
      }
      final result = await PlacesService().searchNearbyHealthcare(
        keyword: 'top rated doctor clinic hospital',
        latitude: lat,
        longitude: lng,
        // Use the user-selected search radius (default 5 km) so the home
        // screen respects the same radius preference as the search screen.
        radius: _storage.getSearchRadiusKm() * 1000,
      );

      // Sort by rating descending, take top 6
      final sorted = List<DoctorModel>.from(result.doctors)
        ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

      topDoctors.value = sorted.take(6).toList();
      _lastTopDoctorFetch = DateTime.now();
    } catch (_) {
      // Silently fail — the section just stays empty
    } finally {
      isLoadingTopDoctors.value = false;
    }
  }

  /// Public method for pull-to-refresh and manual refresh. If GPS is off
  /// the GPS-off alert blocks the refresh until the user enables it.
  Future<void> refreshLocation() async {
    if (!await ensureGpsEnabled()) return;
    await _fetchLocation();
  }

  /// Public method to request location permission from UI. If GPS is off
  /// the GPS-off alert is shown first so the permission prompt isn't
  /// wasted on a device that can't produce a fix anyway.
  Future<void> requestLocationPermission() async {
    if (!await ensureGpsEnabled()) return;
    await _locationService.requestPermission();
    await _fetchLocation();
  }

  /// Gate for location-dependent actions: when GPS is off, shows the
  /// GPS-off alert (with an Open-Settings action) and blocks the action
  /// until the user enables it. Returns `true` when GPS is on. Shared
  /// implementation with the doctor-side screens — see
  /// `widgets/gps_off_dialog.dart`.
  Future<bool> ensureGpsEnabled() =>
      gps.ensureGpsEnabled(gpsCheck: isGpsEnabledOverride);

  /// Automatic (once-per-session) GPS-off popup for the patient home page:
  /// when GPS is disabled the home screen shows a dismissible alert with an
  /// Open-Settings action instead of silently sitting on "GPS is off".
  ///
  /// Navigator-safe: the controller lives across logout/login (permanent),
  /// so the delay + navigator guard keep a popup from firing before the
  /// widget tree is ready (and [isGpsEnabledOverride] lets tests drive the
  /// "check again" button). If the user enables GPS from the dialog the
  /// location refetches immediately.
  Future<void> _maybeShowGpsOffPopup() async {
    if (_hasShownGpsOffPopup) return;
    // Claim the flag synchronously BEFORE the delay: two concurrent
    // _fetchLocation calls (e.g. the 60s refresh racing a pull-to-refresh)
    // would otherwise both pass the check above and stack two dialogs.
    _hasShownGpsOffPopup = true;
    await Future.delayed(const Duration(milliseconds: 600));
    if (Get.key.currentState == null) {
      // Navigator not ready yet (controller created before runApp) —
      // release the claim so the next refresh retries.
      _hasShownGpsOffPopup = false;
      return;
    }
    final enabled = await gps.showGpsOffDialog(
      dismissible: true,
      gpsCheck: isGpsEnabledOverride,
    );
    if (enabled) await _fetchLocation();
  }

  /// Test hook — triggers [_fetchLocation] without starting the real
  /// onInit timer chain, so tests can simulate the home page loading with
  /// GPS off (see [fetchLocationOverride]).
  @visibleForTesting
  Future<void> debugFetchLocation() => _fetchLocation();

  /// Open device location settings (called when GPS is off)
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
    await Future.delayed(const Duration(seconds: 2));
    await _fetchLocation();
  }

  String get userName {
    final name = _authController.currentUser.value?.name ?? 'User';
    if (name.isEmpty) return 'User';
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  /// Navigate to the Doctor Search screen.
  void goToDoctorSearch() {
    Get.toNamed(AppRoutes.doctorSearch);
  }

  /// Navigate to the Appointment History screen.
  void goToAppointmentHistory() {
    Get.toNamed(AppRoutes.appointmentHistory);
  }

  /// Navigate to the Profile screen.
  void goToProfile() {
    Get.toNamed(AppRoutes.profile);
  }

  /// Activate the AI assistant — used by the center FAB in bottom nav.
  /// When called from another tab, this navigates to the home screen
  /// and triggers the mic for voice input.  If already on home, it
  /// just starts listening.
  void activateAiAssistant() {
    final voiceController = Get.find<VoiceController>();
    if (!voiceController.isListening.value &&
        !voiceController.isProcessing.value) {
      voiceController.startListening();
    }
  }

  /// Search for a specific [specialist] — triggers the doctor search
  /// via [DoctorSearchController] and navigates to the search screen.
  /// GPS-off shows the GPS alert first (the search needs a location fix).
  Future<void> searchDoctors(String specialist, {List<String>? symptoms}) async {
    if (!await ensureGpsEnabled()) return;
    final ctrl = Get.find<DoctorSearchController>();
    ctrl.pendingSearchSpecialization.value = specialist;
    ctrl.pendingSymptoms.value = symptoms ?? [];
    Get.toNamed(AppRoutes.doctorSearch, arguments: {'specialist': specialist});
  }
}
