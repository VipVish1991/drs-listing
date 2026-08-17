/// ON-DEVICE regression test: cancelling the UPI app picker dialog leaves
/// the app alive.
///
/// Guards the crash fixed in QuantupiPlugin.java: tapping the picker's
/// **Cancel** button resolved the pending MethodChannel result, then the
/// dialog's `onDismiss` fired and resolved the SAME result a second time
/// — a `MethodChannel.Result` throws "Reply already submitted" on the
/// second submit, which killed the app (the user saw the app exit right
/// after tapping Cancel). The fix take-and-clears the pending result
/// before resolving, so whichever dismissal path fires first wins and
/// every later path becomes a no-op.
///
/// This test drives the REAL native chain on real hardware:
///
///   1. [QuantupiPaymentService.pay] fires a real `upi://pay` intent.
///      With ≥2 UPI apps installed, the plugin's custom **"Pay with"**
///      picker dialog appears (it lists EVERY installed UPI app
///      vertically — the system chooser is a paged carousel that hides
///      apps behind swipes, which made users think the list was
///      incomplete).
///   2. **You tap CANCEL on that dialog** — the exact action that crashed
///      the app before the fix. (The dialog is native Android UI, so the
///      test cannot tap it; the future below resolves the moment it
///      dismisses.)
///   3. The plugin must resolve the Dart future with 'user_canceled'
///      (normalized to 'failed') — a stuck plugin or a cancel-crash
///      fails the test — and the app must STAY ALIVE: the test re-pumps
///      an interactive widget and taps it to prove the engine + native
///      side still respond.
///
/// Prerequisites: an Android device with **≥2 installed UPI apps**
/// (otherwise the picker dialog never appears and the intent path
/// differs). The ₹1 payment goes to a placeholder VPA — nothing is ever
/// sent, the payment is cancelled at the picker.
///
/// Run with the phone connected (USB debugging on):
///   flutter test integration_test/upi_picker_cancel_test.dart -d `<device>`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:DrsListing/services/quantupi_payment_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ON-DEVICE: cancelling the UPI picker resolves and the app '
      'stays alive', (tester) async {
    final service = QuantupiPaymentService.instance;

    // The service must see this as a supported platform (Android only).
    expect(service.isSupported, isTrue,
        reason: 'the real device must report Android as supported');

    // Pump a minimal surface so the plugin's ActivityAware attach is
    // complete before firing the intent.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: Text('UPI')))),
    );
    await tester.pump();

    // Unique reference per run so the UPI app never rejects a duplicate.
    final ref = 'CNL${DateTime.now().millisecondsSinceEpoch % 100000000}';

    debugPrint('>> Firing REAL upi://pay intent: ₹1 to a placeholder VPA');
    debugPrint('>> The "Pay with" PICKER dialog lists every installed '
        'UPI app.');
    debugPrint('>> TAP CANCEL on that dialog now (do NOT complete the '
        'payment)…');

    // The picker dialog is native Android UI — the test cannot tap it, so
    // the human taps Cancel; the future resolves the moment the dialog
    // dismisses. A stuck plugin (or a crash on cancel — the bug this test
    // guards) fails the timeout below.
    final result = await service.pay(
      receiverUpiId: 'test@upi',
      receiverName: 'DrsListing Test',
      amount: 1,
      transactionRef: ref,
      note: 'UPI picker cancel test',
    ).timeout(const Duration(minutes: 2));

    debugPrint('>> RESULT after cancel: outcome=${result.outcome} '
        'raw=${result.rawResponse}');

    // Cancelling the picker must surface as a failed outcome — the raw
    // 'user_canceled' string normalizes to 'failed'. Any other outcome
    // means the human completed (or the UPI app returned) something else.
    expect(result.outcome, 'failed',
        reason: 'cancelling the picker must resolve as failed — tap CANCEL '
            'on the picker dialog, not a UPI app');

    // ── THE regression assertion: the app must still be alive ──
    // Before the fix, the Cancel tap resolved the MethodChannel result and
    // then onDismiss resolved it AGAIN, which throws "Reply already
    // submitted" and kills the app. Re-pump a fully interactive widget and
    // tap it: a dead process can neither render it nor handle the tap.
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('still alive'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('still alive'));
    await tester.pump();
    expect(taps, 1,
        reason: 'the app must remain interactive after cancelling the UPI '
            'picker — a crash here means the double-resolve bug is back');

    // The engine can also tear down cleanly.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
