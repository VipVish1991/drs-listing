import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/utils/payment_csv.dart';

/// Minimal, predictable payment row factory (mirrors the widget-test one).
PaymentModel _payment({
  String appointmentId = 'APT1',
  String? doctorName = 'Dr. Smith',
  String? patientName,
  String? consultationType = 'video',
  String paymentStatus = 'Paid',
  String paymentMethod = 'online',
  double amount = 800,
  String? transactionId = 'TXN1',
  String? upiId = 'clinic@upi',
  DateTime? paidAt,
}) {
  return PaymentModel(
    appointmentId: appointmentId,
    patientId: 'user_1',
    doctorName: doctorName,
    patientName: patientName,
    consultationType: consultationType,
    paymentStatus: paymentStatus,
    paymentMethod: paymentMethod,
    amount: amount,
    transactionId: transactionId,
    upiId: upiId,
    paidAt: paidAt ?? DateTime(2026, 8, 6, 10, 30),
  );
}

void main() {
  test('builds a header plus one row per payment', () {
    final csv = buildPaymentsCsv(
      [_payment()],
      nameFor: (p) => p.doctorName!,
      nameColumn: 'Doctor Name',
    );

    final lines = csv.split('\r\n');
    expect(
      lines.first,
      'Date,Doctor Name,Consultation,Method,Status,Amount (INR),'
      'Transaction ID,UPI ID,Appointment ID',
    );
    expect(
      lines[1],
      '06-08-2026,Dr. Smith,Video Consultation,Online (UPI),Paid,'
      '800,TXN1,clinic@upi,APT1',
    );
  });

  test('nameFor resolves the counterparty column (doctor mode → patient)', () {
    final csv = buildPaymentsCsv(
      [_payment(doctorName: 'Dr. Clinic', patientName: 'Rahul Sharma')],
      nameFor: (p) => p.patientName ?? 'Patient',
      nameColumn: 'Patient Name',
    );

    expect(csv, contains('Rahul Sharma'));
    expect(csv, isNot(contains('Dr. Clinic')));
  });

  test('the header column is role-labeled per side', () {
    // Patient export: the counterparty is the doctor who was paid.
    final patientCsv = buildPaymentsCsv(
      [_payment()],
      nameFor: (p) => p.doctorName!,
      nameColumn: 'Doctor Name',
    );
    expect(patientCsv, startsWith('Date,Doctor Name,Consultation'));

    // Doctor/clinic export: the counterparty is the patient who paid.
    final doctorCsv = buildPaymentsCsv(
      [_payment(patientName: 'Rahul Sharma')],
      nameFor: (p) => p.patientName ?? 'Patient',
      nameColumn: 'Patient Name',
    );
    expect(doctorCsv, startsWith('Date,Patient Name,Consultation'));
  });

  test('empty list yields only the header', () {
    final csv = buildPaymentsCsv(
      const [],
      nameFor: (p) => '',
      nameColumn: 'Doctor Name',
    );

    expect(csv.split('\r\n'), hasLength(1));
    expect(csv, contains('Date,Doctor Name'));
  });

  test('RFC 4180: quotes fields containing commas or quotes', () {
    final csv = buildPaymentsCsv(
      [_payment(doctorName: 'Dr. Smith, Jr.', transactionId: 'TX"12')],
      nameFor: (p) => p.doctorName!,
      nameColumn: 'Doctor Name',
    );

    expect(csv, contains('"Dr. Smith, Jr."'));
    expect(csv, contains('"TX""12"'));
  });

  test('amounts stay numeric so spreadsheets treat them as numbers', () {
    final csv = buildPaymentsCsv(
      [_payment(amount: 800.5)],
      nameFor: (p) => p.doctorName!,
      nameColumn: 'Doctor Name',
    );

    expect(csv, contains(',800.50,'));
  });

  test('missing optional fields render as empty cells', () {
    final csv = buildPaymentsCsv(
      [
        PaymentModel(
          appointmentId: '',
          patientId: 'user_1',
          paymentMethod: 'offline',
          paymentStatus: 'Pending',
        ),
      ],
      nameFor: (p) => 'Patient',
      nameColumn: 'Patient Name',
    );

    final row = csv.split('\r\n')[1];
    // Date + consultation are empty; name, method, status, amount follow.
    expect(row, ',Patient,,Offline (Clinic),Pending,0,,,');
  });
}
