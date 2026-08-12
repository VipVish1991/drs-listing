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
  /// resolves. The OTP screen needs no backend — the fake verifies the
  /// whole flow on-device without Supabase.
  Future<WidgetTester> pumpOtp(WidgetTester tester) async {
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
          authService: _FakeAuthService(),
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
      'ON-DEVICE: default OTP 1111 is pre-filled and verifies to patient '
      'home', (tester) async {
    await pumpOtp(tester);

    // Default OTP '1111' pre-filled → pin boxes render '1', and the pill
    // tells the user the default code.
    expect(find.text('1'), findsAtLeastNWidgets(4));
    expect(find.text('Use default OTP: 1111'), findsOneWidget);
    expect(find.text('Verify & Continue'), findsOneWidget);

    // Tap Verify → registers exactly once and lands on the patient home.
    await tester.tap(find.text('Verify & Continue'));
    await tester.pumpAndSettle();

    final fake = tester
        .widget<OtpVerificationScreen>(find.byType(OtpVerificationScreen))
        .authService as _FakeAuthService;
    expect(fake.registerCalls, 1);
    expect(find.text('PATIENT HOME'), findsOneWidget);

    await flushResendTimer(tester);
  });

  testWidgets(
      'ON-DEVICE: a wrong OTP is rejected without registering', (tester) async {
    await pumpOtp(tester);

    // Replace the pre-filled 1111 with 2222 → wrong code.
    await tester.enterText(find.byType(PinCodeTextField), '2222');
    await tester.pump();
    await tester.tap(find.text('Verify & Continue'));
    await tester.pump();

    expect(find.text('Invalid OTP. Please try again.'), findsOneWidget);

    // register() is never reached for a wrong code.
    final fake = tester
        .widget<OtpVerificationScreen>(find.byType(OtpVerificationScreen))
        .authService as _FakeAuthService;
    expect(fake.registerCalls, 0);

    await flushResendTimer(tester);
  });
}
