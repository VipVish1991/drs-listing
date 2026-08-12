/// On-device end-to-end check for the clinic's payment-settlement flow:
/// after the web booking (patient RealDeviceTest, ₹1000 offline Pending),
/// log into the REAL app as the doctor, open the Appointments tab, tap the
/// card's Mark Paid action, confirm the dialog, and verify the payment
/// flips to Paid (chip updates, actions disappear).
///
/// Run with:
///   flutter drive \
///     --driver=test_driver/doctor_qr_driver.dart \
///     --target=integration_test/doctor_mark_paid_test.dart \
///     -d `<device>`
///
/// Searches the appointments list by the unique patient name so it works
/// regardless of the booked slot's day (search spans every date).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import 'package:DrsListing/controllers/doctor_controller.dart';
import 'package:DrsListing/main.dart' as app;

/// Pump until [finder] matches, with a hard timeout. `pumpAndSettle` is
/// unusable here: the splash screen runs a repeating 5s pulse animation.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for ${finder.description}');
}

Future<String> pumpUntilAnyFound(
  WidgetTester tester,
  Map<String, Finder> finders, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 300));
    for (final entry in finders.entries) {
      if (entry.value.evaluate().isNotEmpty) return entry.key;
    }
  }
  fail('Timed out waiting for any of: '
      '${finders.keys.join(' | ')}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DOCTOR: Mark Paid settles the offline web-booking fee',
      (tester) async {
    // ── Boot the real app (splash → onboarding, or straight to login).
    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── Onboarding (fresh install) OR login directly — handle both.
    final landing = await pumpUntilAnyFound(
      tester,
      {
        'onboarding': find.text('Skip'),
        'login': find.text('Welcome Back!'),
      },
    );
    if (landing == 'onboarding') {
      await tester.tap(find.text('Skip'));
      await pumpUntilFound(tester, find.text('Welcome Back!'));
    }

    // ── Login as the QA doctor (existing user → no OTP).
    await tester.enterText(find.byType(TextField).first, '8989898989');
    await tester.pump(const Duration(milliseconds: 500));
    final continueBtn = find.text('Continue');
    await tester.ensureVisible(continueBtn);
    await tester.tap(continueBtn);

    // ── Wait for the doctor shell, then open the Appointments tab.
    await pumpUntilFound(
      tester,
      find.text('Appointments'),
      timeout: const Duration(seconds: 60),
    );
    await tester.pump(const Duration(seconds: 3)); // let data load
    await tester.tap(find.text('Appointments'));
    await pumpUntilFound(
      tester,
      find.text('My Appointments'),
      timeout: const Duration(seconds: 30),
    );

    // ── Search spans every date — find the web-booked patient's card.
    await tester.tap(find.byKey(const ValueKey('appointments_search_toggle')));
    await pumpUntilFound(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField).last, 'RealDeviceTest');
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntilFound(tester, find.text('RealDeviceTest'));

    // The offline Pending payment must be actionable for the clinic.
    await pumpUntilFound(tester, find.text('Mark Paid'));
    expect(find.text('Mark Paid'), findsWidgets,
        reason: 'offline Pending payment must offer Mark Paid');

    // ── Tap Mark Paid on the card → the confirm dialog opens. The card's
    //    action is a custom _ModernActionBtn; the dialog confirm is the
    //    ElevatedButton also labelled 'Mark Paid', so target it uniquely.
    await tester.tap(find.text('Mark Paid').first);
    await pumpUntilFound(tester, find.text('Mark Payment Paid'));

    // ── Confirm in the dialog.
    final confirmBtn = find.widgetWithText(ElevatedButton, 'Mark Paid');
    expect(confirmBtn, findsOneWidget,
        reason: 'dialog must show the confirm button');
    await tester.tap(confirmBtn);

    // ── Success snackbar.
    await pumpUntilFound(tester, find.text('Payment marked as Paid'));

    // ── Poll the CONTROLLER's payment map (the source of truth the card
    //    renders from) until the flip is reflected there — this separates
    //    "the reload failed" from "the UI didn't rebuild".
    final doctorCtrl = Get.find<DoctorController>();
    final aptId = 'APT1786536523191';
    final endMap = DateTime.now().add(const Duration(seconds: 15));
    String? mapStatus;
    while (DateTime.now().isBefore(endMap)) {
      await tester.pump(const Duration(milliseconds: 400));
      mapStatus =
          doctorCtrl.paymentsByAppointment[aptId]?.paymentStatus;
      if (mapStatus == 'Paid') break;
    }
    debugPrint('MARK_PAID controller map status after flip: '
        '$mapStatus (expected Paid)');

    // ── The payment chip on the card must now read Paid, and the settle
    //    actions must be gone (payment no longer Pending/actionable).
    await pumpUntilFound(
      tester,
      find.text('Paid'),
      timeout: const Duration(seconds: 15),
    );
    expect(find.text('Paid'), findsWidgets,
        reason: 'payment status chip must flip to Paid');
    expect(find.text('Mark Paid'), findsNothing,
        reason: 'Mark Paid action must disappear once settled');

    debugPrint('DOCTOR_MARK_PAID_VISIBLE');

    // Visual proof: keep the screen up while the harness grabs a real
    // screencap via adb, then finish cleanly.
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}
