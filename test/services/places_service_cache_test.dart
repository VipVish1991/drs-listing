import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:DrsListing/services/local_storage_service.dart';
import 'package:DrsListing/services/places_service.dart';
import '../helpers/places_cache_keys.dart';
import '../helpers/test_data.dart';

/// Loads a test API key so `AppConstants.googleMapsApiKey` is non-empty
/// (PlacesService bails out early when the key is missing).
void _ensureDotenv() {
  if (!dotenv.isInitialized) {
    dotenv.loadFromString(
      envString: '''
GOOGLE_MAPS_API_KEY=test_key
GROQ_API_KEY=test_groq_key
''',
    );
  }
}

/// Builds a MockClient that always answers the Google Places Text Search
/// request with [status] and [results], and reports how many HTTP calls
/// were made so tests can assert cache-hit behaviour (no extra calls).
({MockClient client, int Function() calls}) _textSearchMock({
  String status = 'OK',
  List<Map<String, dynamic>> results = const [],
}) {
  var callCount = 0;
  final client = MockClient((request) async {
    callCount++;
    return http.Response(
      jsonEncode({'status': status, 'results': results}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return (client: client, calls: () => callCount);
}

/// Builds a MockClient that always answers the Google Places Details
/// request with [status] and a single [result] object, and reports how
/// many HTTP calls were made so tests can assert cache-hit behaviour.
({MockClient client, int Function() calls}) _detailsMock({
  String status = 'OK',
  Map<String, dynamic>? result,
}) {
  var callCount = 0;
  final client = MockClient((request) async {
    callCount++;
    return http.Response(
      jsonEncode({
        'status': status,
        'result': ?result,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return (client: client, calls: () => callCount);
}

void main() {
  setUpAll(() {
    _ensureDotenv();
  });

  setUp(() async {
    // Fresh empty storage for every test so the singleton cache state
    // never leaks between cases.
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService().init();
  });

  tearDown(() {
    // Restore a real client on the singleton so the mocked client set via
    // setClientForTesting never leaks into other test files.
    PlacesService().setClientForTesting(http.Client());
  });

  group('PlacesService search cache', () {
    test('cache miss calls the API and saves the result', () async {
      final mock = _textSearchMock(
        results: [placesResultJson(placeId: 'cached_1', name: 'City Hospital')],
      );
      PlacesService().setClientForTesting(mock.client);

      final result = await PlacesService().searchNearbyHealthcare(
        keyword: 'clinic',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );

      // One real API call happened…
      expect(mock.calls(), 1);
      expect(result.doctors, hasLength(1));
      expect(result.doctors.first.placeId, 'cached_1');

      // …and the response was persisted to the cache. The write is now
      // awaited inside searchNearbyHealthcare, so it is readable right away
      // (no microtask flush needed).
      final cached = LocalStorageService().getPlacesCache(
        nearbyHealthcareCacheKey(
          keyword: 'clinic',
          latitude: 12.34,
          longitude: 56.78,
          radius: 5000,
        ),
      );
      expect(cached, isNotNull);
      expect(cached, contains('City Hospital'));
    });

    test('cache hit returns cached doctors without calling the API again',
        () async {
      final mock = _textSearchMock(
        results: [placesResultJson(placeId: 'hit_1', name: 'Hit Clinic')],
      );
      PlacesService().setClientForTesting(mock.client);

      // Warm the cache.
      await PlacesService().searchNearbyHealthcare(
        keyword: 'clinic',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );
      expect(mock.calls(), 1);

      // Identical request → served from cache, API untouched.
      final second = await PlacesService().searchNearbyHealthcare(
        keyword: 'clinic',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );

      expect(mock.calls(), 1); // still 1 — no second HTTP call
      expect(second.doctors, hasLength(1));
      expect(second.doctors.first.placeId, 'hit_1');
    });

    test('empty (ZERO_RESULTS) responses are cached too', () async {
      final mock = _textSearchMock(status: 'ZERO_RESULTS');
      PlacesService().setClientForTesting(mock.client);

      // First request: real API call, returns no doctors.
      final first = await PlacesService().searchNearbyHealthcare(
        keyword: 'nonexistent',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );
      expect(first.doctors, isEmpty);
      expect(mock.calls(), 1);

      // Repeat: the empty result is served from cache (no re-fetch),
      // proving an empty list is treated as a valid cache hit, not a miss.
      final second = await PlacesService().searchNearbyHealthcare(
        keyword: 'nonexistent',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );
      expect(second.doctors, isEmpty);
      expect(mock.calls(), 1); // still 1 — empty result cached
    });

    test('different parameters use different cache keys', () async {
      final mock = _textSearchMock(
        results: [placesResultJson(placeId: 'k1', name: 'Radius 5 Clinic')],
      );
      PlacesService().setClientForTesting(mock.client);

      await PlacesService().searchNearbyHealthcare(
        keyword: 'clinic',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );

      // Same query but a different radius → different cache key → real call.
      final other = await PlacesService().searchNearbyHealthcare(
        keyword: 'clinic',
        latitude: 12.34,
        longitude: 56.78,
        radius: 10000,
      );

      expect(mock.calls(), 2);
      expect(other.doctors, hasLength(1));
    });

    test('stale cached entries older than the TTL are re-fetched', () async {
      // Seed the cache with an entry whose saved_at is 25 hours old
      // (TTL is 24h), stored in the same shape _writeSearchCache uses.
      final staleKey = nearbyHealthcareCacheKey(
        keyword: 'clinic',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );
      final storage = LocalStorageService();
      await storage.savePlacesCache(
        staleKey,
        jsonEncode([doctorBasic(placeId: 'stale_1', name: 'Stale Clinic').toJson()]),
      );
      // Rewrite the saved_at to 25h ago by reaching into prefs directly.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(placesCachePrefsKey(staleKey));
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      decoded['saved_at'] = DateTime.now()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      await prefs.setString(
        placesCachePrefsKey(staleKey),
        jsonEncode(decoded),
      );

      // Because the entry is stale, the service must call the API again.
      final mock = _textSearchMock(
        results: [placesResultJson(placeId: 'fresh_1', name: 'Fresh Clinic')],
      );
      PlacesService().setClientForTesting(mock.client);

      final result = await PlacesService().searchNearbyHealthcare(
        keyword: 'clinic',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );

      expect(mock.calls(), 1);
      expect(result.doctors, hasLength(1));
      expect(result.doctors.first.placeId, 'fresh_1');
    });
  });

  group('PlacesService text search cache (textSearchDoctors)', () {
    test('cache miss calls the API and saves the result', () async {
      final mock = _textSearchMock(
        results: [placesResultJson(placeId: 'ts_1', name: 'Apollo Clinic')],
      );
      PlacesService().setClientForTesting(mock.client);

      final result = await PlacesService().textSearchDoctors(
        query: 'Apollo Hospital',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );

      // One real API call happened…
      expect(mock.calls(), 1);
      expect(result.doctors, hasLength(1));
      expect(result.doctors.first.placeId, 'ts_1');

      // …and the response was persisted to the cache. The write is now
      // awaited inside textSearchDoctors, so it is readable right away
      // (no microtask flush needed).
      final cached = LocalStorageService().getPlacesCache(
        textSearchCacheKey(
          query: 'Apollo Hospital',
          latitude: 12.34,
          longitude: 56.78,
          radius: 5000,
        ),
      );
      expect(cached, isNotNull);
      expect(cached, contains('Apollo Clinic'));
    });

    test('cache hit returns cached doctors without calling the API again',
        () async {
      final mock = _textSearchMock(
        results: [placesResultJson(placeId: 'ts_hit', name: 'Hit Clinic')],
      );
      PlacesService().setClientForTesting(mock.client);

      // Warm the cache.
      await PlacesService().textSearchDoctors(
        query: 'Apollo Hospital',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );
      expect(mock.calls(), 1);

      // Identical request → served from cache, API untouched.
      final second = await PlacesService().textSearchDoctors(
        query: 'Apollo Hospital',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );

      expect(mock.calls(), 1); // still 1 — no second HTTP call
      expect(second.doctors, hasLength(1));
      expect(second.doctors.first.placeId, 'ts_hit');
    });

    test('empty (ZERO_RESULTS) responses are cached too', () async {
      final mock = _textSearchMock(status: 'ZERO_RESULTS');
      PlacesService().setClientForTesting(mock.client);

      final first = await PlacesService().textSearchDoctors(
        query: 'No Such Clinic XYZ',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );
      expect(first.doctors, isEmpty);
      expect(mock.calls(), 1);

      final second = await PlacesService().textSearchDoctors(
        query: 'No Such Clinic XYZ',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );
      expect(second.doctors, isEmpty);
      expect(mock.calls(), 1); // still 1 — empty result cached
    });

    test('different parameters use different cache keys', () async {
      final mock = _textSearchMock(
        results: [placesResultJson(placeId: 'ts_k', name: 'Radius Clinic')],
      );
      PlacesService().setClientForTesting(mock.client);

      await PlacesService().textSearchDoctors(
        query: 'Apollo Hospital',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );

      // Same query but a different radius → different cache key → real call.
      final other = await PlacesService().textSearchDoctors(
        query: 'Apollo Hospital',
        latitude: 12.34,
        longitude: 56.78,
        radius: 10000,
      );

      expect(mock.calls(), 2);
      expect(other.doctors, hasLength(1));
    });

    test('stale cached entries older than the TTL are re-fetched', () async {
      final staleKey = textSearchCacheKey(
        query: 'Apollo Hospital',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );
      final storage = LocalStorageService();
      await storage.savePlacesCache(
        staleKey,
        jsonEncode([
          doctorBasic(placeId: 'ts_stale', name: 'Stale Clinic').toJson(),
        ]),
      );
      // Rewrite the saved_at to 25h ago by reaching into prefs directly.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(placesCachePrefsKey(staleKey));
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      decoded['saved_at'] = DateTime.now()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      await prefs.setString(placesCachePrefsKey(staleKey), jsonEncode(decoded));

      final mock = _textSearchMock(
        results: [placesResultJson(placeId: 'ts_fresh', name: 'Fresh Clinic')],
      );
      PlacesService().setClientForTesting(mock.client);

      final result = await PlacesService().textSearchDoctors(
        query: 'Apollo Hospital',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );

      expect(mock.calls(), 1);
      expect(result.doctors, hasLength(1));
      expect(result.doctors.first.placeId, 'ts_fresh');
    });

    test('blank query short-circuits without an API call', () async {
      final mock = _textSearchMock(
        results: [placesResultJson(placeId: 'unused', name: 'Unused')],
      );
      PlacesService().setClientForTesting(mock.client);

      final result = await PlacesService().textSearchDoctors(
        query: '   ',
        latitude: 12.34,
        longitude: 56.78,
        radius: 5000,
      );

      expect(result.doctors, isEmpty);
      expect(mock.calls(), 0);
    });
  });

  group('PlacesService place details cache (getDoctorDetails)', () {
    test('cache miss calls the API and saves the result', () async {
      final mock = _detailsMock(
        result: placesResultJson(placeId: 'detail_1', name: 'Detail Clinic'),
      );
      PlacesService().setClientForTesting(mock.client);

      final doctor = await PlacesService().getDoctorDetails('detail_1');

      // One real API call happened…
      expect(mock.calls(), 1);
      expect(doctor, isNotNull);
      expect(doctor!.placeId, 'detail_1');

      // …and the response was persisted to the cache. NOTE: getDoctorDetails
      // still writes fire-and-forget, so flush pending microtasks before
      // reading the cache back to avoid a race.
      await Future<void>.delayed(Duration.zero);
      final cached = LocalStorageService()
          .getPlacesCache(doctorDetailCacheKey('detail_1'));
      expect(cached, isNotNull);
      expect(cached, contains('Detail Clinic'));
    });

    test('cache hit returns cached doctor without calling the API again',
        () async {
      final mock = _detailsMock(
        result: placesResultJson(placeId: 'detail_hit', name: 'Hit Clinic'),
      );
      PlacesService().setClientForTesting(mock.client);

      // Warm the cache.
      final first = await PlacesService().getDoctorDetails('detail_hit');
      expect(first, isNotNull);
      expect(mock.calls(), 1);

      // Identical request → served from cache, API untouched.
      final second = await PlacesService().getDoctorDetails('detail_hit');

      expect(mock.calls(), 1); // still 1 — no second HTTP call
      expect(second, isNotNull);
      expect(second!.placeId, 'detail_hit');
    });

    test('different place IDs use different cache keys', () async {
      final mock = _detailsMock(
        result: placesResultJson(placeId: 'detail_a', name: 'Clinic A'),
      );
      PlacesService().setClientForTesting(mock.client);

      await PlacesService().getDoctorDetails('detail_a');
      expect(mock.calls(), 1);

      // Different place ID → different cache key → real call again.
      final b = await PlacesService().getDoctorDetails('detail_b');
      expect(mock.calls(), 2);
      expect(b, isNotNull);
    });

    test('stale cached entries older than the TTL are re-fetched', () async {
      final staleKey = doctorDetailCacheKey('detail_stale');
      final storage = LocalStorageService();
      await storage.savePlacesCache(
        staleKey,
        jsonEncode(
          doctorBasic(placeId: 'detail_stale', name: 'Stale Clinic').toJson(),
        ),
      );
      // Rewrite the saved_at to 25h ago by reaching into prefs directly.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(placesCachePrefsKey(staleKey));
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      decoded['saved_at'] = DateTime.now()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      await prefs.setString(placesCachePrefsKey(staleKey), jsonEncode(decoded));

      final mock = _detailsMock(
        result: placesResultJson(placeId: 'detail_fresh', name: 'Fresh Clinic'),
      );
      PlacesService().setClientForTesting(mock.client);

      final doctor = await PlacesService().getDoctorDetails('detail_stale');

      expect(mock.calls(), 1);
      expect(doctor, isNotNull);
      expect(doctor!.placeId, 'detail_fresh');
    });

    test('unreadable cached payload falls through to the API', () async {
      // Seed a fresh-but-corrupt cache entry: the outer wrapper is valid so
      // getPlacesCache returns it, but the inner JSON will not decode.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        placesCachePrefsKey(doctorDetailCacheKey('detail_corrupt')),
        jsonEncode({
          'saved_at': DateTime.now().toIso8601String(),
          'data': '{not valid json',
        }),
      );

      final mock = _detailsMock(
        result: placesResultJson(placeId: 'detail_ok', name: 'Ok Clinic'),
      );
      PlacesService().setClientForTesting(mock.client);

      final doctor = await PlacesService().getDoctorDetails('detail_corrupt');

      // Corrupt cache treated as a miss → real API call returns the doctor.
      expect(mock.calls(), 1);
      expect(doctor, isNotNull);
      expect(doctor!.placeId, 'detail_ok');
    });

    test('empty place ID short-circuits without an API call', () async {
      final mock = _detailsMock(
        result: placesResultJson(placeId: 'unused', name: 'Unused'),
      );
      PlacesService().setClientForTesting(mock.client);

      final doctor = await PlacesService().getDoctorDetails('');

      expect(doctor, isNull);
      expect(mock.calls(), 0);
    });
  });
}
