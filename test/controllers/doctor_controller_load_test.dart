import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/doctor_controller.dart';
import 'package:DrsListing/services/places_service.dart';
import '../helpers/test_data.dart';

/// Test-only AuthController that skips the secure-storage platform channel
/// (same pattern as doctor_controller_test.dart).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// DB doctor row shape — the `doctors` table record that already has
/// `upi_id` and `unavailable_ranges` set (the doctor saved them earlier).
final Map<String, dynamic> _dbDoctorJson = {
  'place_id': 'place_upi_test',
  'name': 'Dr. UPI Test',
  'user_id': 'user_doctor_upi',
  'upi_id': 'clinic@okhdfcbank',
  'experience_years': 12,
  'unavailable_ranges': [
    {'start': '2026-08-10', 'end': '2026-08-12'},
  ],
  'address': '123 Clinic Road',
  'rating': 4.3,
  'user_ratings_total': 50,
  'types': ['doctor', 'health'],
  'specialization': 'General Physician',
  'latitude': 18.52,
  'longitude': 73.86,
};

/// Google Places result shape — NO `upi_id` or `unavailable_ranges` keys
/// (exactly what the real API returns). From [placesResultJson] with a
/// doctor-specific type override.
final Map<String, dynamic> _placesJson = {
  'place_id': 'place_upi_test',
  'name': 'Dr. UPI Test',
  'geometry': {
    'location': {'lat': 18.52, 'lng': 73.86},
  },
  'rating': 4.3,
  'user_ratings_total': 50,
  'types': ['doctor', 'health'],
  'formatted_address': '123 Clinic Road',
  'vicinity': '123 Clinic Road',
  'business_status': 'OPERATIONAL',
  'opening_hours': {'open_now': true},
  'photos': [
    {
      'photo_reference': 'test_ref',
      'height': 200,
      'width': 400,
      'html_attributions': [],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Load a test API key so PlacesService.getDoctorDetails doesn't bail
  // (PlacesService returns null early when the key is missing). Guarded in
  // case another test file in the same run initialized dotenv already.
  if (!dotenv.isInitialized) {
    dotenv.loadFromString(envString: '''
GOOGLE_MAPS_API_KEY=test_key
GROQ_API_KEY=test_groq_key
''');
  }

  // Every HTTP request the mocked Supabase client makes, in order.
  final requests = <http.Request>[];

  late DoctorController controller;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    // ── Mock Supabase client ────────────────────────────────────
    // Returns a doctor row with upi_id + unavailable_ranges for GET,
    // echoes back the payload for POST (upsert from saveDoctorToDb).
    // The auth/settings endpoint is also stubbed so Supabase doesn't
    // try to reach the real auth service.
    final supabaseClient = MockClient((request) async {
      requests.add(request);
      final path = request.url.path;

      http.Response respond(String body, {int status = 200}) =>
          http.Response(
            body,
            status,
            headers: {
              'content-type': 'application/json; charset=utf-8',
            },
            request: request,
          );

      // Auth settings — Supabase initialization probes this endpoint.
      if (path.endsWith('/auth/v1/settings')) {
        return respond(jsonEncode({
          'external': {'enabled': false},
          'mailer': {'enabled': false},
          'phone': {'enabled': false},
          'sms': {'enabled': false},
          'mfa': {'enabled': false},
          'password': {'enabled': false},
          'sessions': {'enabled': false},
        }));
      }

      // Doctors table: GET = getDoctorFromDb, POST = saveDoctorToDb upsert.
      if (path.contains('/rest/v1/doctors')) {
        if (request.method == 'GET') {
          // Return the DB doctor row WITH upi_id + unavailable_ranges.
          return respond(jsonEncode([_dbDoctorJson]));
        }
        if (request.method == 'POST') {
          // Upsert (saveDoctorToDb) — echo the payload back.
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return respond(jsonEncode([{
            '_rpc_upsert': true,
            ...body,
          }]));
        }
      }

      // Everything else (e.g. /rest/v1/ — no-op).
      return respond('[]');
    });

    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test-anon-key',
      httpClient: supabaseClient,
    );

    // ── Mock PlacesService client ──────────────────────────────
    // Returns Google Places details WITHOUT upi_id/unavailableRanges.
    PlacesService().setClientForTesting(
      MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'OK', 'result': _placesJson}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    // ── Register controllers ───────────────────────────────────
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<DoctorController>(DoctorController(), permanent: true);
    controller = Get.find<DoctorController>();
  });

  tearDownAll(() {
    // Restore a real client on the Places singleton so the mock never
    // leaks into other test files.
    PlacesService().setClientForTesting(http.Client());
    Get.reset();
  });

  setUp(() {
    requests.clear();
    // Set a logged-in doctor user so the userId path is exercised.
    Get.find<AuthController>().currentUser.value =
        userDoctor(id: 'user_doctor_upi', mobile: '9876543211');

    // Always start with the normal Places mock so a test that swaps in an
    // error mock (e.g. the fallback test) can never leak it into the next
    // test if it fails partway through.
    PlacesService().setClientForTesting(
      MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'OK', 'result': _placesJson}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  group('loadDoctorFromDb preserves doctor-set fields', () {
    test('preserves upiId from the DB when Google Places enrichment would '
        'drop it', () async {
      await controller.loadDoctorFromDb('place_upi_test');

      final loaded = controller.currentDoctor.value;
      expect(loaded, isNotNull);
      expect(loaded!.placeId, 'place_upi_test');

      // Regression: before the fix, the Places-enriched model was built
      // with only fullDetails.copyWith(userId: userId) — which dropped
      // upiId because Google Places never returns it. The profile screen
      // then showed "Not set" even though the DB value was intact.
      expect(loaded.upiId, 'clinic@okhdfcbank');

      // experienceYears is also doctor-set; Places doesn't return it.
      expect(loaded.experienceYears, 12);

      // unavailableRanges should also be preserved from the DB.
      expect(loaded.unavailableRanges, hasLength(1));
      expect(loaded.unavailableRanges.first.label, '10 Aug 2026 – 12 Aug 2026');

      // Loading state is reset after completion.
      expect(controller.isLoadingProfile.value, isFalse);
    });

    test('preserves unavailableRanges from the DB during Places enrichment',
        () async {
      // Reset and reload to ensure clean state.
      controller.currentDoctor.value = null;
      await controller.loadDoctorFromDb('place_upi_test');

      final loaded = controller.currentDoctor.value;
      expect(loaded, isNotNull);
      expect(loaded!.unavailableRanges, hasLength(1));
      expect(loaded.unavailableRanges.first.start.year, 2026);
      expect(loaded.unavailableRanges.first.end.day, 12);

      // The enriched model kept the DB's range even though Places data
      // has no unavailable_ranges key.
      final range = loaded.unavailableRanges.first;
      expect(range.contains(DateTime(2026, 8, 10)), isTrue);
      expect(range.contains(DateTime(2026, 8, 12)), isTrue);
      expect(range.contains(DateTime(2026, 8, 13)), isFalse);
    });

    test('falls back to DB doctor when Places API fails', () async {
      // Temporarily mock PlacesService to return null (API failure). The
      // setUp() restores the normal mock before the next test.
      PlacesService().setClientForTesting(
        MockClient((request) async {
          return http.Response(
            jsonEncode({'status': 'INVALID_REQUEST', 'result': null}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      controller.currentDoctor.value = null;
      await controller.loadDoctorFromDb('place_upi_test');

      // Fallback: DB doctor still has upiId and ranges.
      final loaded = controller.currentDoctor.value;
      expect(loaded, isNotNull);
      expect(loaded!.upiId, 'clinic@okhdfcbank');
      expect(loaded.experienceYears, 12);
      expect(loaded.unavailableRanges, hasLength(1));
    });

    test('enriched model is saved back to DB via saveDoctorToDb', () async {
      await controller.loadDoctorFromDb('place_upi_test');

      // The upsert POST should carry the merged data.
      final upserts = requests.where(
        (r) => r.method == 'POST' && r.url.path.contains('/rest/v1/doctors'),
      );
      expect(upserts, hasLength(1));

      final body = jsonDecode(upserts.first.body) as Map<String, dynamic>;
      // The saved payload includes the merged doctor-set fields (not null).
      expect(body['upi_id'], 'clinic@okhdfcbank');
      expect(body['experience_years'], 12);
      // unavailable_ranges is removed by saveDoctorToDb before upsert
      // (it's managed separately via saveDoctorUnavailableRanges), so
      // it should NOT be in the upsert payload.
      expect(body.containsKey('unavailable_ranges'), isFalse);
    });
  });
}