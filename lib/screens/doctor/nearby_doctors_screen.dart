import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../models/user_model.dart';
import '../../routes/app_routes.dart';
import '../../services/location_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/places_service.dart';
import '../../services/supabase_service.dart';
import '../../models/doctor_model.dart';
import '../../utils/distance_formatter.dart';
import '../../utils/place_type.dart';
import '../../utils/snackbar_helpers.dart';
import '../../widgets/confirm_continue_button.dart';
import '../../widgets/gps_off_dialog.dart';
import '../../widgets/haptic_button.dart';

/// Shows a list of nearby healthcare places (clinics, doctors, hospitals)
/// within a 5 km radius. Each card shows full details, calculated
/// distance, and a "Connect" button. A search field at the top lets
/// the user filter the list by name.
///
/// When navigated from [DoctorRegisterScreen] with `mode: 'register'`
/// args, switches to registration mode where tapping a place navigates
/// to OTP verification instead of the normal Connect flow.
class NearbyDoctorsScreen extends StatefulWidget {
  const NearbyDoctorsScreen({super.key});

  /// Test hook — replaces the real GPS-service probe (a platform call that
  /// throws MissingPluginException / hangs on bare test bindings) so widget
  /// tests can force GPS off/on deterministically.
  @visibleForTesting
  static Future<bool> Function()? gpsCheckOverride;

  /// Test hook — replaces the real SupabaseService for the
  /// "already registered as a doctor" check so widget tests can
  /// deterministically simulate a previously-registered mobile (or a
  /// fresh one) without hitting the live backend.
  @visibleForTesting
  static SupabaseService Function()? supabaseOverride;

  @override
  State<NearbyDoctorsScreen> createState() => _NearbyDoctorsScreenState();
}

class _NearbyDoctorsScreenState extends State<NearbyDoctorsScreen> {
  final LocationService _locationService = LocationService();
  final PlacesService _placesService = PlacesService();
  final LocalStorageService _storage = LocalStorageService();
  final TextEditingController _searchController = TextEditingController();

  /// Search radius in metres — honours the user's stored preference
  /// (default 5 km) instead of hardcoding 50 km.
  int get _radiusMeters => _storage.getSearchRadiusKm() * 1000;

  final RxList<DoctorModel> allPlaces = <DoctorModel>[].obs;
  final Rx<DoctorModel?> selectedDoctor = Rx<DoctorModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool isRefreshing = false.obs;
  final RxBool isSearching = false.obs;
  final RxBool showSlowSearchWarning = false.obs;
  final RxString errorMessage = ''.obs;
  final RxString searchQuery = ''.obs;

  /// Active type filter chip: 'All', 'Clinic', 'Hospital', or 'Doctor'.
  final RxString selectedFilter = 'All'.obs;

  /// Filter chip options.
  static const List<String> _filterOptions = [
    'All',
    'Clinic',
    'Hospital',
    'Doctor',
  ];

  /// Determine the display type of a place based on its types.
  /// Mirrors the logic in [_PlaceCardState._typeLabel].
  String _getPlaceType(DoctorModel place) => getPlaceType(place);

  // ── Registration mode (from DoctorRegisterScreen) ──
  bool _registrationMode = false;
  String _regDisplayName = '';
  String _regMobile = '';
  String _regRole = UserModel.roleDoctor;

  /// True when the registration mobile already belongs to a registered
  /// doctor (a `users` row with role 'doctor'). When set, the "Select &
  /// Continue" button is disabled — the doctor already manages a clinic
  /// and shouldn't re-register (they should log in instead). Reactive so
  /// the card buttons + notice update as soon as the check lands.
  final RxBool _registrationBlocked = false.obs;

  /// Google Place IDs already registered in the Supabase `doctors` table.
  /// In registration mode, any nearby-Google-result card whose place_id
  /// is in this set is disabled — that clinic/hospital/doctor is already
  /// registered and can't be claimed twice. Reactive so cards update as
  /// soon as the list lands.
  final RxSet<String> _registeredDoctorPlaceIds = <String>{}.obs;

  /// Debounce timer for text search — waits 400ms after the user stops
  /// typing before firing the API call.
  Timer? _searchDebounce;

  /// Cached user position so we don't re-fetch location on every search.
  Position? _userPosition;

  /// The initial nearby places before the user typed a search query.
  /// Saved so we can restore them when the search is cleared.
  final RxList<DoctorModel> _initialNearbyPlaces = <DoctorModel>[].obs;

  /// Whether we're currently showing search results (vs. nearby results).
  bool get _isSearchActive => searchQuery.value.trim().length >= 2;

  /// Display list — applies both search/initial results AND the active
  /// type filter chip.
  List<DoctorModel> get _filteredPlaces {
    final filter = selectedFilter.value;
    if (filter == 'All') return allPlaces;
    return allPlaces.where((p) => _getPlaceType(p) == filter).toList();
  }

  @override
  void initState() {
    super.initState();
    _readArgs();
    if (_registrationMode) {
      _checkDoctorAlreadyRegistered();
      _loadRegisteredDoctorPlaceIds();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearbyPlaces());
  }

  /// In registration mode, check whether the entered mobile number is
  /// already a registered doctor. If it is, "Select & Continue" is
  /// disabled (with an explanatory notice) so the doctor can't create a
  /// duplicate clinic profile. Fails open — a check error (offline,
  /// uninitialized Supabase) never blocks a legitimate registration.
  Future<void> _checkDoctorAlreadyRegistered() async {
    try {
      final supabase =
          NearbyDoctorsScreen.supabaseOverride?.call() ?? SupabaseService();
      final user = await supabase.getUserByMobile(_regMobile);
      if (!mounted) return;
      _registrationBlocked.value = user?['role'] == UserModel.roleDoctor;
    } catch (_) {
      // Fail open: leave the button enabled.
    }
  }

  /// In registration mode, fetch every Google Place ID already present in
  /// the Supabase `doctors` table. Any nearby result whose place_id
  /// matches is already registered and its card is disabled. Fails open —
  /// a fetch error never blocks a legitimate registration.
  Future<void> _loadRegisteredDoctorPlaceIds() async {
    try {
      final supabase =
          NearbyDoctorsScreen.supabaseOverride?.call() ?? SupabaseService();
      final ids = await supabase.getRegisteredDoctorPlaceIds();
      if (!mounted) return;
      _registeredDoctorPlaceIds.assignAll(ids);
    } catch (_) {
      // Fail open: leave all cards enabled.
    }
  }

  /// Read route arguments to detect registration mode.
  void _readArgs() {
    final args = Get.arguments;
    if (args is Map && args['mode'] == 'register') {
      _registrationMode = true;
      _regDisplayName = args['displayName']?.toString() ?? '';
      _regMobile = args['mobile']?.toString() ?? '';
      _regRole = args['role']?.toString() ?? UserModel.roleDoctor;
    }
  }

  /// Called when the user types in the search field. Debounces input and
  /// fires a text search API call after 400ms of inactivity.
  void _onSearchChanged(String value) {
    searchQuery.value = value;
    _searchDebounce?.cancel();

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      // Restore initial nearby results
      isSearching.value = false;
      allPlaces.value = _initialNearbyPlaces;
      errorMessage.value = '';
      return;
    }

    if (trimmed.length < 2) {
      // Too short to search — keep current list
      return;
    }

    // Debounce: wait 400ms after last keystroke
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _performTextSearch(trimmed);
    });
  }

  /// Perform a text search using the Google Places API.
  /// Slow-search timer reference so we can cancel it if the API returns
  /// before the 5-second mark.
  Timer? _slowSearchTimer;

  Future<void> _performTextSearch(String query) async {
    if (query.isEmpty) return;

    // A NEW search must never be served stale cached results — drop the
    // previously cached search entries so this request hits the live
    // Google API (fresh listings every time).
    await _placesService.clearSearchCache();

    isSearching.value = true;
    showSlowSearchWarning.value = false;
    errorMessage.value = '';

    // After 5 seconds of no response, switch from shimmer to a
    // visible "Still searching…" message so the user knows we
    // haven't stalled.
    _slowSearchTimer?.cancel();
    _slowSearchTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && isSearching.value) {
        showSlowSearchWarning.value = true;
      }
    });

    try {
      final result = await _placesService.textSearchDoctors(
        query: query,
        latitude: _userPosition?.latitude,
        longitude: _userPosition?.longitude,
        radius: _radiusMeters,
      );

      _slowSearchTimer?.cancel();

      // Guard: if user cleared search while API was in-flight, discard
      // stale results and restore initial nearby places.
      if (!_isSearchActive) {
        allPlaces.value = _initialNearbyPlaces;
        return;
      }

      final places = result.doctors;

      if (places.isEmpty) {
        // If the API returned an explicit error, surface it so the user
        // can diagnose the issue.
        if (result.errorMessage != null) {
          errorMessage.value = result.errorMessage!;
        } else {
          errorMessage.value = 'No results found for "$query"';
        }
      } else {
        // Calculate distance from user's location and store raw meters
        // for numeric sorting (string compare on "1.2 km" vs "10 km"
        // would give incorrect alphabetical ordering).
        final Map<String, double> distanceMeters = {};
        if (_userPosition != null) {
          for (int i = 0; i < places.length; i++) {
            final place = places[i];
            if (place.latitude != null && place.longitude != null) {
              final meters = Geolocator.distanceBetween(
                _userPosition!.latitude,
                _userPosition!.longitude,
                place.latitude!,
                place.longitude!,
              );
              distanceMeters[place.placeId] = meters;
              places[i] = place.copyWith(distance: formatDistance(meters));
            }
          }
        }

        // Sort by distance ascending (nearest first).
        // Places that couldn't be measured (no lat/lng) go to the end.
        places.sort((a, b) {
          final aDist = distanceMeters[a.placeId];
          final bDist = distanceMeters[b.placeId];
          if (aDist == null && bDist == null) return 0;
          if (aDist == null) return 1;
          if (bDist == null) return -1;
          return aDist.compareTo(bDist);
        });

        allPlaces.value = places;
      }
    } catch (e) {
      errorMessage.value = 'Search timed out or failed. Please try again.';
    } finally {
      _slowSearchTimer?.cancel();
      isSearching.value = false;
      showSlowSearchWarning.value = false;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _slowSearchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Separate refresh handler — keeps the existing list visible while
  /// re-fetching data instead of replacing it with a shimmer skeleton.
  /// If the refresh fails, the previous list is restored so the user
  /// doesn't see an abrupt empty state.
  Future<void> _onRefresh() async {
    isRefreshing.value = true;
    final saved = allPlaces.toList();
    try {
      await _loadNearbyPlaces();
      // If refresh returned nothing and set an error, restore old data
      if (allPlaces.isEmpty && errorMessage.value.isNotEmpty) {
        allPlaces.value = saved;
      }
    } finally {
      isRefreshing.value = false;
    }
  }

  Future<void> _loadNearbyPlaces() async {
    // GPS gate — the Places API *requires* a lat/lng fix, so when GPS is
    // off the non-dismissible GPS-off alert blocks the load (instead of
    // silently showing an empty list) until the user enables it and taps
    // check-again; the pending load then proceeds automatically. Covers
    // the initial open, pull-to-refresh and the retry buttons alike.
    if (!await ensureGpsEnabled(
      gpsCheck: NearbyDoctorsScreen.gpsCheckOverride,
    )) {
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    allPlaces.clear();

    try {
      // Fetch current location first — the Places API *requires*
      // a lat/lng for nearby results; without it the call returns
      // empty or geographically irrelevant data.
      var position = _locationService.currentPosition;
      position ??= await _locationService.getCurrentLocation();
      _userPosition = position; // Cache for text search

      // ── Fetch nearby healthcare places using the New Places Text
      // Search API — gives location-biased results.
      final result = await _placesService.searchNearbyHealthcare(
        latitude: position?.latitude,
        longitude: position?.longitude,
        radius: _radiusMeters,
      );

      final clinics = result.doctors;

      if (clinics.isEmpty) {
        // If the API returned an explicit error, show it to the user
        // so they can diagnose the issue (e.g. "API key not enabled").
        if (result.errorMessage != null) {
          errorMessage.value = result.errorMessage!;
        } else {
          errorMessage.value = 'No healthcare places found nearby.';
        }
      } else {
        // Calculate distance from user's location and store raw meters
        // for numeric sorting (string compare on "1.2 km" vs "10 km"
        // would give incorrect alphabetical ordering).
        final Map<String, double> distanceMeters = {};
        if (position != null) {
          for (int i = 0; i < clinics.length; i++) {
            final place = clinics[i];
            if (place.latitude != null && place.longitude != null) {
              final meters = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                place.latitude!,
                place.longitude!,
              );
              distanceMeters[place.placeId] = meters;
              clinics[i] = place.copyWith(distance: formatDistance(meters));
            }
          }
        }

        // Sort by distance ascending (nearest first).
        // Places that couldn't be measured (no lat/lng) go to the end.
        clinics.sort((a, b) {
          final aDist = distanceMeters[a.placeId];
          final bDist = distanceMeters[b.placeId];
          if (aDist == null && bDist == null) return 0;
          if (aDist == null) return 1; // a goes to bottom
          if (bDist == null) return -1; // b goes to bottom
          return aDist.compareTo(bDist);
        });

        allPlaces.value = clinics;
        _initialNearbyPlaces.value = clinics;
      }
    } catch (e) {
      errorMessage.value =
          'Could not load nearby places. Please check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  /// Handle the place selection:
  /// - In **registration mode**: show a confirmation dialog summarising
  ///   the selected clinic + registrant name before navigating to OTP.
  /// - In **normal mode**: save doctor to database, upgrade user role
  ///   to doctor, store the doctor's place ID, and show the success
  ///   dialog with "Go to Dashboard" button.
  Future<void> _onConnect(DoctorModel place) async {
    // ── Registration mode: show confirmation dialog first ──
    if (_registrationMode) {
      await _showRegistrationConfirmation(place);
      return;
    }

    // ── Normal mode (existing flow) ──
    final auth = Get.find<AuthController>();

    // If user is not logged in, redirect to login with pendingDoctor
    if (auth.currentUser.value == null) {
      Get.toNamed(AppRoutes.login, arguments: {'pendingDoctor': place});
      return;
    }

    try {
      await auth.showConnectedDialog(place);
    } catch (e) {
      debugPrint('❌ Failed to save doctor to DB: $e');
      showErrorSnackbar(
        'Failed to save doctor. Please ensure the doctors table exists '
        'in your Supabase project (run the migration SQL) and try again.',
      );
    }
  }

  /// Show a confirmation dialog summarising the selected clinic and the
  /// registrant's details. The user can confirm to proceed to OTP or
  /// cancel to choose a different clinic.
  Future<void> _showRegistrationConfirmation(DoctorModel place) async {
    if (Get.context == null) return;

    final context = Get.context!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;

    // Extract clinic initials
    final initials = _extractInitials(place.name);

    await Get.dialog(
      PopScope(
        canPop: true,
        child: Container(
          color: Colors.black54,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppColors.bgMain,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Clinic avatar ──
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.primary, AppColors.secondary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(50),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Title ──
                      Text(
                        'Confirm Selection',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Clinic info card ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primary.withAlpha(30),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withAlpha(20),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.local_hospital_rounded,
                                    color: AppColors.primary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Clinic / Hospital',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: bodyColor.withAlpha(180),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        place.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textHeading,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Divider(
                              height: 1,
                              color: AppColors.primary.withAlpha(30),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withAlpha(20),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.person_outline,
                                    color: AppColors.accent,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Registering as',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: bodyColor.withAlpha(180),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _regDisplayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textHeading,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withAlpha(15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Doctor',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Confirm & Continue button (shows a loading
                      // spinner in the button while confirming) ──
                      ConfirmContinueButton(
                        onPressed: () {
                          Get.back(); // close confirmation
                          Get.toNamed(
                            AppRoutes.otpVerification,
                            arguments: {
                              'displayName': _regDisplayName,
                              'mobile': _regMobile,
                              'role': _regRole,
                              'doctor': place,
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      // ── Choose Different button ──
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: Get.back,
                          child: const Text(
                            'Choose Different',
                            style: TextStyle(
                              color: AppColors.textCaption,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      barrierDismissible: true,
    );
  }

  /// Extract initials from a clinic/hospital name for the avatar.
  String _extractInitials(String name) {
    final parts = name
        .replaceFirst('Dr. ', '')
        .replaceFirst('Dr ', '')
        .replaceFirst(RegExp(r'\bClinic\b', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\bHospital\b', caseSensitive: false), '')
        .trim()
        .split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Build the main content area (shimmer, error, empty, or list).
  /// Extracted so it can be wrapped in an [AnimatedSwitcher] with a
  /// dynamic key for smooth crossfades when the filter chip changes.
  Widget _buildContentArea({
    required bool isDark,
    required Color textColor,
    required Color bodyColor,
  }) {
    // On initial load: show shimmer
    if (isLoading.value && !isRefreshing.value) {
      return _buildShimmerList(isDark);
    }

    // Show shimmer while searching via API
    if (isSearching.value && !showSlowSearchWarning.value) {
      return _buildShimmerList(isDark);
    }

    // After 5 seconds, show a more informative slow-search state
    if (isSearching.value && showSlowSearchWarning.value) {
      return _buildSlowSearchState(textColor, bodyColor);
    }

    if (errorMessage.value.isNotEmpty && !isRefreshing.value) {
      return _buildErrorState(textColor, bodyColor);
    }

    final displayList = _filteredPlaces;

    if (displayList.isEmpty && !isRefreshing.value) {
      if (_isSearchActive) {
        return _buildNoSearchResults(textColor, bodyColor);
      }
      return _buildEmptyState(textColor, bodyColor);
    }

    // Show existing list during pull-to-refresh (no shimmer)
    final canRefresh = !_isSearchActive;
    final listView = ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      itemCount: displayList.length,
      itemBuilder: (context, index) {
        final place = displayList[index];
        final isSelected = selectedDoctor.value?.placeId == place.placeId;
        return _PlaceCard(
          place: place,
          index: index,
          isDark: isDark,
          textColor: textColor,
          bodyColor: bodyColor,
          isSelected: isSelected,
          isRegistrationMode: _registrationMode,
          // Disabled when the mobile is already a registered doctor OR
          // when this exact clinic/hospital/doctor is already registered
          // in the doctors table (place_id match against Google results).
          registrationBlocked: _registrationBlocked.value ||
              _registeredDoctorPlaceIds.contains(place.placeId),
          onSelect: () => selectedDoctor.value = place,
          onConnect: () => _onConnect(place),
        );
      },
    );

    if (canRefresh) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppColors.primary,
        child: listView,
      );
    }
    return listView;
  }

  /// Build the type filter chip row: All | Clinic | Hospital | Doctor.
  Widget _buildFilterChips() {
    return Obx(() {
      final current = selectedFilter.value;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: _filterOptions.map((option) {
            final isSelected = current == option;
            IconData? icon;
            switch (option) {
              case 'All':
                icon = Icons.all_inclusive_rounded;
                break;
              case 'Clinic':
                icon = Icons.local_hospital_rounded;
                break;
              case 'Hospital':
                icon = Icons.business_rounded;
                break;
              case 'Doctor':
                icon = Icons.person_rounded;
                break;
            }
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: HapticButton(
                scaleEnd: 0.95,
                hapticType: HapticFeedbackType.selectionClick,
                animationDuration: const Duration(milliseconds: 150),
                onTap: () => selectedFilter.value = option,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.primary.withAlpha(40),
                      width: isSelected ? 0 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(50),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: isSelected ? Colors.white : AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        option,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textHeading,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        // Chip count badge
                        Obx(() {
                          final count = _filteredPlaces.length;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0.0, 0.6, 1.0],
                  colors: [
                    AppColors.primary,
                    AppColors.primaryDark,
                    const Color(0xFF086B55),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(70),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: Get.back,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha(25),
                            border: Border.all(
                              color: Colors.white.withAlpha(40),
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _registrationMode
                                  ? 'Select Your Clinic'
                                  : 'Nearby Healthcare',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.local_hospital,
                                  size: 13,
                                  color: Colors.white.withAlpha(170),
                                ),
                                const SizedBox(width: 4),
                                Obx(() {
                                  final count = _filteredPlaces.length;
                                  if (_registrationMode) {
                                    return Text(
                                      'Pick your clinic below',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withAlpha(170),
                                      ),
                                    );
                                  }
                                  if (_isSearchActive) {
                                    final label = count == 1
                                        ? 'result'
                                        : 'results';
                                    return Text(
                                      '$count $label found',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withAlpha(170),
                                      ),
                                    );
                                  }
                                  final label = count == 1 ? 'place' : 'places';
                                  final radiusKm = _storage.getSearchRadiusKm();
                                  return Text(
                                    '$count $label within $radiusKm km',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withAlpha(170),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── Search field ──
                  Obx(() {
                    final isActivelySearching = isSearching.value;
                    final hasQuery = searchQuery.value.isNotEmpty;
                    return TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (value) {
                        _searchDebounce?.cancel();
                        _performTextSearch(value.trim());
                        FocusScope.of(context).unfocus();
                      },
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: isActivelySearching
                            ? 'Searching...'
                            : 'Search clinic, doctor, hospital...',
                        hintStyle: TextStyle(
                          color: Colors.white.withAlpha(120),
                          fontSize: 15,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        suffixIcon: hasQuery || isActivelySearching
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isActivelySearching)
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white.withAlpha(170),
                                        ),
                                      ),
                                    )
                                  else
                                    HapticButton(
                                      scaleEnd: 0.90,
                                      onTap: () {
                                        _searchDebounce?.cancel();
                                        _performTextSearch(
                                          _searchController.text.trim(),
                                        );
                                        FocusScope.of(context).unfocus();
                                      },
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(40),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.search_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 4),
                                  HapticButton(
                                    scaleEnd: 0.90,
                                    hapticType:
                                        HapticFeedbackType.selectionClick,
                                    onTap: () {
                                      _searchController.clear();
                                      // clear() triggers onChanged → _onSearchChanged('')
                                    },
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.white.withAlpha(170),
                                      size: 22,
                                    ),
                                  ),
                                ],
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withAlpha(25),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.white.withAlpha(40),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0),

            // ── Filter chips ──
            _buildFilterChips()
                .animate()
                .fadeIn(duration: 300.ms, delay: 200.ms)
                .slideY(begin: -0.05, end: 0),

            // ── Already-registered notice (registration mode) ──
            // Shown while the entered mobile already belongs to a
            // registered doctor — explains why every "Select & Continue"
            // button below is disabled.
            Obx(() {
              // Read the observable unconditionally so GetX registers the
              // dependency even when the notice is hidden (normal mode /
              // check still in flight) — otherwise GetX flags the Obx as
              // "improper use" for building without any reactive value.
              final registrationBlocked = _registrationBlocked.value;
              if (!_registrationMode || !registrationBlocked) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withAlpha(18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.warning.withAlpha(70),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This mobile number is already registered as a '
                          'doctor. Please log in to manage your clinic '
                          'instead.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: bodyColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // ── Content (with smooth crossfade when filter/search changes) ──
            Expanded(
              child: Obx(() {
                final viewKey = '${selectedFilter.value}$_isSearchActive';
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeIn,
                  switchOutCurve: Curves.easeOut,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: KeyedSubtree(
                    key: ValueKey(viewKey),
                    child: _buildContentArea(
                      isDark: isDark,
                      textColor: textColor,
                      bodyColor: bodyColor,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      // (bottom connect bar intentionally removed per user request)
    );
  }

  // ── States ──

  /// Shows a centered message with a visible spinner after the search has
  /// been running for more than 5 seconds, informing the user we're still
  /// working on it rather than leaving them staring at silent shimmer.
  Widget _buildSlowSearchState(Color textColor, Color bodyColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withAlpha(18),
              ),
              child: const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Still searching…',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This is taking longer than expected.\nYou can wait or try a different search term.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: bodyColor, height: 1.4),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                final query = searchQuery.value.trim();
                if (query.isNotEmpty) {
                  _performTextSearch(query);
                }
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withAlpha(120)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shimmer ──

  Widget _buildShimmerList(bool isDark) {
    final baseColor = isDark
        ? const Color(0xFF2A2A3E)
        : const Color(0xFFE8E4DA);
    final highlightColor = isDark
        ? const Color(0xFF3A3A4E)
        : const Color(0xFFF4EFE4);

    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildShimmerBox(56, 56, borderRadius: 16),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildShimmerBox(180, 16),
                          const SizedBox(height: 6),
                          _buildShimmerBox(120, 12),
                          const SizedBox(height: 6),
                          _buildShimmerBox(80, 10),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildShimmerBox(double.infinity, 36, borderRadius: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerBox(
    double width,
    double height, {
    double borderRadius = 8,
  }) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  // ── States ──

  Widget _buildErrorState(Color textColor, Color bodyColor) {
    // The AnimatedSwitcher already crossfades between states — this adds
    // the fade + slide entrance on top so the ERROR state itself arrives
    // with the same motion as the app's other error/warning notices.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withAlpha(25),
              ),
              child: const Icon(
                Icons.cloud_off,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage.value,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: bodyColor),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _loadNearbyPlaces,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withAlpha(120)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.08, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }

  Widget _buildEmptyState(Color textColor, Color bodyColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgSecondarySurface,
            ),
            child: const Icon(
              Icons.search_off,
              size: 40,
              color: AppColors.textCaption,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No healthcare places found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try expanding your search area',
            style: TextStyle(fontSize: 14, color: bodyColor),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _loadNearbyPlaces,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withAlpha(120)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults(Color textColor, Color bodyColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bgSecondarySurface,
              ),
              child: const Icon(
                Icons.search_off,
                size: 32,
                color: AppColors.textCaption,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No matches for "${_searchController.text}"',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different name or address',
              style: TextStyle(fontSize: 14, color: bodyColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────
/// Individual place card (doctor / clinic / hospital)
/// ─────────────────────────────────────────────────────────────────────
class _PlaceCard extends StatefulWidget {
  final DoctorModel place;
  final int index;
  final bool isDark;
  final Color textColor;
  final Color bodyColor;
  final bool isSelected;
  final bool isRegistrationMode;

  /// When true (registration mode + the mobile already registered as a
  /// doctor), the "Select & Continue" button is disabled and a hint is
  /// shown instead of the forward arrow.
  final bool registrationBlocked;
  final VoidCallback onSelect;
  final VoidCallback? onConnect;

  const _PlaceCard({
    required this.place,
    required this.index,
    required this.isDark,
    required this.textColor,
    required this.bodyColor,
    this.isSelected = false,
    this.isRegistrationMode = false,
    this.registrationBlocked = false,
    required this.onSelect,
    this.onConnect,
  });

  @override
  State<_PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<_PlaceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _cardScaleAnim;

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.18,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    // Very subtle card-scale pulse (1.2%) so the border and shadow
    // breathe in sync with the checkmark.
    _cardScaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.012,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _pulseCtrl.addStatusListener(_onPulseStatus);
    _pulseCtrl.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(_PlaceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      // Stagger: wait for border transition to begin, then start pulse
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && widget.isSelected) _pulseCtrl.forward();
      });
    } else if (!widget.isSelected && oldWidget.isSelected) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.removeStatusListener(_onPulseStatus);
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onPulseStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _pulseCtrl.reverse();
    } else if (status == AnimationStatus.dismissed) {
      _pulseCtrl.forward();
    }
  }

  // ── Derived helpers from widget props ──

  String get _typeLabel => getPlaceType(widget.place);

  Color get _typeColor => getPlaceTypeColor(_typeLabel);

  String get _initials {
    final parts = widget.place.name
        .replaceFirst('Dr. ', '')
        .replaceFirst('Dr ', '')
        .replaceFirst(RegExp(r'\bClinic\b', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\bHospital\b', caseSensitive: false), '')
        .trim()
        .split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    // Border width pulses subtly when selected (2.0→3.0), synchronised
    // with the checkmark via _pulseAnim.
    final pulseT = (_pulseAnim.value - 1.0) / 0.18; // 0.0 → 1.0
    final borderColor = widget.isSelected
        ? AppColors.primary
        : widget.isDark
        ? Colors.white.withAlpha(15)
        : AppColors.primary.withAlpha(30);
    final borderWidth = widget.isSelected ? 2.0 + pulseT * 1.0 : 1.0;
    final shadowBlur = widget.isSelected ? 16.0 + pulseT * 8.0 : 12.0;
    final shadowAlpha = widget.isSelected
        ? (25 + (pulseT * 20).round()).clamp(0, 255)
        : 8;

    return Transform.scale(
          scale: widget.isSelected ? _cardScaleAnim.value : 1.0,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onSelect,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? Colors.white.withAlpha(10)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: [
                    BoxShadow(
                      color: widget.isSelected
                          ? AppColors.primary.withAlpha(shadowAlpha)
                          : Colors.black.withAlpha(
                              widget.isDark ? 0 : shadowAlpha,
                            ),
                      blurRadius: shadowBlur,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header row: avatar + info ──
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar with pulsing checkmark overlay when selected
                        Stack(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  colors: [
                                    _typeColor.withAlpha(200),
                                    _typeColor.withAlpha(160),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                            // Continuous pulsing checkmark overlay
                            if (widget.isSelected)
                              Positioned(
                                bottom: -2,
                                right: -2,
                                child: AnimatedBuilder(
                                  animation: _pulseAnim,
                                  builder: (context, child) => Transform.scale(
                                    scale: _pulseAnim.value,
                                    child: child,
                                  ),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.success,
                                      border: Border.all(
                                        color: widget.isDark
                                            ? const Color(0xFF0D1117)
                                            : const Color(0xFFF7F2E8),
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.place.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: widget.textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  // Type badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _typeColor.withAlpha(20),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      _typeLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: _typeColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Stars
                                  ...List.generate(
                                    5,
                                    (i) => Icon(
                                      i < (widget.place.rating ?? 0).floor()
                                          ? Icons.star
                                          : Icons.star_border,
                                      size: 14,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.place.rating != null
                                        ? widget.place.rating!.toStringAsFixed(
                                            1,
                                          )
                                        : '—',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: widget.bodyColor,
                                    ),
                                  ),
                                  // Pulsing "Selected" badge – synchronised with
                                  // the checkmark via the same _pulseAnim.
                                  if (widget.isSelected)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: AnimatedBuilder(
                                        animation: _pulseAnim,
                                        builder: (context, child) =>
                                            Transform.scale(
                                              scale: _pulseAnim.value,
                                              child: child,
                                            ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withAlpha(
                                              20,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'Selected',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Divider(
                      height: 1,
                      color: AppColors.textCaption.withAlpha(30),
                    ),
                    const SizedBox(height: 12),

                    // ── Details ──
                    if (widget.place.distance != null &&
                        widget.place.distance!.isNotEmpty) ...[
                      _DetailRow(
                        icon: Icons.near_me,
                        text: '${widget.place.distance} away',
                        bodyColor: AppColors.primary,
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (widget.place.address != null &&
                        widget.place.address!.isNotEmpty) ...[
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        text: widget.place.address!,
                        bodyColor: widget.bodyColor,
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (widget.place.phoneNumber != null &&
                        widget.place.phoneNumber!.isNotEmpty) ...[
                      _DetailRow(
                        icon: Icons.phone_outlined,
                        text: widget.place.phoneNumber!,
                        bodyColor: widget.bodyColor,
                      ),
                      const SizedBox(height: 6),
                    ],

                    const SizedBox(height: 12),

                    // ── Connect / Select & Continue button ──
                    // Disabled (registration mode) when the mobile is
                    // already registered as a doctor — the doctor already
                    // manages a clinic and should log in instead.
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: (widget.isRegistrationMode &&
                                widget.registrationBlocked)
                            ? null
                            : widget.onConnect,
                        icon: Icon(
                          widget.isRegistrationMode
                              ? Icons.arrow_forward_rounded
                              : Icons.phone,
                          size: 18,
                        ),
                        label: Text(
                          widget.isRegistrationMode
                              ? 'Select & Continue'
                              : 'Connect',
                          style: const TextStyle(fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (widget.isRegistrationMode &&
                        widget.registrationBlocked) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Already registered as a doctor',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms, delay: (widget.index * 80).ms)
        .slideY(begin: 0.05, end: 0, duration: 300.ms);
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color bodyColor;

  const _DetailRow({
    required this.icon,
    required this.text,
    required this.bodyColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textCaption),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: bodyColor),
          ),
        ),
      ],
    );
  }
}
