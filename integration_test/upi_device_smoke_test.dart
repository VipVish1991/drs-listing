/// ON-DEVICE smoke test for the UPI payment chain (vendored quantupi
/// plugin → `upi://pay` intent → installed UPI app → response parsing).
///
/// Unlike the widget/unit tests (which fake the plugin), this test drives
/// the REAL plugin path on real hardware:
///
///   1. [QuantupiPaymentService.pay] fires the `upi://pay` intent with a
///      ₹1 test payment to [kTestVpa] — Android's system chooser opens
///      (PhonePe / Paytm / GPay …).
///   2. You complete OR cancel the payment in the UPI app on the phone.
///   3. The UPI app returns its response string via the plugin's
///      `onActivityResult` → method channel; the service normalizes it.
///
/// The test then prints the RAW response the UPI app returned + the parsed
/// outcome. A `success` proves the full loop works; a cancel/failure still
/// proves the intent fired and the response channel came back (the exact
/// failure mode of a broken plugin is a hang or exception — which fails
/// the test).
///
/// NOTE: ₹1 to [kTestVpa] will fail at the bank level if the VPA isn't
/// real — that's fine for a chain check. For a true money-movement test,
/// edit [kTestVpa] to a real receiving VPA.
///
/// Run with the phone connected (USB debugging on):
///   flutter test integration_test/upi_device_smoke_test.dart -d `device`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:DrsListing/services/quantupi_payment_service.dart';

/// Receiving VPA for the test payment — a real test VPA so the UPI app
/// can actually process (and complete) the ₹1 payment, verifying the
/// full success path on-device.
const String kTestVpa = '9691148159@yescred';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ON-DEVICE: real UPI intent fires and a response comes back',
      (tester) async {
    final service = QuantupiPaymentService.instance;

    // The service must see this as a supported platform (Android only).
    expect(service.isSupported, isTrue,
        reason: 'the real device must report Android as supported');

    // Pump a minimal surface so the plugin's ActivityAware attach is
    // complete before firing the intent.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: Text('UPI')) )),
    );
    await tester.pump();

    // Unique reference per run so the UPI app never rejects a duplicate.
    final ref =
        'SMK${DateTime.now().millisecondsSinceEpoch % 100000000}';

    debugPrint('>> Firing REAL upi://pay intent: ₹1 to $kTestVpa');
    debugPrint('>> Complete or CANCEL the payment in the UPI app on the '
        'phone (it may take ~30s to come back)…');

    // The UPI app is in the foreground now — the future resolves when it
    // returns via onActivityResult.
    final result = await service.pay(
      receiverUpiId: kTestVpa,
      receiverName: 'DrsListing Test',
      amount: 1,
      transactionRef: ref,
      note: 'UPI chain smoke test',
    ).timeout(const Duration(seconds: 90));

    // The chain is only "working" if the UPI app actually returned a
    // response (any known outcome). A stuck plugin would time out above
    // and fail the test.
    debugPrint('>> RAW RESPONSE from UPI app: ${result.rawResponse}');
    debugPrint('>> PARSED OUTCOME: ${result.outcome}'
        '${result.transactionId == null ? '' : ' · txn ${result.transactionId}'}'
        '${result.approvalRefNo == null ? '' : ' · ref ${result.approvalRefNo}'}');

    expect(result.rawResponse, isNotNull);
    expect(
      ['success', 'submitted', 'failed'].contains(result.outcome),
      isTrue,
      reason: 'a real response must normalize to one of the known outcomes',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
