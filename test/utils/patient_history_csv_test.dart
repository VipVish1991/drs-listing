import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/utils/patient_history_csv.dart';

import '../helpers/test_data.dart';

void main() {
  test('builds a header plus one row per visit, in the given order', () {
    final csv = buildPatientHistoryCsv([
      appointmentBasic(
        appointmentId: 'APT1',
        appointmentDate: '2026-08-01',
        appointmentTime: '11:00 AM',
        status: 'Completed',
        consultationType: 'video',
        symptoms: 'Recurring headache',
        prescriptionUrls: const ['https://example.com/rx1.jpg'],
      ),
      appointmentBasic(
        appointmentId: 'APT2',
        appointmentDate: '2026-07-20',
        appointmentTime: '9:30 AM',
        status: 'Upcoming',
        consultationType: 'clinic',
      ),
    ]);

    final lines = csv.split('\r\n');
    expect(
      lines.first,
      'Date,Time,Status,Consultation,Symptoms,Prescriptions,Appointment ID',
    );
    expect(
      lines[1],
      '01-08-2026,11:00 AM,Completed,Video Consultation,'
      'Recurring headache,1,APT1',
    );
    expect(lines[2], '20-07-2026,9:30 AM,Upcoming,In-Clinic Visit,,0,APT2');
  });

  test('empty list yields only the header', () {
    final csv = buildPatientHistoryCsv(const []);

    expect(csv.split('\r\n'), hasLength(1));
    expect(csv, contains('Date,Time,Status'));
  });

  test(
    'legacy rows without a stored type render an empty consultation cell',
    () {
      final csv = buildPatientHistoryCsv([
        appointmentBasic(
          appointmentId: 'APT3',
          appointmentDate: '2026-06-15',
          appointmentTime: '2:00 PM',
          status: 'Completed',
          // No consultationType → legacy row.
        ),
      ]);

      final row = csv.split('\r\n')[1];
      expect(row, '15-06-2026,2:00 PM,Completed,,,0,APT3');
    },
  );

  test('RFC 4180: quotes fields containing commas or quotes', () {
    final csv = buildPatientHistoryCsv([
      appointmentBasic(
        appointmentId: 'APT4',
        appointmentDate: '2026-08-01',
        appointmentTime: '10:00 AM',
        status: 'Completed',
        symptoms: 'Fever, body ache and "chills"',
      ),
    ]);

    expect(csv, contains('"Fever, body ache and ""chills"""'));
  });
}
