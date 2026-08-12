import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/notification_settings_controller.dart';
import '../helpers/test_data.dart';

/// Test-only AuthController that skips the secure-storage platform channel
/// (same pattern as the existing auth_controller_test).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  group('defaults', () {
    test('all five event toggles default to ON', () {
      final c = Get.put(NotificationSettingsController());
      expect(c.prefs[NotificationSettingsController.eventBooked], isTrue);
      expect(c.prefs[NotificationSettingsController.eventCancelled], isTrue);
      expect(c.prefs[NotificationSettingsController.eventRescheduled], isTrue);
      expect(
        c.prefs[NotificationSettingsController.eventRescheduledByDoctor],
        isTrue,
      );
      expect(
        c.prefs[NotificationSettingsController.eventStatusChanged],
        isTrue,
      );
    });

    test('the master switch defaults to ON', () {
      final c = Get.put(NotificationSettingsController());
      expect(c.allEnabled, isTrue);
      expect(c.prefs[NotificationSettingsController.eventAll], isTrue);
    });

    test('exposes exactly the five supported event keys', () {
      expect(
        NotificationSettingsController.eventKeys,
        unorderedEquals([
          'appointment_booked',
          'appointment_cancelled',
          'appointment_rescheduled',
          'appointment_rescheduled_by_doctor',
          'appointment_status_changed',
        ]),
      );
    });

    test('allKeys includes the master switch plus every event', () {
      expect(
        NotificationSettingsController.allKeys,
        unorderedEquals([
          'all',
          'appointment_booked',
          'appointment_cancelled',
          'appointment_rescheduled',
          'appointment_rescheduled_by_doctor',
          'appointment_status_changed',
        ]),
      );
    });
  });

  group('loadPrefs', () {
    test('keeps defaults and resets loading when Supabase is unavailable', () async {
      final c = Get.put(NotificationSettingsController());
      // A logged-in user is required for loadPrefs to even try the DB.
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');

      await c.loadPrefs();

      // Supabase is not initialized in tests → the fetch throws → defaults stay.
      expect(c.prefs[NotificationSettingsController.eventBooked], isTrue);
      expect(c.isLoading.value, isFalse);
    });

    test('no-ops without a logged-in user', () async {
      final c = Get.put(NotificationSettingsController());
      await c.loadPrefs();
      expect(c.isLoading.value, isFalse);
    });
  });

  group('setPref', () {
    test('reverts the toggle when the save fails (Supabase unavailable)', () async {
      final c = Get.put(NotificationSettingsController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');

      expect(c.prefs[NotificationSettingsController.eventBooked], isTrue);
      await c.setPref(NotificationSettingsController.eventBooked, false);

      // The save throws in the test environment → the value reverts so the
      // UI never shows a state the server doesn't have.
      expect(c.prefs[NotificationSettingsController.eventBooked], isTrue);
    });

    test('master switch reverts when the save fails', () async {
      final c = Get.put(NotificationSettingsController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');

      expect(c.allEnabled, isTrue);
      await c.setPref(NotificationSettingsController.eventAll, false);

      // Save throws in the test env → reverts back to ON.
      expect(c.allEnabled, isTrue);
    });

    test('does not crash without a logged-in user', () async {
      final c = Get.put(NotificationSettingsController());
      await c.setPref(NotificationSettingsController.eventCancelled, false);
      // Optimistically flipped (nothing to save to).
      expect(
        c.prefs[NotificationSettingsController.eventCancelled],
        isFalse,
      );
    });
  });
}
