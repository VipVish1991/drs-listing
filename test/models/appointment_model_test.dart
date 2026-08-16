import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/models/appointment_model.dart';

void main() {
  group('AppointmentModel.displayDate', () {
    AppointmentModel make({String? date}) => AppointmentModel(
      appointmentId: 'APT1',
      appointmentDate: date,
    );

    test('formats yyyy-MM-dd to dd-MM-yyyy', () {
      expect(make(date: '2026-08-08').displayDate, '08-08-2026');
      expect(make(date: '2026-07-01').displayDate, '01-07-2026');
      expect(make(date: '2026-12-25').displayDate, '25-12-2026');
    });

    test('pads single-digit day and month', () {
      expect(make(date: '2026-08-05').displayDate, '05-08-2026');
      expect(make(date: '2026-01-01').displayDate, '01-01-2026');
    });

    test('keeps the raw value when the date is null or empty', () {
      expect(make(date: null).displayDate, isNull);
      expect(make(date: '').displayDate, '');
    });

    test('falls back to the raw value when unparseable', () {
      expect(make(date: 'not-a-date').displayDate, 'not-a-date');
      expect(make(date: '08/08/2026').displayDate, '08/08/2026');
    });
  });

  group('AppointmentModel.meetLink', () {
    test('fromJson reads meet_link and toJson round-trips it', () {
      final appointment = AppointmentModel.fromJson({
        'appointment_id': 'APT1',
        'meet_link': 'https://meet.google.com/abc-def-ghi',
      });

      expect(appointment.meetLink, 'https://meet.google.com/abc-def-ghi');
      expect(
        appointment.toJson()['meet_link'],
        'https://meet.google.com/abc-def-ghi',
      );
    });

    test('null/empty meet_link is omitted from toJson and read as null', () {
      final appointment = AppointmentModel.fromJson({
        'appointment_id': 'APT2',
      });

      expect(appointment.meetLink, isNull);
      expect(appointment.toJson().containsKey('meet_link'), isFalse);
    });

    test('copyWith updates the meet link (in-place save pattern)', () {
      final appointment = AppointmentModel(
        appointmentId: 'APT3',
      );

      final withLink = appointment.copyWith(
        meetLink: 'https://meet.google.com/xyz-uvw-123',
      );
      expect(withLink.meetLink, 'https://meet.google.com/xyz-uvw-123');
      // Other fields are untouched.
      expect(withLink.appointmentId, 'APT3');

      // Null keeps the existing value (copyWith's nullable-field contract).
      final unchanged = withLink.copyWith(meetLink: null);
      expect(unchanged.meetLink, 'https://meet.google.com/xyz-uvw-123');
    });
  });
}
