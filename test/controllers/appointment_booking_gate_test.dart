import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';

/// The "one patient, one doctor at a time" gate:
///   * an active (Pending/Upcoming) booking always blocks;
///   * otherwise the next booking is allowed only once 12 hours have
///     passed since the most recent booking was created — Completed and
///     Cancelled bookings still trigger the wait.
void main() {
  AppointmentModel apt({
    required String status,
    DateTime? createdAt,
  }) {
    return AppointmentModel(
      appointmentId: 'APT-test-${DateTime.now().microsecondsSinceEpoch}',
      status: status,
      createdAt: createdAt,
    );
  }

  DateTime justNow() => DateTime.now();

  group('AppointmentController.bookingBlockMessage', () {
    test('allows booking with no appointments at all', () {
      expect(AppointmentController.bookingBlockMessage(const []), isNull);
    });

    test('blocks while a Pending booking is active', () {
      final msg = AppointmentController.bookingBlockMessage([
        apt(status: AppointmentStatus.pending, createdAt: justNow()),
      ]);
      expect(msg, isNotNull);
      expect(msg, contains('already have an appointment'));
    });

    test('blocks while an Upcoming booking is active', () {
      final msg = AppointmentController.bookingBlockMessage([
        apt(status: AppointmentStatus.upcoming, createdAt: justNow()),
      ]);
      expect(msg, isNotNull);
      expect(msg, contains('already have an appointment'));
    });

    test('blocks within the 12h cooldown after a Completed booking', () {
      final msg = AppointmentController.bookingBlockMessage([
        apt(
          status: AppointmentStatus.completed,
          createdAt: justNow().subtract(const Duration(minutes: 30)),
        ),
      ]);
      expect(msg, isNotNull);
      expect(msg, contains('after your last booking'));
    });

    test('blocks within the 12h cooldown after a Cancelled booking', () {
      final msg = AppointmentController.bookingBlockMessage([
        apt(
          status: AppointmentStatus.cancelled,
          createdAt: justNow().subtract(const Duration(hours: 5)),
        ),
      ]);
      expect(msg, isNotNull);
      expect(msg, contains('12 hours'));
    });

    test('allows booking 12+ hours after the last Completed booking', () {
      final msg = AppointmentController.bookingBlockMessage([
        apt(
          status: AppointmentStatus.completed,
          createdAt: justNow().subtract(const Duration(hours: 13)),
        ),
      ]);
      expect(msg, isNull);
    });

    test('allows booking 12+ hours after the last Cancelled booking', () {
      final msg = AppointmentController.bookingBlockMessage([
        apt(
          status: AppointmentStatus.cancelled,
          createdAt: justNow().subtract(const Duration(hours: 20)),
        ),
      ]);
      expect(msg, isNull);
    });

    test('an active booking blocks even when it is older than 12h', () {
      final msg = AppointmentController.bookingBlockMessage([
        apt(
          status: AppointmentStatus.upcoming,
          createdAt: justNow().subtract(const Duration(days: 2)),
        ),
      ]);
      expect(msg, isNotNull);
      expect(msg, contains('already have an appointment'));
    });

    test('cooldown is measured from the MOST RECENT booking', () {
      // An old booking alone would be fine, but a recent one (30 min ago)
      // still within the cooldown blocks.
      final msg = AppointmentController.bookingBlockMessage([
        apt(
          status: AppointmentStatus.completed,
          createdAt: justNow().subtract(const Duration(days: 5)),
        ),
        apt(
          status: AppointmentStatus.completed,
          createdAt: justNow().subtract(const Duration(minutes: 30)),
        ),
      ]);
      expect(msg, isNotNull);
    });

    test('appointments with no created_at are ignored for the cooldown', () {
      final msg = AppointmentController.bookingBlockMessage([
        apt(status: AppointmentStatus.completed),
      ]);
      expect(msg, isNull);
    });
  });

  group('AppointmentController.bookingBlockMessageFromError', () {
    test('maps the DB active-booking marker to the friendly message', () {
      final msg = AppointmentController.bookingBlockMessageFromError(
        Exception(
          'appointments_one_active_booking: patient 123 already has an '
          'active appointment APT999',
        ),
      );
      expect(msg, isNotNull);
      expect(msg, contains('already have an appointment'));
    });

    test('maps the DB cooldown marker to the friendly message', () {
      final msg = AppointmentController.bookingBlockMessageFromError(
        Exception(
          'appointments_booking_cooldown: patient 123 must wait 12 hours '
          'after their last booking',
        ),
      );
      expect(msg, isNotNull);
      expect(msg, contains('12 hours after your last booking'));
    });

    test('returns null for non-gate errors (slot taken, network, RLS)', () {
      expect(
        AppointmentController.bookingBlockMessageFromError(
          Exception('appointments_slot_occupied: slot already booked'),
        ),
        isNull,
      );
      expect(
        AppointmentController.bookingBlockMessageFromError(
          Exception('Connection refused'),
        ),
        isNull,
      );
    });
  });
}
