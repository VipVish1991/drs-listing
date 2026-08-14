import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/user_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/doctor/otp_verification_screen.dart';
import 'package:DrsListing/services/auth_service.dart';

import '../test/helpers/test_data.dart';

/// Test-only AuthController that skips platform-channel usage in onInit
/// (flutter_secure_storage has no plugin wiring needed on device either,
/// but onInit would otherwise call checkAuthStatus on startup).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus.
  }
}

/// Counts `register()` invocations so the smoke test can assert the OTP
/// verification leads to exactly one registration.
class _FakeAuthService extends AuthService {
  _FakeAuthService() : super.testing();

  int registerCalls = 0;

  @override
  Future<UserModel> register(
    String name,
    String mobile, {
    String role = UserModel.rolePatient,
  }) async {
    registerCalls++;
    return userPatient();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  /// Pumps the OTP screen (patient registration) with a fake AuthService
  /// and a registered /home route so the post-verification navigation
  /// resolves. The OTP screen needs no backend — the code is generated
  /// client-side and verified locally. Pass [fake] to keep a handle on
  /// the AuthService after the screen is replaced by the home route.
  Future<WidgetTester> pumpOtp(
    WidgetTester tester, {
    _FakeAuthService? fake,
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        getPages: [
          GetPage(
            name: AppRoutes.home,
            page: () => const Scaffold(body: Text('PATIENT HOME')),
          ),
        ],
        home: OtpVerificationScreen(
          displayName: 'Smoke Patient',
          mobile: '9876543210',
          role: UserModel.rolePatient,
          authService: fake ?? _FakeAuthService(),
          otpGenerator: () => '654321',
          otpSendDelay: Duration.zero,
        ),
      ),
    );
    // Advance past the flutter_animate fade-ins so the Verify button is
    // hittable, and one tick of the resend countdown.
    await tester.pump(const Duration(milliseconds: 1500));
    return tester;
  }

  /// Disposes the screen and advances 1s so the resend-countdown
  /// Future.doWhile chain terminates cleanly before teardown.
  Future<void> flushResendTimer(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
      'ON-DEVICE: client-generated OTP is toasted (not pre-filled) and '
      'verifies to patient home', (tester) async {
    final fake = _FakeAuthService();
    await pumpOtp(tester, fake: fake);

    // The toast shows the code (demo mode) but the pin field is NOT
    // pre-filled — the user must type it manually.
    expect(find.text('Demo OTP: 654321'), findsOneWidget);
    expect(find.text('Verify & Continue'), findsOneWidget);

    // User types the code from the toast — completing the 4th digit
    // auto-submits, matches locally, registers exactly once and lands on
    // the patient home.
    await tester.enterText(find.byType(PinCodeTextField), '654321');
    await tester.pumpAndSettle();

    // The OTP screen is replaced by the home route once verified, so the
    // fake is asserted through the reference captured above, not by
    // looking the widget up after navigation.
    expect(fake.registerCalls, 1);
    expect(find.text('PATIENT HOME'), findsOneWidget);

    await flushResendTimer(tester);
  });

  testWidgets(
      'ON-DEVICE: a wrong OTP is rejected without registering', (tester) async {
    final fake = _FakeAuthService();
    await pumpOtp(tester, fake: fake);

    // Type a wrong 4-digit code — completing the 4th digit auto-submits
    // and the mismatch is rejected.
    await tester.enterText(find.byType(PinCodeTextField), '2222');
    await tester.pump();
    await tester.pump();

    expect(find.text('Invalid OTP. Please try again.'), findsOneWidget);

    // register() is never reached for a wrong code.
    expect(fake.registerCalls, 0);

    await flushResendTimer(tester);
  });
}
