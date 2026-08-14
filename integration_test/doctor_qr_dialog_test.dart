/// On-device end-to-end check: boot the REAL DrsListing app, log in as a
/// doctor, and visually verify the Book QR dialog renders a scannable QR.
///
/// Run with:
///   flutter drive \
///     --driver=test_driver/doctor_qr_driver.dart \
///     --target=integration_test/doctor_qr_dialog_test.dart \
///     -d `<device>`
///
/// The app must have been freshly installed (no stale session) so the
/// splash routes to onboarding → login (the test also tolerates booting
/// straight to login). The QA doctor account (8989898989, "Vippl") owns
/// two clinics in the live users/doctors tables — an EXISTING user logs
/// in with just the mobile number (no OTP; OTP verification is
/// server-side and only applies to registration/doctor connection).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/main.dart' as app;

/// Pump until [finder] matches, with a hard timeout. `pumpAndSettle` is
/// unusable here: the splash screen runs a repeating 5s pulse animation,
/// so we advance time explicitly.
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

/// Pump until ANY of the [finders] matches; returns the matching finder's
/// [key]. (Can't return the Finder and compare with `==` — finders don't
/// override equality, so identity comparison would always fail.)
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

  testWidgets('DOCTOR: Book QR dialog renders the scannable booking QR',
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

    // ── Wait for the doctor dashboard (bottom-nav "Profile" tab).
    await pumpUntilFound(
      tester,
      find.text('Profile'),
      timeout: const Duration(seconds: 60),
    );
    await tester.pump(const Duration(seconds: 3)); // let doctor profile load

    // ── Open the Profile tab.
    await tester.tap(find.text('Profile'));

    // ── Wait for the doctor profile's Book action (needs currentDoctor).
    //    The action row sits at the bottom of the scrollable profile, so
    //    scroll it into view first.
    await pumpUntilFound(tester, find.text('Book'));
    await tester.scrollUntilVisible(
      find.text('Book'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Book'));

    // ── The QR dialog: title + QrImageView + the booking URL text the
    //    dialog renders under the QR (the same string the QR encodes).
    await pumpUntilFound(tester, find.text('Scan to Book'));
    expect(find.byType(QrImageView), findsOneWidget,
        reason: 'QR image must render in the dialog');

    // The visible tappable URL under the QR is built from the exact
    // payload `AppConstants.bookingPageUrl(placeId, doctorName: name)`
    // that QrImageView encodes. Assert its structure generically — the
    // QA doctor owns multiple clinics, so the exact placeId is dynamic —
    // but it must be the GitHub Pages booking URL for one of them.
    final visibleUrl = find.textContaining(AppConstants.bookingHost);
    expect(visibleUrl, findsOneWidget,
        reason: 'dialog must show the booking URL under the QR');
    final urlText = tester.widget<Text>(visibleUrl).data!;
    // booking.html is a REAL file on GitHub Pages (HTTP 200 for crawlers);
    // the placeId rides in the ?doctor= query param, which the booking
    // page parses (the pretty /book/<placeId> path was removed because
    // Pages serves it through 404.html with an HTTP 404 status).
    expect(urlText, contains('booking.html?doctor='));
    expect(urlText, contains('token=${AppConstants.bookingSharedSecret}'));
    expect(urlText, contains('name='));
    debugPrint('QR dialog booking URL: $urlText');

    // Visual proof: keep the dialog open and signal the harness to grab a
    // real screencap via adb (the in-test Flutter screenshot API needs a
    // hardware buffer this device's GPU rejects). Pumps for the watcher to
    // capture, then finishes the test cleanly.
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('DOCTOR_QR_DIALOG_VISIBLE');
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}
