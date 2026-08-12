import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/doctor_model.dart';
import 'local_storage_service.dart';

/// Wrapper for the search response that includes the result list
/// and any API-level error message.
class PlacesSearchResult {
  final List<DoctorModel> doctors;
  final String? errorMessage;

  PlacesSearchResult({required this.doctors, this.errorMessage});
}

/// Service for interacting with the Google Places API.
///
/// Provides:
/// 1. **Text Search** (`searchNearbyHealthcare`) – finds nearby
///    doctors/clinics/hospitals using the Google Places Text Search API.
/// 2. **Text Search** (`textSearchDoctors`) – searches by name/query.
/// 3. **Place Details** (`getDoctorDetails`) – fetches full detail for a
///    single place by its Google Place ID.
/// 4. **Photos** (`getPhotoUrl`) – generates a photo URL from a reference.
class PlacesService {
  static final PlacesService _instance = PlacesService._internal();
  factory PlacesService() => _instance;
  PlacesService._internal();

  http.Client _client = http.Client();

  /// Injects a mock HTTP client so tests can stub Google Places responses
  /// without touching the network. Test-only; never called in production.
  @visibleForTesting
  void setClientForTesting(http.Client client) {
    _client = client;
  }

  final LocalStorageService _storage = LocalStorageService();

  /// Builds a stable cache key from the search parameters so repeat
  /// identical requests hit the local cache instead of the paid API.
  ///
  /// Public (static) so the test helper builds keys through the exact same
  /// logic — tests never hardcode a key string that can drift.
  static String searchCacheKey({
    required String query,
    double? latitude,
    double? longitude,
    int radius = AppConstants.placesSearchRadius,
  }) {
    final lat = latitude?.toStringAsFixed(3) ?? 'x';
    final lng = longitude?.toStringAsFixed(3) ?? 'x';
    // Full query text (not a hash) → zero collision risk. Keys are short-
    // lived (cache cleared on app close) so verbosity is not a concern.
    return 'search_${query}_${lat}_${lng}_${radius.toString()}';
  }

  /// Composes the natural text query used by [searchNearbyHealthcare]
  /// (e.g. "doctors clinics hospitals clinic"). Exposed so the test
  /// helper can reproduce the exact cache key without hardcoding it.
  static String nearbyTextQuery({
    String? specialization,
    String? keyword,
  }) {
    final parts = <String>['doctors', 'clinics', 'hospitals'];
    if (specialization != null && specialization.isNotEmpty) {
      parts.add(specialization);
    }
    if (keyword != null && keyword.isNotEmpty) {
      parts.add(keyword);
    }
    return parts.join(' ');
  }

  /// Builds the cache key for a single place's details payload.
  static String detailCacheKey(String placeId) => 'detail_$placeId';

  /// Returns cached search results for [key] if present and fresh, or
  /// `null` when nothing is cached (a real cache miss). An empty list is a
  /// valid cached result (e.g. ZERO_RESULTS) so it must be distinguishable
  /// from a miss — otherwise the API would be re-called on every attempt.
  List<DoctorModel>? _readSearchCache(String key) {
    final cached = _storage.getPlacesCache(key);
    if (cached == null) return null;
    try {
      final decoded = jsonDecode(cached) as List;
      return decoded
          .map((e) => DoctorModel.fromJson(e as Map<String, dynamic>))
          .where((d) => d.name.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Persists [doctors] under [key] so future identical requests are
  /// served locally (reduces Google Places API cost).
  ///
  /// Callers should await this so the cache is durably written before the
  /// search returns — otherwise a subsequent request could miss the cache
  /// and hit the paid API again.
  Future<void> _writeSearchCache(
    String key,
    List<DoctorModel> doctors,
  ) async {
    try {
      final json =
          jsonEncode(doctors.map((d) => d.toJson()).toList());
      await _storage.savePlacesCache(key, json);
    } catch (_) {
      // Caching is best-effort — never block the caller on a cache error.
    }
  }

  /// Return the proxy base URL if configured, otherwise fall back to
  /// the direct Google Places API URL.
  ///
  /// On web, the browser blocks direct calls to maps.googleapis.com
  /// (CORS).  Set [AppConstants.placesProxyUrl] to your Supabase Edge
  /// Function URL to route requests through a server-side proxy.
  String get _apiBaseUrl {
    final proxy = AppConstants.placesProxyUrl;
    return proxy.isNotEmpty ? proxy : AppConstants.googlePlacesBaseUrl;
  }

  /// Whether the server-side proxy is active.
  /// When `true`, the API key is injected server-side (via the proxy's
  /// environment variable) and should NOT be sent from the client.
  bool get _useProxy => AppConstants.placesProxyUrl.isNotEmpty;

  /// ────────────────────────────────────────────────────────────────
  /// Nearby Healthcare Search – uses Google Places Text Search API
  /// ────────────────────────────────────────────────────────────────
  /// Finds nearby healthcare places (clinics, doctors, hospitals) using
  /// the Google Places Text Search API with location bias.
  ///
  /// Internally calls:
  ///   GET /maps/api/place/textsearch/json
  ///       ?query={query}&location={lat},{lng}&radius={n}&key={key}
  ///
  /// [specialization] – optional medical specialty (e.g. "Cardiologist").
  /// [keyword]        – optional additional keyword (e.g. "clinic").
  /// [latitude]/[longitude] – bias results to this location.
  /// [radius]         – search radius in metres (default 5000 = 5 km).
  Future<PlacesSearchResult> searchNearbyHealthcare({
    String? specialization,
    double? latitude,
    double? longitude,
    int radius = AppConstants.placesSearchRadius,
    String? keyword,
    List<String>? symptoms,
  }) async {
    final key = AppConstants.googleMapsApiKey;
    if (key.isEmpty) {
      debugPrint('⚠️ Google Maps API key is empty!');
      return PlacesSearchResult(doctors: []);
    }

    try {
      // Build a natural text query like a user would type.
      final textQuery = nearbyTextQuery(
        specialization: specialization,
        keyword: keyword,
      );

      // ── Cache-first: serve repeat identical searches locally ──
      final cacheKey = searchCacheKey(
        query: textQuery,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
      );
      final cachedDoctors = _readSearchCache(cacheKey);
      if (cachedDoctors != null) {
        debugPrint('🧠 Places search served from cache: $cacheKey');
        return PlacesSearchResult(doctors: cachedDoctors);
      }

      final queryParams = <String, String>{
        'query': textQuery,
      };
      if (!_useProxy) {
        queryParams['key'] = key;
      }

      // Add location bias if available
      if (latitude != null && longitude != null) {
        queryParams['location'] = '$latitude,$longitude';
        queryParams['radius'] = radius.toString();
      }

      final uri = Uri.parse(
        '$_apiBaseUrl/textsearch/json',
      ).replace(queryParameters: queryParams);

      debugPrint('🔍 Google Places Text Search: $uri');

      final response = await _client.get(uri).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Check for API-level error
        if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
          debugPrint('⚠️ Google Places API error: ${data['status']} - ${data['error_message']}');
          return PlacesSearchResult(
            doctors: [],
            errorMessage: 'Search failed (${data['status']})',
          );
        }

        final results = data['results'] as List? ?? [];

        final doctors = results
            .map((r) => DoctorModel.fromGooglePlaces(
                  r as Map<String, dynamic>,
                ))
            .where((d) => d.name.isNotEmpty)
            .toList();

        // Cache the fresh results so repeat identical requests skip the API.
        // Await the write so the cache is persisted before returning.
        await _writeSearchCache(cacheKey, doctors);

        return PlacesSearchResult(doctors: doctors);
      }

      final errorBody = response.body.isNotEmpty
          ? response.body.substring(0, response.body.length.clamp(0, 500))
          : '(empty body)';
      debugPrint(
        '⚠️ Google Places search failed: HTTP ${response.statusCode}\n$errorBody',
      );

      return PlacesSearchResult(
        doctors: [],
        errorMessage: 'Search failed (HTTP ${response.statusCode})',
      );
    } catch (e) {
      debugPrint('⚠️ Google Places search error: $e');
      return PlacesSearchResult(
        doctors: [],
        errorMessage: 'Network error. Please check your connection.',
      );
    }
  }

  /// ────────────────────────────────────────────────────────────────
  /// Text Search – search by name / query (Google Places Text Search)
  /// ────────────────────────────────────────────────────────────────
  /// Searches for healthcare places using the Google Places Text Search
  /// API. Used when the user types a clinic name, doctor name, or
  /// hospital name into the search field.
  ///
  /// [query] – the user's search query (e.g. "Apollo Hospital Delhi")
  /// [latitude]/[longitude] – bias results to this location
  /// [radius] – search radius in metres (default 5000 = 5 km)
  Future<PlacesSearchResult> textSearchDoctors({
    required String query,
    double? latitude,
    double? longitude,
    int radius = AppConstants.placesSearchRadius,
  }) async {
    final key = AppConstants.googleMapsApiKey;
    if (key.isEmpty) {
      debugPrint('⚠️ Google Maps API key is empty!');
      return PlacesSearchResult(doctors: []);
    }

    if (query.trim().isEmpty) {
      return PlacesSearchResult(doctors: []);
    }

    try {
      final textQuery = query.trim();

      // ── Cache-first: serve repeat identical searches locally ──
      final cacheKey = searchCacheKey(
        query: textQuery,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
      );
      final cachedDoctors = _readSearchCache(cacheKey);
      if (cachedDoctors != null) {
        debugPrint('🧠 Places text search served from cache: $cacheKey');
        return PlacesSearchResult(doctors: cachedDoctors);
      }

      final queryParams = <String, String>{
        'query': textQuery,
      };
      if (!_useProxy) {
        queryParams['key'] = key;
      }

      // Add location bias if available
      if (latitude != null && longitude != null) {
        queryParams['location'] = '$latitude,$longitude';
        queryParams['radius'] = radius.toString();
      }

      final uri = Uri.parse(
        '$_apiBaseUrl/textsearch/json',
      ).replace(queryParameters: queryParams);

      debugPrint('🔍 Google Places Text Search: $uri');

      final response = await _client.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
          debugPrint('⚠️ Google Places API error: ${data['status']} - ${data['error_message']}');
          return PlacesSearchResult(
            doctors: [],
            errorMessage: 'Text search failed (${data['status']})',
          );
        }

        final results = data['results'] as List? ?? [];

        final doctors = results
            .map((r) => DoctorModel.fromGooglePlaces(
                  r as Map<String, dynamic>,
                ))
            .where((d) => d.name.isNotEmpty)
            .toList();

        // Cache the fresh results so repeat identical requests skip the API.
        // Await the write so the cache is persisted before returning.
        await _writeSearchCache(cacheKey, doctors);

        return PlacesSearchResult(doctors: doctors);
      }

      final errorBody = response.body.isNotEmpty
          ? response.body.substring(0, response.body.length.clamp(0, 500))
          : '(empty body)';
      debugPrint(
        '⚠️ Google Places text search failed: HTTP ${response.statusCode}\n'
        '$errorBody',
      );

      return PlacesSearchResult(
        doctors: [],
        errorMessage: 'Text search failed (HTTP ${response.statusCode})',
      );
    } catch (e) {
      debugPrint('⚠️ Google Places text search error: $e');
      return PlacesSearchResult(
        doctors: [],
        errorMessage: 'Network error. Please check your connection.',
      );
    }
  }

  /// ────────────────────────────────────────────────────────────────
  /// Place Details – full detail for a single place (Google Places Details)
  /// ────────────────────────────────────────────────────────────────
  /// Fetches full detail for a place using the Google Places Details API:
  ///   GET /maps/api/place/details/json
  ///       ?place_id={placeId}&fields=...&key={key}
  Future<DoctorModel?> getDoctorDetails(String placeId) async {
    final key = AppConstants.googleMapsApiKey;
    if (key.isEmpty) {
      debugPrint('⚠️ Google Maps API key is empty! '
          'Add GOOGLE_MAPS_API_KEY to your .env file.');
      return null;
    }

    if (placeId.isEmpty) return null;

    // ── Cache-first: serve repeat detail views locally ──
    final detailKey = detailCacheKey(placeId);
    final cachedDetail = _storage.getPlacesCache(detailKey);
    if (cachedDetail != null) {
      try {
        final cachedDoctor = DoctorModel.fromJson(
          jsonDecode(cachedDetail) as Map<String, dynamic>,
        );
        debugPrint('🧠 Place details served from cache: $placeId');
        return cachedDoctor;
      } catch (_) {
        // Fall through to the API if the cached payload is unreadable.
      }
    }

    try {
      // Request all available fields for a rich detail result
      final fields = [
        'place_id', 'name', 'formatted_address', 'vicinity',
        'geometry', 'rating', 'user_ratings_total', 'photos',
        'opening_hours', 'formatted_phone_number',
        'international_phone_number', 'website', 'url',
        'types', 'address_components', 'business_status',
        'price_level', 'reviews', 'plus_code',
        'editorial_summary',
        // New fields for richer doctor profiles
        'wheelchair_accessible_entrance',
        'current_opening_hours',
      ].join(',');

      final params = <String, String>{
        'place_id': placeId,
        'fields': fields,
      };
      if (!_useProxy) {
        params['key'] = key;
      }
      final uri = Uri.parse(
        '$_apiBaseUrl/details/json',
      ).replace(queryParameters: params);

      final response = await _client.get(uri).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['status'] == 'OK' && data['result'] != null) {
          final doctor = DoctorModel.fromGooglePlaces(
            data['result'] as Map<String, dynamic>,
          );

          // Cache the fresh details so repeat views skip the API.
          _storage.savePlacesCache(
            detailKey,
            jsonEncode(doctor.toJson()),
          );

          return doctor;
        }

        debugPrint('⚠️ Google Places Details API error: ${data['status']} - ${data['error_message']}');
      }
    } catch (e) {
      debugPrint('⚠️ Google Places details error: $e');
    }
    return null;
  }

  /// ────────────────────────────────────────────────────────────────
  /// Photo helper – generates a Google Places photo URL
  /// ────────────────────────────────────────────────────────────────
  /// Generates a URL for a place photo using the Google Places Photo API:
  ///   GET /maps/api/place/photo
  ///       ?photo_reference={ref}&maxwidth={w}&key={key}
  String? getPhotoUrl(String photoReference, {int maxWidth = 400}) {
    final key = AppConstants.googleMapsApiKey;
    if (key.isEmpty || photoReference.isEmpty) return null;
    // Photos are loaded via Image.network (<img> tag) which is not
    // subject to CORS, so we always call Google directly to avoid
    // additional latency through the proxy.
    return '${AppConstants.googlePlacesBaseUrl}/photo'
        '?photo_reference=$photoReference'
        '&maxwidth=$maxWidth'
        '&key=$key';
  }

  /// Larger photo variant for hero/header use.
  String? getPhotoUrlLarge(String photoReference, {int maxWidth = 800}) {
    return getPhotoUrl(photoReference, maxWidth: maxWidth);
  }
}
