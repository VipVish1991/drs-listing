
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import '../config/constants.dart';
import '../models/doctor_model.dart';
import '../services/location_service.dart';
import '../services/local_storage_service.dart';
import '../services/places_service.dart';
import '../utils/distance_formatter.dart';
import '../utils/place_type.dart';

/// Available type filter options based on Google Places types.
const List<String> kTypeFilterOptions = ['All', 'Doctor', 'Clinic', 'Hospital', 'Pharmacy'];

class DoctorSearchController extends GetxController {
  final PlacesService _placesService = PlacesService();
  final LocationService _locationService = LocationService();
  final LocalStorageService _storage = LocalStorageService();

  final RxList<DoctorModel> doctors = <DoctorModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxString searchQuery = ''.obs;
  final RxString selectedSpecialization = ''.obs;
  final RxDouble minRating = 0.0.obs;
  final RxString filterType = 'All'.obs;
  final RxBool sortByDistance = true.obs;

  /// Current search radius in km — synced from local storage.
  final RxInt searchRadiusKm = AppConstants.defaultSearchRadiusKm.obs;

  /// External search trigger — set by [HomeController.searchDoctors] when
  /// the user taps \"Find [specialist]s near you\" from a chat bubble.
  final RxString pendingSearchSpecialization = ''.obs;

  /// Symptoms list from AI analysis — used to refine nearby clinic search.
  final RxList<String> pendingSymptoms = <String>[].obs;

  /// Error message to show when a search fails.
  final RxString errorMessage = ''.obs;

  /// Cached raw distances (placeId -> meters) for efficient sorting.
  final Map<String, double> _rawDistances = {};

  /// Last known position for radius filtering.
  double? _lastLatitude;
  double? _lastLongitude;

  Rx<DoctorModel?> selectedDoctor = Rx<DoctorModel?>(null);

  @override
  void onInit() {
    super.onInit();
    searchRadiusKm.value = _storage.getSearchRadiusKm();
    ever(searchRadiusKm, (km) => _storage.setSearchRadiusKm(km));
  }

  // ── Search ───────────────────────────────────────────────────────

  Future<void> searchDoctors({
    String? specialization,
    String? query,
  }) async {
    // A NEW search must never be served stale cached results — drop the
    // previously cached search entries so this request hits the live
    // Google API (fresh listings every time). Doctor-detail cache is kept.
    await _placesService.clearSearchCache();

    isLoading.value = true;
    errorMessage.value = '';
    doctors.clear();
    _rawDistances.clear();

    final searchSpec = specialization ?? selectedSpecialization.value;
    final searchQ = query ?? searchQuery.value;

    final position = _locationService.currentPosition;
    _lastLatitude = position?.latitude;
    _lastLongitude = position?.longitude;

    // Fall back to the last saved GPS fix (persisted on every app open)
    // so searches still get a location bias when a fresh fix is missing.
    if (_lastLatitude == null || _lastLongitude == null) {
      final saved = _storage.getLastLatLng();
      if (saved != null && saved.length == 2) {
        _lastLatitude = saved[0];
        _lastLongitude = saved[1];
      }
    }

    try {
      final result = await _placesService.searchNearbyHealthcare(
        specialization: searchSpec.isNotEmpty ? searchSpec : null,
        keyword: searchQ.isNotEmpty ? searchQ : null,
        latitude: _lastLatitude,
        longitude: _lastLongitude,
        radius: searchRadiusKm.value * 1000,
        symptoms: pendingSymptoms.isNotEmpty ? pendingSymptoms.toList() : null,
      );

      if (result.doctors.isEmpty) {
        errorMessage.value =
            'No doctors found. Try a different search or check your internet connection.';
      }

      final withDistances = _attachDistances(result.doctors);
      doctors.assignAll(withDistances);
    } catch (e) {
      errorMessage.value =
          'Failed to search. Please check your internet and try again.';
    } finally {
      isLoading.value = false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  List<DoctorModel> _attachDistances(List<DoctorModel> list) {
    if (_lastLatitude == null || _lastLongitude == null) return list;
    return list.map((d) {
      String? distanceText;
      if (d.latitude != null && d.longitude != null) {
        final meters = Geolocator.distanceBetween(
          _lastLatitude!,
          _lastLongitude!,
          d.latitude!,
          d.longitude!,
        );
        _rawDistances[d.placeId] = meters;
        distanceText = formatDistance(meters);
      }
      return d.copyWith(distance: distanceText);
    }).toList();
  }

  Future<void> searchBySpecialization(String specialization) async {
    selectedSpecialization.value = specialization;
    await searchDoctors(specialization: specialization);
  }

  void setFilter(String type) {
    filterType.value = type;
  }

  /// Determine the display type of a place based on its Google Places types.
  String _getPlaceType(DoctorModel place) => getPlaceType(place);

  /// Sets the active type filter.
  Future<void> setTypeFilter(String type) async {
    if (type == 'All') {
      filterType.value = 'All';
      return;
    }
    filterType.value = type;
    await searchDoctors(query: type.toLowerCase());
  }

  /// Returns true if [doctor] matches the current [filterType] filter.
  bool matchesFilterType(DoctorModel doctor) {
    final current = filterType.value;
    if (current == 'All') return true;
    return _getPlaceType(doctor) == current;
  }

  /// Returns the active type filter count — how many results match
  /// each available type, for badge display on filter chips.
  Map<String, int> get typeFilterCounts {
    final counts = <String, int>{};
    for (final type in kTypeFilterOptions) {
      if (type == 'All') {
        counts[type] = doctors.length;
      } else {
        counts[type] = doctors.where((d) => _getPlaceType(d) == type).length;
      }
    }
    return counts;
  }

  void toggleSortByDistance() {
    sortByDistance.value = !sortByDistance.value;
  }

  bool get isAnyFilterActive =>
      minRating.value > 0 ||
      sortByDistance.value ||
      filterType.value != 'All' ||
      selectedSpecialization.value.isNotEmpty;

  int get _radiusMeters => searchRadiusKm.value * 1000;

  @visibleForTesting
  void setTestFilterState({
    required double latitude,
    required double longitude,
    required Map<String, double> rawDistances,
  }) {
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _rawDistances
      ..clear()
      ..addAll(rawDistances);
  }

  List<DoctorModel> get filteredDoctors {
    // Work on a COPY — never on the RxList itself. `results.sort(...)`
    // below would otherwise call the reactive RxList.sort, which fires
    // refresh() and notifies the Obx that is currently building this
    // getter, throwing "setState() or markNeedsBuild() called during
    // build" (the filteredDoctors getter is consumed inside Obx builders).
    List<DoctorModel> results = doctors.toList();

    if (_lastLatitude != null && _lastLongitude != null) {
      results = results.where((d) {
        final raw = _rawDistances[d.placeId];
        if (raw == null) return true;
        return raw <= _radiusMeters;
      }).toList();
    }

    if (minRating.value > 0) {
      results =
          results.where((d) => (d.rating ?? 0) >= minRating.value).toList();
    }

    if (filterType.value != 'All') {
      results = results
          .where((d) => matchesFilterType(d))
          .toList();
    }

    if (sortByDistance.value) {
      results.sort((a, b) {
        final aDist = _rawDistances[a.placeId];
        final bDist = _rawDistances[b.placeId];
        if (aDist == null && bDist == null) return 0;
        if (aDist == null) return 1;
        if (bDist == null) return -1;
        return aDist.compareTo(bDist);
      });
    }

    return results;
  }

  void selectDoctor(DoctorModel doctor) {
    selectedDoctor.value = doctor;
  }

  void clearSearch() {
    doctors.clear();
    _rawDistances.clear();
    _lastLatitude = null;
    _lastLongitude = null;
    errorMessage.value = '';
    searchQuery.value = '';
    selectedSpecialization.value = '';
    pendingSymptoms.clear();
    minRating.value = 0.0;
    filterType.value = 'All';
    sortByDistance.value = true;
  }
}
