import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/models/notification_item.dart';

void main() {
  NotificationItem base() => NotificationItem(
        id: 'n1',
        type: 'appointment_booked',
        title: 'New Appointment Request',
        body: 'Rahul booked for 10-08-2026 at 10:00 AM.',
        data: const {
          'appointment_id': 'APT999',
          'doctor_place_id': 'place-1',
          'doctor_name': 'Dr. Test Clinic',
          'patient_name': 'Rahul Sharma',
          'appointment_date': '2026-08-10',
          'appointment_time': '10:00 AM',
        },
        createdAt: DateTime(2026, 8, 6, 10),
      );

  group('fromJson', () {
    test('parses the server row including the data payload', () {
      final item = NotificationItem.fromJson({
        'id': 'n1',
        'type': 'appointment_status_changed',
        'title': 'Appointment Confirmed',
        'body': 'Dr. Test confirmed your appointment.',
        'data': {
          'appointment_id': 'APT999',
          'doctor_place_id': 'place-1',
          'doctor_name': 'Dr. Test Clinic',
          'status': 'Confirmed',
        },
        'read': true,
        'created_at': '2026-08-06T10:00:00Z',
      });

      expect(item.id, 'n1');
      expect(item.type, 'appointment_status_changed');
      expect(item.read, isTrue);
      expect(item.doctorName, 'Dr. Test Clinic');
      expect(item.status, 'Confirmed');
      expect(item.appointmentId, 'APT999');
      expect(item.doctorPlaceId, 'place-1');
    });

    test('survives rows without a data payload (legacy)', () {
      final item = NotificationItem.fromJson({
        'id': 'n1',
        'type': 'appointment_booked',
        'title': 'New Appointment Request',
        'body': null,
        'read': false,
        'created_at': '2026-08-06T10:00:00Z',
      });

      expect(item.doctorName, isNull);
      expect(item.destinationLabel, 'Opens Doctor Dashboard');
    });
  });

  group('destination helpers', () {
    test('doctor events (booked/cancelled) target the doctor dashboard', () {
      expect(base().isDoctorEvent, isTrue);
      expect(base().destinationLabel, 'Opens Doctor Dashboard');

      final cancelled = NotificationItem(
        id: 'n2',
        type: 'appointment_cancelled',
        title: 'Appointment Cancelled',
        createdAt: DateTime(2026, 8, 6, 11),
      );
      expect(cancelled.isDoctorEvent, isTrue);
      expect(cancelled.destinationLabel, 'Opens Doctor Dashboard');
    });

    test('status changes target the appointment history', () {
      final statusChanged = NotificationItem(
        id: 'n3',
        type: 'appointment_status_changed',
        title: 'Appointment Confirmed',
        createdAt: DateTime(2026, 8, 6, 11),
      );
      expect(statusChanged.isDoctorEvent, isFalse);
      expect(statusChanged.destinationLabel, 'Opens Appointment History');
    });

    test('exposes the doctor name from the payload', () {
      expect(base().doctorName, 'Dr. Test Clinic');
    });
  });
}
