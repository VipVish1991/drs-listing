/// On-device end-to-end check for the FULL booking loop: after an
/// appointment is created through the web booking page (filled in Chrome
/// on this device), log into the REAL app as the doctor and confirm the
/// booking shows up in the doctor dashboard's Appointments tab.
///
/// Run with:
///   flutter drive \
///     --driver=test_driver/doctor_qr_driver.dart \
///     --target=integration_test/doctor_dashboard_booking_check_test.dart \
///     -d `<device>`
///
/// The test searches the appointments list by the unique patient name the
/// web booking used, so it works regardless of the day the slot was
/// booked for (search spans every date — the list's default view filters
/// to today).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

  testWidgets(
      'DOCTOR: web-booked appointment appears in the doctor dashboard',
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

    // ── Wait for the doctor shell (bottom-nav labels appear).
    await pumpUntilFound(
      tester,
      find.text('Appointments'),
      timeout: const Duration(seconds: 60),
    );
    await tester.pump(const Duration(seconds: 3)); // let data load

    // ── Open the Appointments tab (full list, date-filtered by default).
    await tester.tap(find.text('Appointments'));
    await pumpUntilFound(
      tester,
      find.text('My Appointments'),
      timeout: const Duration(seconds: 30),
    );

    // ── Switch on search so the list spans EVERY date (the default view
    //    filters to today, and the web booking was for a chosen slot day).
    await tester.tap(find.byKey(const ValueKey('appointments_search_toggle')));
    await pumpUntilFound(tester, find.byType(TextField));

    // ── Search by the exact patient name the web booking used.
    await tester.enterText(find.byType(TextField).last, 'RealDeviceTest');
    await tester.pump(const Duration(milliseconds: 400));

    // ── The card for the web booking must appear.
    await pumpUntilFound(tester, find.text('RealDeviceTest'));
    expect(find.text('RealDeviceTest'), findsWidgets,
        reason: 'the web-booked patient must appear in the doctor list');

    // Pending status chip on the card (the web booking lands as Pending
    // awaiting clinic confirmation).
    expect(find.text('Pending'), findsWidgets,
        reason: 'the booking must still be Pending');

    // The offline consultation fee recorded for the slot (₹1000) renders
    // as a payment row on the card — proving the payment chain too.
    expect(find.textContaining('₹1000'), findsWidgets,
        reason: 'the ₹1000 offline fee row must render on the card');

    // An offline Pending payment gets the clinic's Mark Paid action.
    expect(find.text('Mark Paid'), findsWidgets,
        reason: 'clinic must be able to settle the offline fee');

    debugPrint('DOCTOR_DASHBOARD_BOOKING_VISIBLE');

    // Visual proof: keep the screen up while the harness grabs a real
    // screencap via adb, then finish cleanly.
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}
