/// ON-DEVICE smoke test for the Google Meet consultation flow (static room).
///
/// Every consultation in the app uses ONE fixed static Google Meet room —
/// `https://meet.google.com/rnz-wivx-yze` (kStaticMeetLink) — pre-filled
/// on every new appointment's `meet_link` column. Unlike the old flow
/// (Google Sign-In → calendar event creation), joining now just opens that
/// room in the browser / Meet app:
///
///   1. [MeetConsultService.joinConsultation] runs exactly what the
///      details sheet's **Join Video Call** button does.
///   2. No Google Sign-In, no calendar-event creation, no Firebase — the
///      static link is opened externally.
///   3. The test asserts the flow succeeded and returned the static link —
///      the link the sheet persists via `onSaveMeetLink`, so BOTH sides
///      always join the same meeting.
///
/// The service future is awaited DIRECTLY (like the UPI smoke test) rather
/// than pumped — the browser / Meet app leaves the Flutter frame, so
/// widget pumping can't wait for them.
///
/// Run with the phone connected (USB debugging on):
///   flutter test integration_test/meet_consultation_smoke_test.dart -d `<device>`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/services/meet_consult_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ON-DEVICE: join opens the fixed static Meet room', (tester) async {
    // A video consultation (remote type) — the flow the details sheet's
    // Join Video Call button runs. No stored link, so it falls back to the
    // shared static room.
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

    debugPrint('>> Firing Meet flow: opening the static room '
        '$kStaticMeetLink');

    // Await the open directly (no pumping — the phone leaves the Flutter
    // frame for the browser / Meet app).
    final result = await MeetConsultService.joinConsultation(
      tester.element(find.byType(Scaffold)),
      appointment,
    ).timeout(const Duration(minutes: 2));

    debugPrint('>> FLOW RESULT: success=${result.success} '
        'link=${result.meetingLink} error=${result.error}');

    // The static room is the link the sheet would persist for the other
    // side — every meeting lands in the same place.
    expect(result.success, isTrue,
        reason: 'opening the static Meet room must succeed; check the '
            'on-phone error snackbar for config issues');
    expect(result.meetingLink, kStaticMeetLink);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
