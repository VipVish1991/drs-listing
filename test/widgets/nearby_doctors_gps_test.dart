import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/screens/doctor/nearby_doctors_screen.dart';

/// Test-only AuthController that skips platform-channel usage in onInit.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus to avoid
    // MissingPluginException for flutter_secure_storage in test env.
  }
}

void main() {
  setUpAll(() {
    if (!dotenv.isInitialized) {
      dotenv.loadFromString(
        envString: '''
GOOGLE_MAPS_API_KEY=test_key
GROQ_API_KEY=test_groq_key
''',
      );
    }
  });

  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    NearbyDoctorsScreen.gpsCheckOverride = null;
  });

  tearDown(() {
    NearbyDoctorsScreen.gpsCheckOverride = null;
  });

  Widget buildApp() {
    return GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: const NearbyDoctorsScreen(),
    );
  }

  testWidgets('blocks the nearby-places load with the GPS-off alert when '
      'GPS is off, then proceeds after the user enables it', (tester) async {
    var gpsEnabled = false;
    NearbyDoctorsScreen.gpsCheckOverride = () async => gpsEnabled;

    await tester.pumpWidget(buildApp());
    // Post-frame → _loadNearbyPlaces → gate probes GPS (off) → alert pops.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('GPS is Off'), findsOneWidget);

    // The user enables GPS and taps check-again → alert closes and the
    // pending nearby load proceeds (PlacesService fails on the mocked
    // HTTP client in tests, landing on the error state — never the alert).
    gpsEnabled = true;
    await tester.tap(find.text("I've enabled GPS — check again"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('GPS is Off'), findsNothing);
  });

  testWidgets('loads without the GPS alert when GPS is on', (tester) async {
    NearbyDoctorsScreen.gpsCheckOverride = () async => true;

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('GPS is Off'), findsNothing);
  });
}
