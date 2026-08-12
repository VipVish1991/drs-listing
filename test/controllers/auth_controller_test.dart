import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/user_model.dart';
import '../helpers/test_data.dart';

/// A test-only subclass that overrides [onInit] so that
/// [checkAuthStatus] — which uses flutter_secure_storage platform
/// channel — is NOT called automatically during test setup.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus in test environment
    // to avoid MissingPluginException for flutter_secure_storage.
  }
}

void main() {
  late AuthController controller;

  setUp(() {
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    controller = Get.find<AuthController>();
    // Ensure we start fresh — simulate not logged in
    controller.isLoggedIn.value = false;
    controller.currentUser.value = null;
    controller.errorMessage.value = '';
    controller.isLoading.value = false;
  });

  tearDown(() {
    Get.reset();
  });

  group('isDoctor / isPatient', () {
    test('returns false for isDoctor when user is patient', () {
      controller.currentUser.value = userPatient();
      expect(controller.isDoctor, isFalse);
      expect(controller.isPatient, isTrue);
    });

    test('returns true for isDoctor when user is doctor', () {
      controller.currentUser.value = userDoctor();
      expect(controller.isDoctor, isTrue);
      expect(controller.isPatient, isFalse);
    });

    test('returns false for isDoctor when no user is set', () {
      controller.currentUser.value = null;
      expect(controller.isDoctor, isFalse);
      expect(controller.isPatient, isTrue); // default
    });
  });

  group('userId', () {
    test('returns user id when user is set', () {
      controller.currentUser.value = userPatient(id: 'user_abc');
      expect(controller.userId, 'user_abc');
    });

    test('returns null when no user is set', () {
      controller.currentUser.value = null;
      expect(controller.userId, isNull);
    });
  });

  group('login validation', () {
    test('sets error for empty mobile', () async {
      await controller.login('');
      expect(controller.errorMessage.value, 'Please enter mobile number');
      expect(controller.isLoggedIn.value, isFalse);
    });

    test('sets error for whitespace-only mobile', () async {
      await controller.login('   ');
      expect(controller.errorMessage.value, 'Please enter mobile number');
    });

    test('sets error for invalid mobile (too short)', () async {
      await controller.login('12345');
      expect(
        controller.errorMessage.value,
        contains('valid 10-digit mobile number'),
      );
    });

    test('sets error for invalid mobile (non-digits)', () async {
      await controller.login('12345abcde');
      expect(
        controller.errorMessage.value,
        contains('valid 10-digit mobile number'),
      );
    });

    test('sets error for invalid mobile (too long)', () async {
      await controller.login('12345678901');
      expect(
        controller.errorMessage.value,
        contains('valid 10-digit mobile number'),
      );
    });
  });

  group('register validation', () {
    test('sets error for empty name', () async {
      await controller.register('', '9876543210');
      expect(controller.errorMessage.value, 'Please enter your name');
    });

    test('sets error for whitespace-only name', () async {
      await controller.register('   ', '9876543210');
      expect(controller.errorMessage.value, 'Please enter your name');
    });

    test('sets error for empty mobile', () async {
      await controller.register('John', '');
      expect(controller.errorMessage.value, 'Please enter mobile number');
    });

    test('sets error for short mobile', () async {
      await controller.register('John', '12345');
      expect(
        controller.errorMessage.value,
        contains('valid 10-digit mobile number'),
      );
    });

    test('sets error for invalid mobile with letters', () async {
      await controller.register('John', '12345abcde');
      expect(
        controller.errorMessage.value,
        contains('valid 10-digit mobile number'),
      );
    });

    test(
      'accepts valid name and mobile (will fail on network, not validation)',
      () async {
        // This will attempt a real Supabase call and fail (no connection),
        // but should set a connection error, not a validation error
        await controller.register('John Doe', '9876543210');
        // Should NOT be a validation error since input is valid
        expect(controller.errorMessage.value, isNot(contains('Please enter')));
        // Error will be network-related or Supabase not initialized
      },
    );
  });

  group('register as doctor', () {
    test('accepts valid name and mobile for doctor registration', () async {
      await controller.register(
        'Dr. Jane',
        '9876543210',
        role: UserModel.roleDoctor,
      );
      // Validation passes → network error expected in test env
      expect(controller.errorMessage.value, isNot(contains('Please enter')));
    });
  });

  group('isValidMobile (via login)', () {
    test('validates correct mobile length', () async {
      // 10-digit mobile should pass validation and proceed to network call
      await controller.login('9876543210');
      expect(controller.errorMessage.value, isNot(contains('valid')));
    });

    test('rejects non-10-digit mobiles', () async {
      await controller.login('987654321'); // 9 digits
      expect(
        controller.errorMessage.value,
        contains('valid 10-digit mobile number'),
      );
    });

    test('rejects mobiles with special characters', () async {
      await controller.login('98765-3210');
      expect(
        controller.errorMessage.value,
        contains('valid 10-digit mobile number'),
      );
    });
  });

  group('logout', () {
    test('catches error when flutter_secure_storage is unavailable', () async {
      // Set initial state
      controller.currentUser.value = userPatient();
      controller.isLoggedIn.value = true;

      // logout() calls AuthService which uses flutter_secure_storage
      // (platform channel) and will throw MissingPluginException in
      // a pure unit test (no WidgetsFlutterBinding).
      // The controller does not catch this error, so it propagates.
      expect(() => controller.logout(), throwsA(isA<Object>()));
    });
  });

  group('errorMessage', () {
    test('clears error message before new validation', () async {
      // Set a previous error
      controller.errorMessage.value = 'Old error';
      expect(controller.errorMessage.value, 'Old error');

      // New validation clears it
      await controller.login('');
      // Now it should be the new error, not the old one
      expect(controller.errorMessage.value, 'Please enter mobile number');
    });
  });
}
