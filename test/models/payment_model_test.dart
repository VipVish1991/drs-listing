import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/models/payment_model.dart';

void main() {
  group('PaymentModel', () {
    test('fromJson/toJson round-trips all payment fields', () {
      final payment = PaymentModel(
        id: 'pay_1',
        appointmentId: 'APT123456',
        patientId: 'user_1',
        doctorPlaceId: 'place_9',
        doctorName: 'Dr. Sharma',
        consultationType: 'video',
        paymentType: 'consultation',
        paymentStatus: 'Paid',
        paymentMethod: 'online',
        amount: 800,
        currency: 'INR',
        transactionId: 'TXN123456',
        upiId: 'drslisting@upi',
        approvalRefNo: 'REF42',
        responseCode: '00',
        txnRef: 'APT123',
        upiAppId: 'com.phonepe.app',
        rawResponse: '?txnId=TXN123456&Status=SUCCESS&txnRef=APT123',
        paidAt: DateTime.utc(2026, 8, 9, 10, 30),
      );

      final json = payment.toJson();
      expect(json['appointment_id'], 'APT123456');
      expect(json['patient_id'], 'user_1');
      expect(json['doctor_place_id'], 'place_9');
      expect(json['doctor_name'], 'Dr. Sharma');
      expect(json['consultation_type'], 'video');
      expect(json['payment_type'], 'consultation');
      expect(json['payment_status'], 'Paid');
      expect(json['payment_method'], 'online');
      expect(json['amount'], 800);
      expect(json['currency'], 'INR');
      expect(json['transaction_id'], 'TXN123456');
      expect(json['upi_id'], 'drslisting@upi');
      expect(json['approval_ref_no'], 'REF42');
      expect(json['response_code'], '00');
      expect(json['txn_ref'], 'APT123');
      expect(json['upi_app_id'], 'com.phonepe.app');
      expect(json['raw_response'], '?txnId=TXN123456&Status=SUCCESS&txnRef=APT123');
      expect(json['paid_at'], isNotNull);
      // id / created_at are DB-generated — never sent.
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('created_at'), isFalse);

      final restored = PaymentModel.fromJson(json);
      expect(restored.appointmentId, 'APT123456');
      expect(restored.patientId, 'user_1');
      expect(restored.doctorPlaceId, 'place_9');
      expect(restored.doctorName, 'Dr. Sharma');
      expect(restored.consultationType, 'video');
      expect(restored.paymentStatus, 'Paid');
      expect(restored.paymentMethod, 'online');
      expect(restored.amount, 800);
      expect(restored.transactionId, 'TXN123456');
      expect(restored.upiId, 'drslisting@upi');
      expect(restored.approvalRefNo, 'REF42');
      expect(restored.responseCode, '00');
      expect(restored.txnRef, 'APT123');
      expect(restored.upiAppId, 'com.phonepe.app');
      expect(restored.rawResponse, '?txnId=TXN123456&Status=SUCCESS&txnRef=APT123');
      expect(restored.isPaid, isTrue);
    });

    test('fromJson parses patient_name from the embedded appointments join', () {
      // Doctor-side reads (getPaymentsForDoctor) embed the appointment.
      // Many-to-one embeds come back as a SINGLE object (verified against
      // the live project): `appointments: { patient_name }`.
      final payment = PaymentModel.fromJson({
        'id': 'pay_1',
        'appointment_id': 'APT123456',
        'patient_id': 'user_1',
        'payment_status': 'Paid',
        'payment_method': 'offline',
        'amount': 800,
        'appointments': {'patient_name': 'Rahul Sharma'},
      });
      expect(payment.patientName, 'Rahul Sharma');
      // The one-to-many list form is handled defensively too.
      final listForm = PaymentModel.fromJson({
        'appointment_id': 'APT2',
        'patient_id': 'user_1',
        'appointments': [
          {'patient_name': 'Priya Patel'},
        ],
      });
      expect(listForm.patientName, 'Priya Patel');
      // Patient-side reads (no join) leave it null — never a crash.
      final plain = PaymentModel.fromJson({'appointment_id': 'APT1'});
      expect(plain.patientName, isNull);
    });

    test('toJson never sends the join-only patientName', () {
      final payment = PaymentModel.fromJson({
        'appointment_id': 'APT123456',
        'patient_id': 'user_1',
        'appointments': [
          {'patient_name': 'Rahul Sharma'},
        ],
      });
      expect(payment.patientName, 'Rahul Sharma');
      expect(payment.toJson().containsKey('patientName'), isFalse);
      expect(payment.toJson().containsKey('patient_name'), isFalse);
    });

    test('null JSON fields default to safe values', () {
      final payment = PaymentModel.fromJson({
        'appointment_id': 'APT1',
        'patient_id': 'user_1',
      });

      expect(payment.paymentStatus, 'Pending');
      expect(payment.paymentMethod, 'offline');
      expect(payment.amount, 0);
      expect(payment.currency, 'INR');
      expect(payment.paymentType, 'consultation');
      expect(payment.isPaid, isFalse);
    });

    test('labels: online vs offline and amount formatting', () {
      const online = PaymentModel(
        appointmentId: 'a',
        patientId: 'u',
        paymentMethod: 'online',
        amount: 500,
      );
      const offline = PaymentModel(
        appointmentId: 'a',
        patientId: 'u',
        paymentMethod: 'offline',
        amount: 499.5,
      );

      expect(online.paymentMethodLabel, 'Online (UPI)');
      expect(offline.paymentMethodLabel, 'Offline (Clinic)');
      expect(online.amountLabel, '₹500');
      expect(offline.amountLabel, '₹499.50');
    });

    test('copyWith fills the appointment id (booking-time pattern)', () {
      const draft = PaymentModel(
        patientId: 'user_1',
        paymentMethod: 'online',
        paymentStatus: 'Paid',
        amount: 800,
      );

      final finalPayment = draft.copyWith(
        appointmentId: 'APT123456',
        paidAt: DateTime.utc(2026, 8, 9),
      );

      expect(finalPayment.appointmentId, 'APT123456');
      expect(finalPayment.paidAt, isNotNull);
      expect(finalPayment.patientId, 'user_1');
      expect(finalPayment.paymentStatus, 'Paid');
      // isPaid drives whether paid_at gets set by the controller.
      expect(finalPayment.isPaid, isTrue);
    });

    test('parses TIMESTAMPTZ strings into LOCAL time (UTC → local)', () {
      // PostgREST returns timestamptz columns as UTC ISO strings with a
      // Z/offset; the model must normalize to local so the card shows the
      // user's own time (a 10:30 IST payment must NOT display 05:00).
      final parsed = PaymentModel.fromJson({
        'paid_at': '2026-08-06T05:00:00Z',
        'created_at': '2026-08-06T05:00:00+00:00',
      });

      expect(parsed.paidAt, isNotNull);
      expect(parsed.paidAt!.isUtc, isFalse);
      expect(parsed.createdAt, isNotNull);
      expect(parsed.createdAt!.isUtc, isFalse);
      // The instant is preserved exactly (local conversion is a zone
      // change, never a time shift).
      expect(parsed.paidAt!.toUtc(), DateTime.utc(2026, 8, 6, 5, 0));
    });
  });
}
