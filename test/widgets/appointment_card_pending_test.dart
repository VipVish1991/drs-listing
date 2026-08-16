import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/widgets/appointment_card.dart';

import '../helpers/test_data.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  AppointmentModel appointment,
  String displayStatus,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: AppointmentCard(
          appointment: appointment,
          displayStatus: displayStatus,
          onTap: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Pending appointment shows warning badge + confirmation message',
    (tester) async {
      final appointment = appointmentBasic(
        appointmentId: 'APT2001',
        doctorName: 'Dr. Smith',
        appointmentDate: '2026-07-31',
        appointmentTime: 'Flexible',
        status: AppointmentStatus.pending,
      );

      await _pumpCard(tester, appointment, AppointmentStatus.pending);

      // Status badge shows "Pending" with the hourglass icon.
      expect(find.text('Pending'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);

      // The clinic-confirmation message banner is visible.
      expect(
        find.textContaining('Awaiting clinic confirmation'),
        findsOneWidget,
      );

      // Pending card is outlined in the warning color (not primary).
      final badgeText = tester.widget<Text>(find.text('Pending'));
      expect(badgeText.style?.color, AppColors.warning);
    },
  );

  testWidgets('Upcoming appointment does not show the confirmation banner', (
    tester,
  ) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT2002',
      doctorName: 'Dr. Smith',
      appointmentDate: '2026-07-31',
      appointmentTime: '10:00 AM',
      status: AppointmentStatus.upcoming,
    );

    await _pumpCard(tester, appointment, AppointmentStatus.upcoming);

    // Badge shows the normal Upcoming schedule icon, not the hourglass.
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsNothing);

    // No confirmation banner for confirmed/upcoming bookings.
    expect(find.textContaining('Awaiting clinic confirmation'), findsNothing);
  });

  testWidgets('Completed appointment shows check icon and no Pending banner', (
    tester,
  ) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT2003',
      doctorName: 'Dr. Smith',
      appointmentDate: '2026-07-30',
      appointmentTime: '09:00 AM',
      status: AppointmentStatus.completed,
    );

    await _pumpCard(tester, appointment, AppointmentStatus.completed);

    expect(find.text('Completed'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsNothing);
    expect(find.textContaining('Awaiting clinic confirmation'), findsNothing);
  });

  testWidgets('Card shows uploaded prescription thumbnails for patients', (
    tester,
  ) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT2006',
      doctorName: 'Dr. Smith',
      appointmentDate: '2026-07-30',
      appointmentTime: '09:00 AM',
      status: AppointmentStatus.completed,
      consultationType: 'video',
      prescriptionUrls: const ['https://example.com/rx1.jpg'],
    );

    await _pumpCard(tester, appointment, AppointmentStatus.completed);

    // Compact gallery header; the consultation type renders as the
    // full-width row with its own label + value.
    expect(find.text('Prescription'), findsOneWidget);
    expect(find.text('Consultation'), findsOneWidget);
    expect(find.text('Video Consultation'), findsOneWidget);
  });

  testWidgets(
    'the time renders once inside the shared info grid',
    (tester) async {
      final appointment = appointmentBasic(
        appointmentId: 'APT2008',
        doctorName: 'Dr. Smith',
        appointmentDate: '2026-08-08',
        appointmentTime: '11:00 AM',
        status: AppointmentStatus.upcoming,
      );

      await _pumpCard(tester, appointment, AppointmentStatus.upcoming);

      // The shared card shows the time exactly once, as a cell of the
      // 2-column info grid — no separate header chip anymore.
      expect(
        find.byKey(const ValueKey('patient_card_time_chip')),
        findsNothing,
      );
      expect(find.text('11:00 AM'), findsOneWidget);
      expect(find.byIcon(Icons.access_time_rounded), findsOneWidget);

      // Cards without a stored time skip the cell (no crash, no ghost).
      final noTime = appointmentBasic(
        appointmentId: 'APT2009',
        doctorName: 'Dr. Smith',
        appointmentDate: '2026-08-08',
        appointmentTime: null,
        status: AppointmentStatus.upcoming,
      );
      await _pumpCard(tester, noTime, AppointmentStatus.upcoming);
      expect(find.text('11:00 AM'), findsNothing);
      expect(find.byIcon(Icons.access_time_rounded), findsNothing);
    },
  );

  testWidgets(
    'card shows all data on a narrow screen without overflow or truncation',
    (tester) async {
      // 320dp phone — the same width class that caught the doctor-side
      // cards overflowing: every datum must stay on its own full-width row.
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appointment = appointmentBasic(
        appointmentId: 'APT2007',
        doctorName: 'Dr. Rajesh Kumar Sharma',
        appointmentDate: '2026-08-08',
        appointmentTime: '2:00 PM',
        status: AppointmentStatus.upcoming,
        consultationType: 'video',
        patientName: 'Vippp',
        callNumber: '9876543210',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppointmentCard(
              appointment: appointment,
              displayStatus: AppointmentStatus.upcoming,
              onTap: () {},
              // Exercise the widest action set — Map + Cancel flow inside
              // the Wrap instead of overflowing the card edge.
              onMap: () {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // No RenderFlex overflow anywhere on the card.
      expect(tester.takeException(), isNull);

      // Every datum renders in the 2-column info grid (label + value).
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('08-08-2026'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      // The time appears exactly once — as a cell of the info grid.
      expect(find.text('2:00 PM'), findsOneWidget);
      // No separate 'Type' tile — the consultation type renders as the
      // full-width row that replaced the doctor's phone on the card.
      expect(find.text('Type'), findsNothing);
      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Video Consultation'), findsOneWidget);
      // The doctor's phone no longer renders on the card (the details
      // sheet keeps it). The logged-in patient's own name no longer
      // repeats on their own card.
      expect(find.text('Phone'), findsNothing);
      expect(find.text('9876543210'), findsNothing);
      expect(find.text('Patient: Vippp'), findsNothing);
      expect(find.text('Upcoming'), findsOneWidget);
      // All action chips render and fit.
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets('Consultation row and Map chips appear only when known', (
    tester,
  ) async {
    // A card with a stored consultation type shows the full-width
    // Consultation row (the doctor's phone moved into the details sheet),
    // but no Map/Cancel chips — those render only when the caller provides
    // the callbacks.
    final withType = appointmentBasic(
      appointmentId: 'APT2010',
      doctorName: 'Dr. Smith',
      appointmentDate: '2026-07-31',
      appointmentTime: '10:00 AM',
      status: AppointmentStatus.upcoming,
      consultationType: 'video',
    );
    await _pumpCard(tester, withType, AppointmentStatus.upcoming);
    await tester.pump();
    expect(find.text('Consultation'), findsOneWidget);
    expect(find.text('Video Consultation'), findsOneWidget);
    expect(find.text('Map'), findsNothing);
    expect(find.text('Cancel'), findsNothing);

    // Without a stored type there is no Consultation row at all.
    final noType = appointmentBasic(
      appointmentId: 'APT2011',
      doctorName: 'Dr. Smith',
      appointmentDate: '2026-07-31',
      appointmentTime: '10:00 AM',
      status: AppointmentStatus.upcoming,
    );
    await _pumpCard(tester, noType, AppointmentStatus.upcoming);
    await tester.pump();
    expect(find.text('Consultation'), findsNothing);
    expect(find.text('Video Consultation'), findsNothing);
  });
}
