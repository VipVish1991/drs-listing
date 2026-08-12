import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/widgets/appointment_search.dart';

import '../helpers/test_data.dart';

void main() {
  final appointments = <AppointmentModel>[
    appointmentBasic(
      appointmentId: 'APT_1',
      doctorName: 'Dr. Alice Green',
      patientName: 'Bob Smith',
      callNumber: '9876543210',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
      symptoms: 'fever and cough',
    ),
    appointmentBasic(
      appointmentId: 'APT_2',
      doctorName: 'Dr. Carol White',
      patientName: 'Dana Brown',
      callNumber: '9123456789',
      appointmentDate: '2026-08-02',
      appointmentTime: '10:00 AM',
      status: 'Completed',
      symptoms: 'headache',
    ),
    appointmentBasic(
      appointmentId: 'APT_3',
      doctorName: 'Dr. Eve Black',
      patientName: 'Frank Ocean',
      callNumber: null,
      appointmentDate: '2026-08-03',
      appointmentTime: '11:00 AM',
      status: AppointmentStatus.pending,
      symptoms: null,
    ),
  ];

  List<String> ids(String query) => filterAppointmentsForSearch(
    appointments,
    query,
  ).map((a) => a.appointmentId).toList();

  test('empty query returns the whole list unchanged', () {
    expect(ids(''), ['APT_1', 'APT_2', 'APT_3']);
    expect(ids('   '), ['APT_1', 'APT_2', 'APT_3']);
  });

  test('matches the doctor name', () {
    expect(ids('alice'), ['APT_1']);
    expect(ids('Dr. Carol'), ['APT_2']);
  });

  test('matches the patient name', () {
    expect(ids('Dana'), ['APT_2']);
    expect(ids('frank'), ['APT_3']);
  });

  test('matches the phone number', () {
    expect(ids('9876543210'), ['APT_1']);
    expect(ids('9123456789'), ['APT_2']);
  });

  test('matches the status', () {
    expect(ids('Completed'), ['APT_2']);
    expect(ids('pending'), ['APT_3']);
  });

  test('matches the date and time', () {
    expect(ids('2026-08-02'), ['APT_2']);
    expect(ids('9:00'), ['APT_1']);
  });

  test('matches symptoms and appointment id', () {
    expect(ids('headache'), ['APT_2']);
    expect(ids('apt_3'), ['APT_3']);
  });

  test('search is case-insensitive and trims surrounding whitespace', () {
    expect(ids('  ALICE  '), ['APT_1']);
  });

  test('no match returns an empty list', () {
    expect(ids('zzz-no-such-doctor'), isEmpty);
  });

  test('does not mutate the input list', () {
    final before = appointments.length;
    filterAppointmentsForSearch(appointments, 'alice');
    expect(appointments.length, before);
  });
}
