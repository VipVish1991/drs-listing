import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';

/// The "one active booking per doctor" gate:
///   * an active (Pending/Upcoming) booking with the SAME doctor blocks
///     a second booking with that doctor;
///   * bookings with OTHER doctors are never blocked — the patient can
///     hold active bookings with several doctors simultaneously;
///   * the same doctor can be re-booked immediately once the active
///     booking is Completed or Cancelled (no cooldown).
void main() {
  AppointmentModel apt({
    required String status,
    String? doctorPlaceId = 'PLACE-DOC-A',
  }) {
    return AppointmentModel(
      appointmentId: 'APT-test-${DateTime.now().microsecondsSinceEpoch}',
      status: status,
      doctorPlaceId: doctorPlaceId,
    );
  }

  group('AppointmentController.bookingBlockMessage', () {
    test('allows booking with no appointments at all', () {
      expect(
        AppointmentController.bookingBlockMessage(
          const [],
          doctorPlaceId: 'PLACE-DOC-A',
        ),
        isNull,
      );
    });

    test('blocks while a Pending booking is active with the SAME doctor',
        () {
      final msg = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.pending)],
        doctorPlaceId: 'PLACE-DOC-A',
      );
      expect(msg, isNotNull);
      expect(msg, contains('active appointment with this doctor'));
    });

    test('blocks while an Upcoming booking is active with the SAME doctor',
        () {
      final msg = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.upcoming)],
        doctorPlaceId: 'PLACE-DOC-A',
      );
      expect(msg, isNotNull);
      expect(msg, contains('active appointment with this doctor'));
    });

    test('allows booking with a DIFFERENT doctor while one is active', () {
      final msg = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.pending)],
        doctorPlaceId: 'PLACE-DOC-B',
      );
      expect(msg, isNull);
    });

    test('allows booking with the same doctor after it is Completed', () {
      final msg = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.completed)],
        doctorPlaceId: 'PLACE-DOC-A',
      );
      expect(msg, isNull);
    });

    test('allows booking with the same doctor after it is Cancelled', () {
      final msg = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.cancelled)],
        doctorPlaceId: 'PLACE-DOC-A',
      );
      expect(msg, isNull);
    });

    test('no 12h cooldown: recently completed booking does not block', () {
      final msg = AppointmentController.bookingBlockMessage(
        [
          apt(
            status: AppointmentStatus.completed,
            doctorPlaceId: 'PLACE-DOC-A',
          ),
        ],
        doctorPlaceId: 'PLACE-DOC-A',
      );
      expect(msg, isNull);
    });

    test('an active booking with doctor A blocks only doctor A', () {
      final msgForA = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.upcoming)],
        doctorPlaceId: 'PLACE-DOC-A',
      );
      final msgForB = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.upcoming)],
        doctorPlaceId: 'PLACE-DOC-B',
      );
      expect(msgForA, isNotNull);
      expect(msgForB, isNull);
    });

    test('without a doctor context, an active booking shows the notice', () {
      final msg = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.pending)],
      );
      expect(msg, isNotNull);
      expect(msg, contains('active appointment'));
    });

    test('without a doctor context, completed/cancelled only is null', () {
      final msg = AppointmentController.bookingBlockMessage(
        [
          apt(status: AppointmentStatus.completed),
          apt(status: AppointmentStatus.cancelled),
        ],
      );
      expect(msg, isNull);
    });

    test('an active booking blocks even when it is old', () {
      final msg = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.upcoming)],
        doctorPlaceId: 'PLACE-DOC-A',
      );
      expect(msg, isNotNull);
      expect(msg, contains('active appointment with this doctor'));
    });

    test('legacy appointment without doctor id never blocks a doctor', () {
      final msg = AppointmentController.bookingBlockMessage(
        [apt(status: AppointmentStatus.pending, doctorPlaceId: null)],
        doctorPlaceId: 'PLACE-DOC-A',
      );
      expect(msg, isNull);
    });
  });

  group('AppointmentController.bookingBlockMessageFromError', () {
    test('maps the DB active-booking marker to the friendly message', () {
      final msg = AppointmentController.bookingBlockMessageFromError(
        Exception(
          'appointments_one_active_booking: patient 123 already has an '
          'active appointment APT999 with this doctor',
        ),
      );
      expect(msg, isNotNull);
      expect(msg, contains('active appointment with this doctor'));
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
