import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import '../helpers/test_data.dart';
/// Test-only AuthController that skips platform-channel usage in onInit.
class _TestAuthGuardController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus to avoid
    // MissingPluginException for flutter_secure_storage in test env.
  }
}

void main() {
  late AuthController controller;

  setUp(() {
    Get.put<AuthController>(_TestAuthGuardController(), permanent: true);
    controller = Get.find<AuthController>();
    controller.isLoggedIn.value = false;
    controller.currentUser.value = null;
    controller.errorMessage.value = '';
    controller.isLoading.value = false;
  });

  tearDown(() {
    Get.reset();
  });

  group('completeDoctorConnection guard (null user)', () {
    test('returns false when no user is logged in', () async {
      controller.currentUser.value = null;

      final result = await controller.completeDoctorConnection(doctorBasic());

      expect(result, isFalse);
    });

    test('sets error message when no user is logged in', () async {
      controller.currentUser.value = null;

      await controller.completeDoctorConnection(doctorBasic());

      expect(
        controller.errorMessage.value,
        'Please log in first to connect a doctor.',
      );
    });

    test('sets error message without Supabase being initialized', () async {
      // Verifies the null-user guard fires BEFORE any Supabase call,
      // so it works even without Supabase being initialized.
      controller.currentUser.value = null;

      await controller.completeDoctorConnection(doctorMinimal());

      expect(
        controller.errorMessage.value,
        'Please log in first to connect a doctor.',
      );
    });
  });

  group('isDoctor guard (currentUser null)', () {
    test('returns false when no user is set', () {
      controller.currentUser.value = null;
      expect(controller.isDoctor, isFalse);
    });

    test('returns false when user role is patient', () {
      controller.currentUser.value = userPatient();
      expect(controller.isDoctor, isFalse);
    });

    test('returns true when user role is doctor', () {
      controller.currentUser.value = userDoctor();
      expect(controller.isDoctor, isTrue);
    });
  });

  group('isPatient default', () {
    test('returns true when no user is set (default)', () {
      controller.currentUser.value = null;
      expect(controller.isPatient, isTrue);
    });

    test('returns true when user role is patient', () {
      controller.currentUser.value = userPatient();
      expect(controller.isPatient, isTrue);
    });

    test('returns false when user role is doctor', () {
      controller.currentUser.value = userDoctor();
      expect(controller.isPatient, isFalse);
    });
  });

  group('pendingDoctor — login guard integration', () {
    test(
      'login with pendingDoctor rejects empty mobile before connection',
      () async {
        controller.currentUser.value = userPatient();
        final doctor = doctorBasic(placeId: 'pending_doc');

        await controller.login('', pendingDoctor: doctor);

        // Validation error, not a connection error
        expect(controller.errorMessage.value, contains('mobile number'));
        expect(controller.isLoggedIn.value, isFalse);
      },
    );

    test(
      'login with pendingDoctor uses currentUser that is already set',
      () async {
        // Simulate: user successfully logged in
        controller.currentUser.value = userPatient();
        controller.isLoggedIn.value = true;

        // Then login is called again with a pendingDoctor
        // Validation passes → connection attempt (will fail in test env)
        await controller.login('9876543210', pendingDoctor: doctorBasic());

        // Should NOT be a "log in first" guard error — user is logged in
        expect(controller.errorMessage.value, isNot(contains('log in first')));
      },
    );
  });

  group('pendingDoctor — register guard integration', () {
    test(
      'register with pendingDoctor rejects empty name before connection',
      () async {
        final doctor = doctorBasic(placeId: 'reg_doc');

        await controller.register('', '9876543210', pendingDoctor: doctor);

        expect(controller.errorMessage.value, contains('name'));
      },
    );

    test(
      'register with pendingDoctor uses currentUser that is already set',
      () async {
        // Simulate: registration completed successfully
        controller.currentUser.value = userPatient();
        controller.isLoggedIn.value = true;

        // Then register is called again with a pendingDoctor
        await controller.register(
          'Dr. Test',
          '9876543210',
          pendingDoctor: doctorBasic(),
        );

        // Should NOT be a "log in first" guard error — user is logged in
        expect(controller.errorMessage.value, isNot(contains('log in first')));
      },
    );
  });
}
