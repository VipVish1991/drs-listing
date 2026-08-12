import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/services/places_service.dart';

/// Builds the cache key for a [PlacesService.searchNearbyHealthcare] search,
/// using the same query composition and key format as the service so tests
/// never hardcode a key string that can drift from production.
String nearbyHealthcareCacheKey({
  String? specialization,
  String? keyword,
  double? latitude,
  double? longitude,
  int radius = AppConstants.placesSearchRadius,
}) {
  return PlacesService.searchCacheKey(
    query: PlacesService.nearbyTextQuery(
      specialization: specialization,
      keyword: keyword,
    ),
    latitude: latitude,
    longitude: longitude,
    radius: radius,
  );
}

/// Builds the cache key for a [PlacesService.textSearchDoctors] search
/// (the query is trimmed exactly as the service trims it).
String textSearchCacheKey({
  required String query,
  double? latitude,
  double? longitude,
  int radius = AppConstants.placesSearchRadius,
}) {
  return PlacesService.searchCacheKey(
    query: query.trim(),
    latitude: latitude,
    longitude: longitude,
    radius: radius,
  );
}

/// Builds the cache key for a [PlacesService.getDoctorDetails] lookup.
String doctorDetailCacheKey(String placeId) {
  return PlacesService.detailCacheKey(placeId);
}

/// The storage prefix under which every Places cache entry is persisted.
/// Mirrors [LocalStorageService.savePlacesCache]'s key construction so
/// tests that reach into prefs directly stay in sync.
String placesCachePrefsKey(String cacheKey) {
  return '${AppConstants.placesCachePrefix}$cacheKey';
}
