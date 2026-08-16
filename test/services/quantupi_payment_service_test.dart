import 'package:flutter_test/flutter_test.dart';
import 'package:quantupi/quantupi.dart';

import 'package:DrsListing/services/quantupi_payment_service.dart';

void main() {
  tearDown(() {
    QuantupiPaymentService.transactionOverride = null;
    QuantupiPaymentService.forceAndroid = null;
  });

  group('parseResponse', () {
    test('maps a confirmed success response', () {
      final r = QuantupiPaymentService.parseResponse(
        'upi://pay?txnid=ABC123&responsecode=00&approvalrefno=REF456'
        '&status=success&txnref=APT111',
      );
      expect(r.isSuccess, isTrue);
      expect(r.outcome, 'success');
      expect(r.transactionId, 'ABC123');
      expect(r.approvalRefNo, 'REF456');
      expect(r.proceedWithBooking, isTrue);
    });

    test('handles URL-encoded values (spaces/plusses)', () {
      final r = QuantupiPaymentService.parseResponse(
        'txnid=ABC&status=success&approvalrefno=my%20ref',
      );
      expect(r.isSuccess, isTrue);
      expect(r.approvalRefNo, 'my ref');
    });

    test('maps submitted (initiated but unconfirmed) — never books', () {
      final r = QuantupiPaymentService.parseResponse(
        'txnid=ABC&status=submitted',
      );
      expect(r.isSubmitted, isTrue);
      expect(r.proceedWithBooking, isFalse);
    });

    test('maps failure statuses to failed', () {
      for (final raw in [
        'txnid=ABC&status=failure',
        'txnid=ABC&status=FAILED',
        'upi://pay?txnid=ABC&responsecode=01&status=failure',
      ]) {
        final r = QuantupiPaymentService.parseResponse(raw);
        expect(r.isFailed, isTrue, reason: raw);
        expect(r.proceedWithBooking, isFalse);
      }
    });

    test('treats error markers and unknown responses as failed', () {
      for (final raw in [
        'user_canceled',
        'null_response',
        'app_not_installed',
        'invalid_parameters',
        'some gibberish',
        'status=weird',
        '',
      ]) {
        final r = QuantupiPaymentService.parseResponse(raw);
        expect(r.isFailed, isTrue, reason: raw);
        expect(r.proceedWithBooking, isFalse);
      }
    });

    test('extracts txnid from a response with a leading scheme', () {
      final r = QuantupiPaymentService.parseResponse(
        'upi://pay?txnid=PAY123&status=success',
      );
      expect(r.isSuccess, isTrue);
      expect(r.transactionId, 'PAY123');
    });

    test('matches keys case-insensitively (on-device: Status=FAILURE&)', () {
      // Real UPI apps return the response with a capitalised key and a
      // trailing ampersand — the exact shape captured on-device.
      final r = QuantupiPaymentService.parseResponse('Status=FAILURE&');
      expect(r.isFailed, isTrue);
      expect(r.proceedWithBooking, isFalse);
    });

    test('a capitalised Status=SUCCESS must still count as success', () {
      // Regression: before the case-insensitive key match, this response
      // (the success twin of the on-device `Status=FAILURE&` format) was
      // misread as failed — a real paid booking would never have booked.
      final r = QuantupiPaymentService.parseResponse(
        'Status=SUCCESS&Txnid=TXN901&Approvalrefno=APP42&',
      );
      expect(r.isSuccess, isTrue);
      expect(r.proceedWithBooking, isTrue);
      expect(r.transactionId, 'TXN901');
      expect(r.approvalRefNo, 'APP42');
    });

    test('parses the exact on-device response (bare ?, txnId empty)', () {
      // The real app returned this on-device (Cred/PhonePe response extra):
      // no scheme, a leading `?`, a capitalised Status and an empty txnId.
      final r = QuantupiPaymentService.parseResponse(
        '?txnId=&responseCode=null&Status=SUCCESS&txnRef=SMK82990473'
        '&AppID=com.dreamplug.androidapp',
      );
      expect(r.isSuccess, isTrue);
      expect(r.proceedWithBooking, isTrue);
      expect(r.transactionId, isNull); // empty txnId → no bogus value
      // Every tracking field is captured: response code (the literal
      // 'null' the app sent is kept for debugging), echoed txn ref, and
      // which UPI app processed the payment.
      expect(r.responseCode, 'null');
      expect(r.txnRef, 'SMK82990473');
      expect(r.appId, 'com.dreamplug.androidapp');
    });

    test('extracts all tracking fields from a full response', () {
      final r = QuantupiPaymentService.parseResponse(
        'upi://pay?txnid=TXN901&responsecode=00&status=success'
        '&approvalrefno=APP42&txnref=APT123&appid=com.phonepe.app',
      );
      expect(r.isSuccess, isTrue);
      expect(r.transactionId, 'TXN901');
      expect(r.approvalRefNo, 'APP42');
      expect(r.responseCode, '00');
      expect(r.txnRef, 'APT123');
      expect(r.appId, 'com.phonepe.app');
    });
  });

  group('pay', () {
    test('refuses a blank receiver VPA without invoking the plugin', () async {
      var invoked = false;
      QuantupiPaymentService.transactionOverride = (upi) async {
        invoked = true;
        return 'status=success';
      };
      QuantupiPaymentService.forceAndroid = true;

      final r = await QuantupiPaymentService.instance.pay(
        receiverUpiId: '   ',
        receiverName: 'Dr. Test',
        amount: 800,
        transactionRef: 'APT1',
        note: 'fee',
      );
      expect(invoked, isFalse);
      expect(r.isFailed, isTrue);
    });

    test('returns failed on unsupported platforms without invoking', () async {
      var invoked = false;
      QuantupiPaymentService.transactionOverride = (upi) async {
        invoked = true;
        return 'status=success';
      };
      QuantupiPaymentService.forceAndroid = false;

      final r = await QuantupiPaymentService.instance.pay(
        receiverUpiId: 'clinic@okhdfcbank',
        receiverName: 'Dr. Test',
        amount: 800,
        transactionRef: 'APT1',
        note: 'fee',
      );
      expect(invoked, isFalse);
      expect(r.isFailed, isTrue);
      expect(r.rawResponse, 'unsupported_platform');
    });

    test('passes the payment details to the plugin and maps a success', () async {
      QuantupiPaymentService.forceAndroid = true;
      Quantupi? seen;
      QuantupiPaymentService.transactionOverride = (upi) async {
        seen = upi;
        return 'upi://pay?txnid=TX1&status=success&approvalrefno=AR1';
      };

      final r = await QuantupiPaymentService.instance.pay(
        receiverUpiId: 'clinic@okhdfcbank',
        receiverName: 'Dr. Test',
        amount: 800,
        transactionRef: 'APT12345',
        note: 'Video Consultation fee — Dr. Test',
      );

      expect(seen, isNotNull);
      expect(seen!.receiverUpiId, 'clinic@okhdfcbank');
      expect(seen!.receiverName, 'Dr. Test');
      expect(seen!.amount, 800);
      expect(seen!.transactionRefId, 'APT12345');
      expect(r.isSuccess, isTrue);
      expect(r.transactionId, 'TX1');
      expect(r.approvalRefNo, 'AR1');
    });

    test('maps a submitted plugin response to submitted', () async {
      QuantupiPaymentService.forceAndroid = true;
      QuantupiPaymentService.transactionOverride =
          (upi) async => 'status=submitted';

      final r = await QuantupiPaymentService.instance.pay(
        receiverUpiId: 'clinic@okhdfcbank',
        receiverName: 'Dr. Test',
        amount: 800,
        transactionRef: 'APT1',
        note: 'fee',
      );
      expect(r.isSubmitted, isTrue);
      expect(r.proceedWithBooking, isFalse);
    });

    test('maps a plugin exception to failed, never throwing', () async {
      QuantupiPaymentService.forceAndroid = true;
      QuantupiPaymentService.transactionOverride =
          (upi) async => throw Exception('plugin exploded');

      final r = await QuantupiPaymentService.instance.pay(
        receiverUpiId: 'clinic@okhdfcbank',
        receiverName: 'Dr. Test',
        amount: 800,
        transactionRef: 'APT1',
        note: 'fee',
      );
      expect(r.isFailed, isTrue);
    });
  });
}
