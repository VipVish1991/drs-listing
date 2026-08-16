/// ON-DEVICE smoke test for the Google Meet consultation flow (vendored
/// google_meet_sdk → Google Sign-In → calendar event → link opens).
///
/// Unlike the widget/unit tests (which fake the Google APIs), this test
/// drives the REAL chain on real hardware:
///
///   1. [MeetConsultService.joinConsultation] runs the full flow — exactly
///      what the details sheet's **Join Video Call** button does.
///   2. Google Sign-In opens the account chooser on the phone — **you must
///      pick the Google account and approve the Calendar scopes** (the app
///      requests `calendar` + `calendar.events`).
///   3. A Meet-backed calendar event is created on that account's primary
///      calendar; the returned `meet.google.com/<id>` link opens in the
///      browser / Meet app.
///   4. The test asserts the flow succeeded (a `meet.google.com/` link came
///      back) — the link is exactly what the sheet persists via
///      `onSaveMeetLink` so BOTH sides join the same room.
///
/// The service future is awaited DIRECTLY (like the UPI smoke test) rather
/// than pumped — the native account picker + Meet app leave the Flutter
/// frame, so widget pumping can't wait for them.
///
/// Prerequisites (outside the repo): Google Calendar API enabled in GCP,
/// Firebase Auth with the Google provider on, and the app's SHA-1
/// registered on the Firebase Android app. A broken config fails at the
/// GoogleSignIn layer (clientConfigurationError), surfaced via the vendored
/// SDK's snackbar + this test's failure.
///
/// Run with the phone connected (USB debugging on):
///   flutter test integration_test/meet_consultation_smoke_test.dart -d `<device>`
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/services/meet_consult_service.dart';
import 'package:DrsListing/services/meet_consult_service_io.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ON-DEVICE: real Google Sign-In → calendar event → Meet link',
      (tester) async {
    // The real app initializes Firebase in main(); the test harness pumps
    // its own tree, so initialize here (Google Sign-In needs the default
    // Firebase app — without it the SDK fails with [core/no-app]).
    await Firebase.initializeApp();

    // The real gateway is already the default; make it explicit so a
    // stray test fake can never leak into this on-device run.
    meetFlowGateway = SdkMeetFlowGateway();

    // A video consultation (remote type) — the flow the details sheet's
    // Join Video Call button runs.
    final appointment = AppointmentModel(
      appointmentId: 'APT_MEET_SMOKE',
      doctorName: 'Dr. Smoke',
      patientName: 'Smoke Patient',
      appointmentDate: '2026-08-15',
      appointmentTime: '10:00 AM',
      consultationType: 'video',
    );

    // Minimal surface so the plugin's ActivityAware attach is complete
    // before firing the intent (same pattern as the UPI smoke test).
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: Text('Meet')))),
    );
    await tester.pump();

    debugPrint('>> Firing REAL Meet flow: Google Sign-In → calendar event');
    debugPrint('>> Pick the Google account and APPROVE the Calendar scopes '
        'on the phone…');

    // Await the real chain directly (no pumping — the phone leaves the
    // Flutter frame for the account picker + Meet app).
    final result = await MeetConsultService.joinConsultation(
      // A context is required by the SDK; the root navigator's context is
      // available after the pump above.
      tester.element(find.byType(Scaffold)),
      appointment,
    ).timeout(const Duration(minutes: 2));

    debugPrint('>> FLOW RESULT: success=${result.success} '
        'link=${result.meetingLink} error=${result.error}');

    // The real chain is only "working" if a meet.google.com link came
    // back — exactly the link the sheet would persist for the other side.
    expect(
      result.success,
      isTrue,
      reason: 'a real Google Sign-In + Calendar event must succeed; '
          'check the on-phone error snackbar for config issues',
    );
    expect(result.meetingLink, startsWith('https://meet.google.com/'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
