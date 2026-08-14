import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/user_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/doctor/nearby_doctors_screen.dart';
import 'package:DrsListing/screens/doctor/otp_verification_screen.dart';
import 'package:DrsListing/services/local_storage_service.dart';
import 'package:DrsListing/services/places_service.dart';
import 'package:DrsListing/services/supabase_service.dart';

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

/// Test-only AuthController that skips platform-channel usage in onInit.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus to avoid
    // MissingPluginException for flutter_secure_storage in test env.
  }
}

/// A Geolocator platform that answers `isLocationServiceEnabled` with
/// `false`. `NearbyDoctorsScreen._loadNearbyPlaces()` calls
/// `LocationService.getCurrentLocation()`, which awaits a Geolocator
/// platform-channel call. Under widget-test fake async that channel never
/// resolves (it would hang the load forever), so we inject a fake platform
/// that returns immediately — the screen then proceeds to the (mocked)
/// Places search with a null position.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
}

/// The real platform instance, saved so `tearDown` can restore it and the
/// fake never leaks into other test files in the same run.
GeolocatorPlatform? _savedGeolocatorPlatform;

/// Mirrors the OTP route builder in lib/app.dart so the test exercises the
/// same argument forwarding the real app uses.
Widget _otpRouteBuilder() {
  final args = Get.arguments;
  final displayName =
      args is Map ? (args['displayName']?.toString() ?? '') : '';
  final mobile = args is Map ? (args['mobile']?.toString() ?? '') : '';
  final role = args is Map
      ? (args['role']?.toString() ?? UserModel.roleDoctor)
      : UserModel.roleDoctor;
  final doctor = args is Map ? (args['doctor'] as DoctorModel?) : null;
  return OtpVerificationScreen(
    displayName: displayName,
    mobile: mobile,
    role: role,
    doctor: doctor,
  );
}

/// MockClient that answers the Google Places Text Search request with a
/// single clinic, letting NearbyDoctorsScreen load a real card to tap.
MockClient _placesMock() {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'status': 'OK',
        'results': [
          placesResultJson(placeId: 'clinic_flow', name: 'City Clinic'),
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

/// Fake Supabase service for the "already registered as a doctor" check.
/// [role] is what `users.role` is reported to be for the registration
/// mobile — 'doctor' blocks registration, anything else allows it.
/// [registeredPlaceIds] is what the `doctors` table is reported to
/// contain (Google Place IDs) — a matching nearby result is disabled.
class _FakeSupabaseService extends SupabaseService {
  _FakeSupabaseService(this.role, {this.registeredPlaceIds = const []})
      : super.testing();

  final String? role;
  final List<String> registeredPlaceIds;

  @override
  Future<Map<String, dynamic>?> getUserByMobile(String mobile) async {
    return role == null ? null : {'mobile': mobile, 'role': role};
  }

  @override
  Future<List<String>> getRegisteredDoctorPlaceIds() async {
    return registeredPlaceIds;
  }
}

void main() {
  setUpAll(_ensureDotenv);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService().init();

    // The GPS gate runs before the screen's own location fetch. This test
    // simulates a normal working device, so the gate must pass — the fake
    // Geolocator platform below returns `false` for
    // isLocationServiceEnabled (so the location fetch resolves instantly
    // instead of hanging on an unresolved channel), which the gate would
    // otherwise read as "GPS off" and block the whole flow.
    NearbyDoctorsScreen.gpsCheckOverride = () async => true;

    // Replace the Geolocator platform so the screen's location fetch
    // resolves instantly instead of hanging on an unresolved channel.
    _savedGeolocatorPlatform = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform();
  });

  tearDown(() {
    NearbyDoctorsScreen.gpsCheckOverride = null;
    NearbyDoctorsScreen.supabaseOverride = null;
    // Restore a real client so the mocked PlacesService client never leaks
    // into other test files.
    PlacesService().setClientForTesting(http.Client());
    // Restore the real Geolocator platform.
    if (_savedGeolocatorPlatform != null) {
      GeolocatorPlatform.instance = _savedGeolocatorPlatform!;
    }
  });

  testWidgets(
      'full flow: tap Select & Continue → Confirm & Continue → OTP screen',
      (tester) async {
    // Fresh GetX state (controllers + route table) per test.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    PlacesService().setClientForTesting(_placesMock());

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Center(child: Text('launch'))),
        getPages: [
          GetPage(
            name: AppRoutes.nearbyDoctors,
            page: () => const NearbyDoctorsScreen(),
          ),
          GetPage(
            name: AppRoutes.otpVerification,
            page: _otpRouteBuilder,
          ),
        ],
      ),
    );
    await tester.pump();

    // Enter the nearby-clinic screen in doctor-registration mode.
    Get.toNamed(
      AppRoutes.nearbyDoctors,
      arguments: {
        'mode': 'register',
        'displayName': 'Dr. Raj',
        'mobile': '9876543210',
        'role': UserModel.roleDoctor,
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // route transition
    await tester.pump(const Duration(milliseconds: 100)); // mock places load
    await tester.pump(const Duration(milliseconds: 600)); // card fade-in

    // Registration-mode header + the clinic card with its continue button.
    expect(find.text('Select Your Clinic'), findsOneWidget);
    expect(find.text('City Clinic'), findsOneWidget);
    expect(find.text('Select & Continue'), findsOneWidget);

    // ── Step 1: Select the clinic → confirmation dialog ──
    await tester.tap(find.text('Select & Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Confirm Selection'), findsOneWidget);
    expect(find.text('Confirm & Continue'), findsOneWidget);

    // ── Step 2: Confirm & Continue → spinner → navigate to OTP ──
    await tester.tap(find.text('Confirm & Continue'));
    await tester.pump();
    // The button shows its loading spinner while the dialog is closing.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Flush the button's minimum spinner timer + dialog pop + route push.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 300)); // transition
    await tester.pump(const Duration(milliseconds: 1200)); // OTP fade-ins

    // ── Step 3: OTP screen reached with forwarded registration data ──
    expect(Get.currentRoute, AppRoutes.otpVerification);
    expect(find.text('Verify OTP'), findsOneWidget);
    expect(find.text('Verify & Continue'), findsOneWidget);
    expect(find.text('Dr. Raj'), findsOneWidget);
    expect(find.text('+91 9876543210'), findsOneWidget);

    // Flush the OTP resend countdown chain (15 × 1s timers) so no timers
    // remain pending when the test tears down.
    await tester.pump(const Duration(seconds: 16));
    // The OTP screen auto-shows the demo-OTP toast (6s display timer) —
    // let it expire and its hide animation finish while the overlay is
    // still mounted, then force-close any remainder.
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    Get.closeAllSnackbars();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'registration mode: already-registered mobile disables Select & '
      'Continue', (tester) async {
    // Fresh GetX state (controllers + route table) per test.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    PlacesService().setClientForTesting(_placesMock());
    // The mobile already belongs to a registered doctor → registration
    // must be blocked.
    NearbyDoctorsScreen.supabaseOverride =
        () => _FakeSupabaseService(UserModel.roleDoctor);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Center(child: Text('launch'))),
        getPages: [
          GetPage(
            name: AppRoutes.nearbyDoctors,
            page: () => const NearbyDoctorsScreen(),
          ),
        ],
      ),
    );
    // Enter the nearby-clinic screen in doctor-registration mode.
    Get.toNamed(
      AppRoutes.nearbyDoctors,
      arguments: {
        'mode': 'register',
        'displayName': 'Dr. Raj',
        'mobile': '9876543210',
        'role': UserModel.roleDoctor,
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // route transition
    await tester.pump(const Duration(milliseconds: 100)); // mock places load
    await tester.pump(const Duration(milliseconds: 600)); // card fade-in

    // Registration-mode header + the clinic card are still shown (nearby
    // data displays for new AND already-registered doctors).
    expect(find.text('Select Your Clinic'), findsOneWidget);
    expect(find.text('City Clinic'), findsOneWidget);

    // The already-registered notice is shown and every Select & Continue
    // button is disabled.
    expect(
      find.textContaining('already registered as a doctor'),
      findsWidgets,
    );
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Select & Continue'),
        matching: find.bySubtype<ElevatedButton>(),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Already registered as a doctor'), findsOneWidget);
  });

  testWidgets(
      'registration mode: fresh mobile keeps Select & Continue enabled',
      (tester) async {
    // Fresh GetX state (controllers + route table) per test.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    PlacesService().setClientForTesting(_placesMock());
    // No users row for this mobile → registration allowed.
    NearbyDoctorsScreen.supabaseOverride = () => _FakeSupabaseService(null);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Center(child: Text('launch'))),
        getPages: [
          GetPage(
            name: AppRoutes.nearbyDoctors,
            page: () => const NearbyDoctorsScreen(),
          ),
        ],
      ),
    );
    Get.toNamed(
      AppRoutes.nearbyDoctors,
      arguments: {
        'mode': 'register',
        'displayName': 'Dr. New',
        'mobile': '9876543211',
        'role': UserModel.roleDoctor,
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // route transition
    await tester.pump(const Duration(milliseconds: 100)); // mock places load
    await tester.pump(const Duration(milliseconds: 600)); // card fade-in

    // Nearby data shows and the button stays enabled for a fresh mobile.
    expect(find.text('Select Your Clinic'), findsOneWidget);
    expect(find.text('City Clinic'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Select & Continue'),
        matching: find.bySubtype<ElevatedButton>(),
      ),
    );
    expect(button.onPressed, isNotNull);
    expect(
      find.text('Already registered as a doctor'),
      findsNothing,
    );
  });

  testWidgets(
      'registration mode: a Google result already in the doctors table '
      'is disabled even for a fresh mobile', (tester) async {
    // Fresh GetX state (controllers + route table) per test.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    PlacesService().setClientForTesting(_placesMock());
    // Fresh mobile (no users row) BUT the Google place 'clinic_flow' is
    // already registered in the doctors table → its card must be disabled.
    NearbyDoctorsScreen.supabaseOverride = () => _FakeSupabaseService(
          null,
          registeredPlaceIds: const ['clinic_flow'],
        );

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Center(child: Text('launch'))),
        getPages: [
          GetPage(
            name: AppRoutes.nearbyDoctors,
            page: () => const NearbyDoctorsScreen(),
          ),
        ],
      ),
    );
    Get.toNamed(
      AppRoutes.nearbyDoctors,
      arguments: {
        'mode': 'register',
        'displayName': 'Dr. New',
        'mobile': '9876543212',
        'role': UserModel.roleDoctor,
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // route transition
    await tester.pump(const Duration(milliseconds: 100)); // mock places load
    await tester.pump(const Duration(milliseconds: 600)); // card fade-in

    // The card is shown (nearby data displays) but its Select & Continue
    // button is disabled because the place is already registered.
    expect(find.text('Select Your Clinic'), findsOneWidget);
    expect(find.text('City Clinic'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Select & Continue'),
        matching: find.bySubtype<ElevatedButton>(),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Already registered as a doctor'), findsOneWidget);
  });
}
