import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/services/places_service.dart';

import '../helpers/test_data.dart';

/// Test-only AuthController that skips the secure-storage platform channel
/// (same pattern as auth_controller_test.dart).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// DB doctor row shape — the `doctors` table record that already has
/// `upi_id`, `unavailable_ranges` and `experience_years` set (the doctor
/// saved them earlier).
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
/// (exactly what the real API returns).
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
  // (PlacesService returns null early when the key is missing).
  if (!dotenv.isInitialized) {
    dotenv.loadFromString(envString: '''
GOOGLE_MAPS_API_KEY=test_key
GROQ_API_KEY=test_groq_key
''');
  }

  // Every HTTP request the mocked Supabase client makes, in order.
  final requests = <http.Request>[];

  late AuthController auth;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    // ── Mock Supabase client ────────────────────────────────────
    // Returns a doctor row with upi_id + unavailable_ranges for GET,
    // echoes back the payload for POST (upsert from saveDoctorToDb).
    final supabaseClient = MockClient((request) async {
      requests.add(request);
      final path = request.url.path;

      http.Response respond(String body, {int status = 200}) =>
          http.Response(
            body,
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
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

      // Doctors table: GET = getDoctorFromDb / getDoctorsByUserId,
      // POST = saveDoctorToDb upsert.
      if (path.contains('/rest/v1/doctors')) {
        if (request.method == 'GET') {
          // Return the DB doctor row WITH upi_id + unavailable_ranges.
          return respond(jsonEncode([_dbDoctorJson]));
        }
        if (request.method == 'POST') {
          // Upsert (saveDoctorToDb) — echo the payload back.
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return respond(jsonEncode([{'_rpc_upsert': true, ...body}]));
        }
      }

      // Everything else (appointments / doctor_slots / payments / …) — no-op.
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
    auth = Get.find<AuthController>();
  });

  tearDownAll(() {
    // Restore a real client on the Places singleton so the mock never
    // leaks into other test files.
    PlacesService().setClientForTesting(http.Client());
    Get.reset();
  });

  setUp(() {
    requests.clear();
  });

  /// Pumps a navigator with the doctor-dashboard route so the
  /// Get.offAllNamed(AppRoutes.doctorDashboard) at the end of
  /// [AuthController.navigateToRoleBasedHome] resolves.
  Future<void> pumpNavigator(WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: SizedBox()),
        getPages: [
          GetPage(
            name: AppRoutes.doctorDashboard,
            page: () => const Scaffold(body: Text('DASH')),
          ),
        ],
      ),
    );
  }

  group('navigateToRoleBasedHome preserves doctor-set fields on re-login', () {
    testWidgets('enriched doctor keeps the saved availability (primary path)',
        (tester) async {
      await pumpNavigator(tester);

      // A doctor user whose clinic already has doctor-set fields saved in
      // the DB (experience_years, unavailable_ranges).
      auth.currentUser.value = userDoctor(
        id: 'user_doctor_upi',
        mobile: '9876543211',
      ).copyWith(doctorPlaceId: 'place_upi_test');

      await auth.navigateToRoleBasedHome();
      await tester.pumpAndSettle();

      // Regression: before the fix, the Places-enriched model was built
      // with only fullDetails.copyWith(userId: user.id) — dropping upiId
      // because Google Places never returns it. After logout → login the
      // profile then showed "Not set" even though the DB value was intact.
      final loaded = Get.find<DoctorController>().currentDoctor.value;
      expect(loaded, isNotNull);
      expect(loaded!.placeId, 'place_upi_test');
      expect(loaded.upiId, 'clinic@okhdfcbank');
      expect(loaded.experienceYears, 12);
      expect(loaded.unavailableRanges, hasLength(1));

      // The enriched model saved back to the DB carries the merged
      // upi_id (not omitted as null).
      final upserts = requests.where(
        (r) => r.method == 'POST' && r.url.path.contains('/rest/v1/doctors'),
      );
      expect(upserts, isNotEmpty);
      final body = jsonDecode(upserts.last.body) as Map<String, dynamic>;
      expect(body['upi_id'], 'clinic@okhdfcbank');
      expect(body['experience_years'], 12);
    });

    testWidgets(
        'fallback path (getDoctorsByUserId) also preserves doctor-set fields',
        (tester) async {
      await pumpNavigator(tester);

      // No doctorPlaceId on the user → the login flow falls back to
      // getDoctorsByUserId, which returns the DB row with the doctor-set
      // fields.
      auth.currentUser.value = userDoctor(
        id: 'user_doctor_upi',
        mobile: '9876543211',
      );

      await auth.navigateToRoleBasedHome();
      await tester.pumpAndSettle();

      final loaded = Get.find<DoctorController>().currentDoctor.value;
      expect(loaded, isNotNull);
      expect(loaded!.upiId, 'clinic@okhdfcbank');
      expect(loaded.experienceYears, 12);
      expect(loaded.unavailableRanges, hasLength(1));
    });
  });
}
