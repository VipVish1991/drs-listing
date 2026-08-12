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
}
