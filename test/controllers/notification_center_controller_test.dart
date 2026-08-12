import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/notification_center_controller.dart';
import 'package:DrsListing/models/notification_item.dart';
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

  NotificationItem makeItem(String id, {bool read = false}) => NotificationItem(
        id: id,
        type: 'appointment_booked',
        title: 'New Appointment Request',
        body: 'Rahul booked for 10-08-2026 at 10:00 AM.',
        data: const {'appointment_id': 'APT999', 'doctor_place_id': 'place-1'},
        read: read,
        createdAt: DateTime(2026, 8, 6, 10),
      );

  group('load', () {
    test('clears the unread badge without a logged-in user', () async {
      final c = Get.put(NotificationCenterController());
      await c.load();
      expect(c.unreadCount.value, 0);
      expect(c.items, isEmpty);
    });

    test('is non-fatal when Supabase is unavailable', () async {
      final c = Get.put(NotificationCenterController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');

      await c.load();
      // The fetch throws in the test env → list stays empty, loading resets.
      expect(c.isLoading.value, isFalse);
      expect(c.items, isEmpty);
      expect(c.unreadCount.value, 0);
    });
  });

  group('markRead', () {
    test('marks the item read and decrements the unread count', () async {
      final c = Get.put(NotificationCenterController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');
      c.items.value = [makeItem('n1'), makeItem('n2', read: true)];

      expect(c.unreadCount.value, 1);
      await c.markRead(c.items.first);

      expect(c.items.first.read, isTrue);
      expect(c.unreadCount.value, 0);
    });

    test('is a no-op for an already-read item', () async {
      final c = Get.put(NotificationCenterController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');
      c.items.value = [makeItem('n1', read: true)];

      await c.markRead(c.items.first);
      expect(c.unreadCount.value, 0);
    });

    test('does not crash without a logged-in user (no-op)', () async {
      final c = Get.put(NotificationCenterController());
      c.items.value = [makeItem('n1')];
      await c.markRead(c.items.first);
      // Nothing to save against — the row stays unread (no-op, not a crash).
      expect(c.items.first.read, isFalse);
      expect(c.unreadCount.value, 1);
    });
  });

  group('markDoctorEventsRead', () {
    test('marks doctor-event items read but leaves patient events unread',
        () async {
      final c = Get.put(NotificationCenterController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');
      c.items.value = [
        makeItem('n1'), // appointment_booked (doctor event)
        NotificationItem(
          id: 'n2',
          type: 'appointment_status_changed', // patient event
          title: 'Appointment Confirmed',
          body: 'Rahul confirmed your appointment.',
          data: const {'appointment_id': 'APT999', 'status': 'Upcoming'},
          read: false,
          createdAt: DateTime(2026, 8, 6, 11),
        ),
        makeItem('n3', read: true),
      ];

      expect(c.unreadCount.value, 2);
      await c.markDoctorEventsRead();

      // Booking notification -> read; status change stays unread;
      // already-read row untouched.
      expect(c.items[0].read, isTrue);
      expect(c.items[1].read, isFalse);
      expect(c.items[2].read, isTrue);
      expect(c.unreadCount.value, 1);
    });

    test('is a no-op without a logged-in user (no crash)', () async {
      final c = Get.put(NotificationCenterController());
      c.items.value = [makeItem('n1')];
      await c.markDoctorEventsRead();
      expect(c.items.first.read, isFalse);
      expect(c.unreadCount.value, 1);
    });

    test('does not touch anything when nothing is unread', () async {
      final c = Get.put(NotificationCenterController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');
      c.items.value = [
        makeItem('n1', read: true),
        NotificationItem(
          id: 'n2',
          type: 'appointment_status_changed',
          title: 'Appointment Confirmed',
          body: 'Rahul confirmed your appointment.',
          data: const {'appointment_id': 'APT999', 'status': 'Upcoming'},
          read: false,
          createdAt: DateTime(2026, 8, 6, 11),
        ),
      ];

      await c.markDoctorEventsRead();
      // No doctor event was unread -> nothing changes.
      expect(c.items[0].read, isTrue);
      expect(c.items[1].read, isFalse);
      expect(c.unreadCount.value, 1);
    });
  });

  group('markAppointmentRead', () {
    test('marks only the matching appointment\'s notifications read',
        () async {
      final c = Get.put(NotificationCenterController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');
      c.items.value = [
        makeItem('n1'), // APT999, unread
        makeItem('n2', read: true), // APT999, already read
        NotificationItem(
          id: 'n3',
          type: 'appointment_booked',
          title: 'New Appointment Request',
          body: 'Sara booked for 11-08-2026 at 4:00 PM.',
          data: const {
            'appointment_id': 'APT888',
            'doctor_place_id': 'place-1',
          },
          read: false,
          createdAt: DateTime(2026, 8, 6, 12),
        ),
      ];

      expect(c.unreadCount.value, 2);
      await c.markAppointmentRead('APT999');

      // Both APT999 rows read; the other appointment stays unread.
      expect(c.items[0].read, isTrue);
      expect(c.items[1].read, isTrue);
      expect(c.items[2].read, isFalse);
      expect(c.unreadCount.value, 1);
    });

    test('is a no-op without a logged-in user (no crash)', () async {
      final c = Get.put(NotificationCenterController());
      c.items.value = [makeItem('n1')];
      await c.markAppointmentRead('APT999');
      expect(c.items.first.read, isFalse);
      expect(c.unreadCount.value, 1);
    });

    test('ignores an empty appointment id', () async {
      final c = Get.put(NotificationCenterController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');
      c.items.value = [makeItem('n1')];

      await c.markAppointmentRead('');
      expect(c.items.first.read, isFalse);
      expect(c.unreadCount.value, 1);
    });

    test('does not touch anything when no notification matches', () async {
      final c = Get.put(NotificationCenterController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');
      c.items.value = [makeItem('n1')]; // APT999

      await c.markAppointmentRead('APT777');
      expect(c.items.first.read, isFalse);
      expect(c.unreadCount.value, 1);
    });
  });

  group('markAllRead', () {
    test('marks every item read and clears the badge', () async {
      final c = Get.put(NotificationCenterController());
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_1', mobile: '9876543210');
      c.items.value = [makeItem('n1'), makeItem('n2'), makeItem('n3', read: true)];

      await c.markAllRead();

      expect(c.items.every((n) => n.read), isTrue);
      expect(c.unreadCount.value, 0);
    });
  });
}
