import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:DrsListing/app.dart';
import 'package:DrsListing/controllers/auth_controller.dart';

/// Test-only AuthController that skips platform-channel usage in onInit.
class _TestAppAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus to avoid
    // MissingPluginException for flutter_secure_storage in test env.
  }
}

void main() {
  setUpAll(() {
    // Register a test AuthController so the splash screen can resolve
    // Get.find<AuthController>() without throwing a runtime error.
    Get.put<AuthController>(_TestAppAuthController(), permanent: true);
  });

  tearDownAll(() {
    Get.reset();
  });

  testWidgets('App should build without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const App());

    // The splash screen shows the 'AI' badge text immediately
    // (as a plain Text widget, not Text.rich). Verify the core
    // splash content renders before navigation starts.
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('Your AI Health Assistant'), findsOneWidget);

    // Advance the clock past the splash screen's Future.delayed (0.4 s)
    // and the location-service check.  Ensures no pending timers or
    // animations crash the test tear-down.
    await tester.pump(const Duration(seconds: 4));
  });
}
