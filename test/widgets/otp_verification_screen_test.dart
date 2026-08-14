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
///
/// [otpGenerator] injects a fixed client-side code so tests can assert
/// toast + local verification deterministically. The OTP send delay is
/// zeroed so the toast shows immediately instead of after 3s.
Future<void> _pumpOtpScreen(
  WidgetTester tester, {
  required AuthService authService,
  String Function()? otpGenerator,
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
        otpGenerator: otpGenerator,
        otpSendDelay: Duration.zero,
      ),
    ),
  );
  // Advance past all initial flutter_animate fade-ins (longest chain ends
  // ~1.2s) in a single frame so the Verify button is fully visible and
  // hittable. The 1s resend-countdown timer fires once during this step
  // (schedules one frame) — harmless.
  await tester.pump(const Duration(milliseconds: 1500));
}

/// Disposes the OTP screen and flushes pending timers so the test
/// framework doesn't fail on a still-pending timer:
///  (a) the demo-OTP toast's 6s snackbar display timer must expire and its
///      hide animation finish WHILE the overlay is still mounted (pumping
///      it after dispose leaks a ticker), and
///  (b) the resend-countdown `Future.doWhile` chain (one 1s one-shot
///      timer at a time) must see the screen unmounted and terminate.
/// Fixed pumps only — never pumpAndSettle while the OTP screen is
/// mounted (the pin field's blinking cursor animates forever).
Future<void> _flushResendTimer(WidgetTester tester) async {
  // Let the toast time out and hide while mounted.
  await tester.pump(const Duration(seconds: 7));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  // Force-close any snackbar still on screen (its reverse animation may
  // not have been driven to completion) while the overlay is alive.
  Get.closeAllSnackbars();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  // Now dispose and let the resend chain terminate.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
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
      'client-generated OTP is toasted (not pre-filled) and verifies '
      'locally with exactly one register() call',
      (tester) async {
        final fake = _FakeAuthService();

        await _pumpOtpScreen(
          tester,
          authService: fake,
          otpGenerator: () => '1234',
        );

        // The toast shows the code (demo mode) but the pin field is NOT
        // pre-filled — the user must type the code manually.
        expect(find.text('Demo OTP: 1234'), findsOneWidget);
        expect(find.text('Verify & Continue'), findsOneWidget);
        expect(find.text('1'), findsNothing);

        // User reads the code from the toast and types it in manually —
        // completing the 4th digit auto-submits verification.
        await tester.enterText(find.byType(PinCodeTextField), '1234');
        await tester.pumpAndSettle();

        // The code matched locally → exactly one register() ran.
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

      await _pumpOtpScreen(
        tester,
        authService: fake,
        otpGenerator: () => '1234',
      );

      // Before verifying, back navigation is enabled.
      expect(
        tester.widget<AppBackButton>(find.byType(AppBackButton)).onPressed,
        isNotNull,
      );

      // User types the code from the toast manually — completing the 4th
      // digit auto-submits verification (held in-flight by the gate).
      await tester.enterText(find.byType(PinCodeTextField), '1234');
      await tester.pump();
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
                otpGenerator: () => '1234',
                otpSendDelay: Duration.zero,
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

      // User types the code from the toast manually — completing the 4th
      // digit auto-submits verification (held in-flight by the gate).
      await tester.enterText(find.byType(PinCodeTextField), '1234');
      await tester.pump();
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

    testWidgets('non-matching OTP is rejected without calling register()', (
      tester,
    ) async {
      final fake = _FakeAuthService();

      await _pumpOtpScreen(
        tester,
        authService: fake,
        otpGenerator: () => '1234',
      );

      // The user types a WRONG code (local verification accepts only the
      // generated '1234'). Completing the 4th digit auto-submits → the
      // mismatch is rejected without ever calling register().
      await tester.enterText(find.byType(PinCodeTextField), '2222');
      await tester.pump();
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
      'a completed code auto-submits and wrong codes are '
      'rejected',
      (tester) async {
        final fake = _FakeAuthService();

        await _pumpOtpScreen(
          tester,
          authService: fake,
          otpGenerator: () => '1234',
        );

        // Replace the pre-filled code with a wrong 4-digit one (= complete
        // → auto-submit) → rejected without registering.
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

        await _pumpOtpScreen(
          tester,
          authService: fake,
          otpGenerator: () => '1234',
        );

        // Typing the full code auto-submits (register() now in-flight,
        // held by the gate). A button tap landing before the rebuild would
        // otherwise fire _verifyOtp a second time — the `if (_isLoading)
        // return;` guard swallows it.
        await tester.enterText(find.byType(PinCodeTextField), '1234');
        // No pump between enterText and the tap: the button's captured
        // onPressed still points at _verifyOtp (the loading rebuild that
        // disables it hasn't happened yet).
        await tester.tap(find.text('Verify & Continue'));

        // Guard swallowed the second invocation → still exactly one.
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
