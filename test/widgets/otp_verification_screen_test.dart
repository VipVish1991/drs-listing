import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/user_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/doctor/otp_verification_screen.dart';
import 'package:DrsListing/services/auth_service.dart';
import 'package:DrsListing/widgets/app_button.dart';

import '../helpers/test_data.dart';

/// Test-only AuthController that skips platform-channel usage in onInit
/// (flutter_secure_storage has no plugin in the test environment).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus.
  }
}

/// Counts `register()` invocations and can hold the call in-flight via
/// [gate] so the test can fire a second verification while the first is
/// still pending (the exact race the re-entry guard is for).
class _FakeAuthService extends AuthService {
  _FakeAuthService() : super.testing();

  int registerCalls = 0;
  Completer<UserModel>? gate;

  @override
  Future<UserModel> register(
    String name,
    String mobile, {
    String role = UserModel.rolePatient,
  }) async {
    registerCalls++;
    final g = gate;
    if (g != null) return g.future;
    return userPatient();
  }
}

/// Base route used by the system-back test so the OTP screen is pushed
/// on top of something pop-able.
const String _baseRoute = '/otp-system-back-base';

/// Pumps the OTP screen (patient registration, no pre-selected doctor)
/// with an injectable [AuthService] fake and a registered `/home` route
/// so the post-verification navigation resolves.
Future<void> _pumpOtpScreen(
  WidgetTester tester, {
  required AuthService authService,
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
        displayName: 'Test Patient',
        mobile: '9876543210',
        role: UserModel.rolePatient,
        authService: authService,
      ),
    ),
  );
  // Advance past all initial flutter_animate fade-ins (longest chain ends
  // ~1.2s) in a single frame so the Verify button is fully visible and
  // hittable. The 1s resend-countdown timer fires once during this step
  // (schedules one frame) — harmless.
  await tester.pump(const Duration(milliseconds: 1500));
}

/// Disposes the OTP screen and advances 1s so the resend-countdown
/// `Future.doWhile` chain (one 1s one-shot timer at a time) sees the
/// screen is unmounted and terminates — otherwise the test framework
/// fails on a still-pending timer.
Future<void> _flushResendTimer(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  group('OtpVerificationScreen verification', () {
    testWidgets(
      'default OTP 1111 is pre-filled and verifies with exactly one '
      'register() call',
      (tester) async {
        final fake = _FakeAuthService();

        await _pumpOtpScreen(tester, authService: fake);

        // The default OTP '1111' is pre-filled → each pin box renders
        // the digit '1'. (find.text matches both the rendered Text and
        // the underlying EditableText per box, so assert a lower bound.)
        expect(find.text('1'), findsAtLeastNWidgets(4));
        expect(find.text('Verify & Continue'), findsOneWidget);

        await tester.tap(find.text('Verify & Continue'));
        await tester.pumpAndSettle();

        // Exactly one register() was made with the correct payload.
        expect(fake.registerCalls, 1);
        // Patient registration lands on the patient home.
        expect(find.text('PATIENT HOME'), findsOneWidget);

        // The screen was disposed by navigation mid-countdown; flush the
        // pending one-shot resend timer.
        await _flushResendTimer(tester);
      },
    );

    testWidgets('back button is disabled while verification is loading', (
      tester,
    ) async {
      final fake = _FakeAuthService();
      final gate = Completer<UserModel>();
      fake.gate = gate;

      await _pumpOtpScreen(tester, authService: fake);

      // Before verifying, back navigation is enabled.
      expect(
        tester.widget<AppBackButton>(find.byType(AppBackButton)).onPressed,
        isNotNull,
      );

      await tester.tap(find.text('Verify & Continue')); // in-flight
      await tester.pump();

      // While the registration is pending, back is disabled so the user
      // cannot pop the screen mid-register.
      expect(
        tester.widget<AppBackButton>(find.byType(AppBackButton)).onPressed,
        isNull,
      );

      gate.complete(userPatient());
      await tester.pumpAndSettle();
      expect(find.text('PATIENT HOME'), findsOneWidget);

      await _flushResendTimer(tester);
    });

    testWidgets('system back cannot pop the screen while verification is '
        'loading', (tester) async {
      final fake = _FakeAuthService();
      final gate = Completer<UserModel>();
      fake.gate = gate;

      // Pump the OTP screen PUSHED over a base route so there is actually
      // a route below it to pop back to.
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          getPages: [
            GetPage(
              name: _baseRoute,
              page: () => const Scaffold(body: Text('BASE SCREEN')),
            ),
            GetPage(
              name: AppRoutes.otpVerification,
              page: () => OtpVerificationScreen(
                displayName: 'Test Patient',
                mobile: '9876543210',
                role: UserModel.rolePatient,
                authService: fake,
              ),
            ),
            GetPage(
              name: AppRoutes.home,
              page: () => const Scaffold(body: Text('PATIENT HOME')),
            ),
          ],
          initialRoute: _baseRoute,
        ),
      );
      await tester.pumpAndSettle();

      Get.toNamed(AppRoutes.otpVerification);
      // Fixed pumps, not pumpAndSettle: the autofocused pin field's
      // blinking cursor animates indefinitely while the screen is
      // mounted, which would make pumpAndSettle time out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.byType(OtpVerificationScreen), findsOneWidget);

      // Start verification (held in-flight by the gate).
      await tester.tap(find.text('Verify & Continue'));
      await tester.pump();

      // Simulate the Android system back button → must NOT pop while the
      // registration is pending (PopScope canPop: false).
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pump();
      expect(find.byType(OtpVerificationScreen), findsOneWidget);

      // Complete → navigates to the patient home.
      gate.complete(userPatient());
      await tester.pumpAndSettle();
      expect(find.byType(OtpVerificationScreen), findsNothing);
      expect(find.text('PATIENT HOME'), findsOneWidget);

      await _flushResendTimer(tester);
    });

    testWidgets('non-default OTP is rejected without calling register()', (
      tester,
    ) async {
      final fake = _FakeAuthService();

      await _pumpOtpScreen(tester, authService: fake);

      // Simulate the user replacing the pre-filled 1111 with 2222. The
      // screen shares its private controller with the PinCodeTextField,
      // so writing through the widget's controller is equivalent to
      // typing.
      final pinField =
          tester.widget<PinCodeTextField>(find.byType(PinCodeTextField));
      pinField.controller?.text = '2222';
      await tester.pump();

      await tester.tap(find.text('Verify & Continue'));
      await tester.pump();

      // Wrong OTP → error shown, and register() is never reached.
      expect(fake.registerCalls, 0);
      expect(
        find.text('Invalid OTP. Please try again.'),
        findsOneWidget,
      );

      await _flushResendTimer(tester);
    });

    testWidgets(
      'a completed dev code auto-submits and wrong codes are '
      'rejected',
      (tester) async {
        final fake = _FakeAuthService();

        await _pumpOtpScreen(tester, authService: fake);

        // Replace the pre-filled 1111 with 2222 (4 digits = complete) →
        // auto-submit rejects it without registering.
        await tester.enterText(find.byType(PinCodeTextField), '2222');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(fake.registerCalls, 0);
        expect(find.text('Invalid OTP. Please try again.'), findsOneWidget);

        await _flushResendTimer(tester);
      },
    );

    testWidgets(
      'second Verify tap while a registration is in flight does NOT '
      'double-register (re-entry guard)',
      (tester) async {
        final fake = _FakeAuthService();
        final gate = Completer<UserModel>();
        fake.gate = gate;

        await _pumpOtpScreen(tester, authService: fake);

        final verifyButton = find.text('Verify & Continue');
        await tester.tap(verifyButton); // 1st call → register() in-flight

        // Tap again BEFORE any rebuild. The button's captured onPressed
        // still points at _verifyOtp, so without the `if (_isLoading)
        // return;` guard this would fire register() a second time.
        await tester.tap(verifyButton);

        // Guard swallowed the second invocation.
        expect(fake.registerCalls, 1);

        // Prove the registration is genuinely still in flight: the button
        // now shows its loading spinner (self-documents that tap #2 really
        // raced an active _verifyOtp rather than a settled one).
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Let the first registration complete → patient home.
        gate.complete(userPatient(id: 'otp_guard_user'));
        await tester.pumpAndSettle();

        expect(fake.registerCalls, 1);
        expect(find.text('PATIENT HOME'), findsOneWidget);

        // The screen was disposed by navigation mid-countdown; flush the
        // pending one-shot resend timer.
        await _flushResendTimer(tester);
      },
    );
  });
}
