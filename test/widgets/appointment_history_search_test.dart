import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/appointment/appointment_history_screen.dart';
import 'package:DrsListing/widgets/appointment_date_filter.dart';

import '../helpers/test_data.dart';

/// Auth double that skips the real onInit network work (AppointmentController
/// pulls it via Get.find in its field initializer).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// AppointmentController double that skips the real onInit network work and
/// the post-frame loadAppointments call so the pre-seeded list stays intact.
class _TestAppointmentController extends AppointmentController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> loadAppointments() async {}
}

/// Lets the flutter_animate effects on the screen run to completion (the
/// header and cards use fadeIn/slideY backed by Future.delayed timers,
/// which would otherwise trip the "Timer is still pending" guard).
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpScreen(
  WidgetTester tester,
  List<AppointmentModel> appointments,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Get.reset();
  Get.put<AuthController>(_TestAuthController(), permanent: true);
  final controller = _TestAppointmentController();
  controller.appointments.assignAll(appointments);
  Get.put<AppointmentController>(controller, permanent: true);

  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: const AppointmentHistoryScreen(),
      // Stub target for the doctor-detail route (used by the details
      // sheet's "View Doctor Profile" action).
      getPages: [
        GetPage(
          name: AppRoutes.doctorDetail,
          page: () => const _DoctorDetailStub(),
        ),
      ],
    ),
  );
  await tester.pump();
  await _settleAnimations(tester);
}

/// A yyyy-MM-dd key `daysFromNow` days from today — always future/past
/// relative to the test run so `_effectiveStatus` auto-completion is stable.
String _futureKey(int daysFromNow) {
  final d = DateTime.now().add(Duration(days: daysFromNow));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets(
    'header search toggle filters appointments across dates and hides the calendar',
    (tester) async {
      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_ALICE',
          doctorName: 'Dr. Alice Green',
          appointmentDate: _futureKey(1),
          appointmentTime: '09:00 AM',
          status: AppointmentStatus.upcoming,
        ),
        appointmentBasic(
          appointmentId: 'APT_BOB',
          doctorName: 'Dr. Bob Brown',
          appointmentDate: _futureKey(1),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
        ),
      ]);

      // The default view shows them on the most recent date.
      expect(find.text('Dr. Alice Green'), findsOneWidget);
      expect(find.text('Dr. Bob Brown'), findsOneWidget);

      // The header search toggle replaces the old appointment-count badge.
      expect(
        find.byKey(const ValueKey('patient_history_search_toggle')),
        findsOneWidget,
      );

      // Open the search field via the header search toggle.
      await tester.tap(
        find.byKey(const ValueKey('patient_history_search_toggle')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // While searching the date filter is hidden so results span dates.
      expect(find.byType(AppointmentDateFilter), findsNothing);

      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pump();
      expect(find.text('Dr. Alice Green'), findsOneWidget);
      expect(find.text('Dr. Bob Brown'), findsNothing);

      // Clearing the query restores every appointment.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('Dr. Alice Green'), findsOneWidget);
      expect(find.text('Dr. Bob Brown'), findsOneWidget);

      // Closing search brings the calendar back.
      await tester.tap(
        find.byKey(const ValueKey('patient_history_search_toggle')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppointmentDateFilter), findsOneWidget);

      await _settleAnimations(tester);
    },
  );

  testWidgets('renders the day\'s appointments soonest-first', (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_MORNING',
        doctorName: 'Dr. Morning',
        appointmentDate: _futureKey(1),
        appointmentTime: '9:00 AM',
        status: AppointmentStatus.upcoming,
      ),
      appointmentBasic(
        appointmentId: 'APT_NOON',
        doctorName: 'Dr. Noon',
        appointmentDate: _futureKey(1),
        appointmentTime: '12:00 PM',
        status: AppointmentStatus.upcoming,
      ),
      appointmentBasic(
        appointmentId: 'APT_AFTERNOON',
        doctorName: 'Dr. Afternoon',
        appointmentDate: _futureKey(1),
        appointmentTime: '3:00 PM',
        status: AppointmentStatus.upcoming,
      ),
      appointmentBasic(
        appointmentId: 'APT_DONE',
        doctorName: 'Dr. Done',
        appointmentDate: _futureKey(-2),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.completed,
      ),
    ]);

    // The calendar is visible and the list narrows to the most recent
    // date with appointments (tomorrow).
    expect(find.byType(AppointmentDateFilter), findsOneWidget);

    // Earliest appointment of the day renders on top (soonest first).
    final morningY = tester.getTopLeft(find.text('Dr. Morning')).dy;
    final noonY = tester.getTopLeft(find.text('Dr. Noon')).dy;
    final afternoonY = tester.getTopLeft(find.text('Dr. Afternoon')).dy;
    expect(morningY, lessThan(noonY));
    expect(noonY, lessThan(afternoonY));

    // Appointments on other dates (here a completed one two days ago)
    // never appear — the list is narrowed to the selected date.
    expect(find.text('Dr. Done'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('search shows a no-results state for unmatched queries', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_ALICE',
        doctorName: 'Dr. Alice Green',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.upcoming,
      ),
    ]);

    await tester.tap(
      find.byKey(const ValueKey('patient_history_search_toggle')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'zzz-no-such-doctor');
    await tester.pump();

    expect(find.text('No results found'), findsOneWidget);
    expect(find.text('Dr. Alice Green'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('search matches by phone and status too', (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_PHONE',
        doctorName: 'Dr. Call Me',
        callNumber: '9876543210',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.upcoming,
      ),
      appointmentBasic(
        appointmentId: 'APT_DONE',
        doctorName: 'Dr. Finished',
        appointmentDate: _futureKey(1),
        appointmentTime: '11:00 AM',
        status: 'Completed',
      ),
    ]);

    await tester.tap(
      find.byKey(const ValueKey('patient_history_search_toggle')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Search by phone number.
    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.pump();
    expect(find.text('Dr. Call Me'), findsOneWidget);
    expect(find.text('Dr. Finished'), findsNothing);

    // Search by status.
    await tester.enterText(find.byType(TextField), 'Completed');
    await tester.pump();
    expect(find.text('Dr. Finished'), findsOneWidget);
    expect(find.text('Dr. Call Me'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets(
    'tapping a card opens the full details sheet with a Call Now dialer',
    (tester) async {
      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_DETAILS',
          doctorName: 'Dr. Smith',
          patientName: 'John Doe',
          callNumber: '9876543210',
          appointmentDate: _futureKey(1),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          symptoms: 'Fever and headache since two days',
          consultationType: 'video',
        ),
      ]);

      // The card itself no longer previews symptoms.
      expect(find.text('Fever and headache since two days'), findsNothing);
      expect(find.text('Symptoms / Notes'), findsNothing);

      // Tap the card → the details sheet opens with the full information.
      await tester.tap(find.text('Dr. Smith'));
      await tester.pumpAndSettle();

      expect(find.text('Symptoms / Notes'), findsOneWidget);
      // Symptoms live only in the sheet now.
      expect(find.text('Fever and headache since two days'), findsOneWidget);
      // The phone now lives only in the sheet — the card's phone cell was
      // replaced by a consultation row, which renders behind the sheet
      // next to the header consultation chip (the sheet's own detail row
      // was dropped — the chip covers it).
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      // The Consultation label comes only from the card's row; the type
      // VALUE appears twice — the card's row and the header chip.
      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Video Consultation'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('details_sheet_consultation_chip')),
        findsOneWidget,
      );
      expect(find.text('Call Now'), findsOneWidget);
      expect(find.text('Appointment ID'), findsOneWidget);
      expect(find.text('APT_DETAILS'), findsOneWidget);
      // The card renders "Patient: John Doe" as one string, so the bare
      // 'Patient' label below matches only the sheet's detail row.
      expect(find.text('Patient'), findsOneWidget);
      // The doctor profile stays reachable from the sheet.
      expect(find.text('View Doctor Profile'), findsOneWidget);

      // Close the sheet.
      await tester.tap(
        find.byKey(const ValueKey('patient_appointment_details_close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Call Now'), findsNothing);

      await _settleAnimations(tester);
    },
  );

  testWidgets('details sheet shows the consultation type row + prescription', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_RX_TYPE',
        doctorName: 'Dr. Smith',
        patientName: 'John Doe',
        callNumber: '9876543210',
        consultationType: 'tele',
        appointmentDate: _futureKey(-1),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.completed,
        prescriptionUrls: const ['https://example.com/rx1.jpg'],
      ),
    ]);

    // The single date-filtered list shows yesterday's completed booking.
    await tester.tap(find.text('Dr. Smith'));
    await tester.pumpAndSettle();

    // The card's full-width consultation row behind the sheet (it
    // replaced the phone cell) — the sheet itself has no Consultation
    // detail row anymore, only the header chip.
    expect(find.text('Consultation'), findsOneWidget);
    // The value appears twice: the card's row and the header chip.
    expect(find.text('Tele Consultation'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('details_sheet_consultation_chip')),
      findsOneWidget,
    );
    // The prescription gallery is visible — the card's compact strip
    // (behind the sheet) and the sheet's grid header both say "Prescription".
    expect(find.text('Prescription'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('patient_appointment_details_close')),
    );
    await tester.pumpAndSettle();
    await _settleAnimations(tester);
  });

  testWidgets(
    'details sheet "View Doctor Profile" opens the doctor detail route',
    (tester) async {
      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_PROFILE',
          doctorName: 'Dr. Smith',
          doctorPlaceId: 'place_profile_1',
          appointmentDate: _futureKey(1),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
        ),
      ]);

      await tester.tap(find.text('Dr. Smith'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Doctor Profile'));
      await tester.pumpAndSettle();

      // The sheet closes and the doctor detail stub is now the top route.
      expect(find.text('Call Now'), findsNothing);
      expect(find.text('DOCTOR_DETAIL_STUB'), findsOneWidget);

      await _settleAnimations(tester);
    },
  );

  testWidgets('the calendar filter narrows the list to the selected date', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_TOMORROW',
        doctorName: 'Dr. Tomorrow',
        appointmentDate: _futureKey(1),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
      ),
      appointmentBasic(
        appointmentId: 'APT_LATER',
        doctorName: 'Dr. Later',
        appointmentDate: _futureKey(3),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
      ),
    ]);

    // No appointments today, so the screen jumps to the most recent
    // date (day+3) — only that day's appointment renders, proving the
    // calendar narrows the list to the selected date.
    expect(find.text('Dr. Later'), findsOneWidget);
    expect(find.text('Dr. Tomorrow'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('shows every status for the day, sorted by real clock time', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_OLD',
        doctorName: 'Dr. Old',
        appointmentDate: _futureKey(-10),
        appointmentTime: '9:00 AM',
        status: AppointmentStatus.completed,
      ),
      appointmentBasic(
        appointmentId: 'APT_NEW',
        doctorName: 'Dr. New',
        appointmentDate: _futureKey(-10),
        appointmentTime: '2:00 PM',
        status: AppointmentStatus.completed,
      ),
      appointmentBasic(
        appointmentId: 'APT_CANCELLED',
        doctorName: 'Dr. Cancelled',
        appointmentDate: _futureKey(-10),
        appointmentTime: '12:00 PM',
        status: AppointmentStatus.cancelled,
      ),
    ]);

    // No status tabs: Completed + Cancelled share the single
    // date-filtered list (day-10, the only date), earliest first by
    // real clock time.
    expect(find.text('Dr. Old'), findsOneWidget);
    expect(find.text('Dr. Cancelled'), findsOneWidget);
    expect(find.text('Dr. New'), findsOneWidget);
    final oldY = tester.getTopLeft(find.text('Dr. Old')).dy;
    final cancelledY = tester.getTopLeft(find.text('Dr. Cancelled')).dy;
    final newY = tester.getTopLeft(find.text('Dr. New')).dy;
    expect(oldY, lessThan(cancelledY));
    expect(cancelledY, lessThan(newY));

    await _settleAnimations(tester);
  });

  testWidgets('the screen jumps to the most recent date that has rows', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_UP',
        doctorName: 'Dr. Up',
        appointmentDate: _futureKey(1),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
      ),
      appointmentBasic(
        appointmentId: 'APT_DONE_SEL',
        doctorName: 'Dr. Done Sel',
        appointmentDate: _futureKey(3),
        appointmentTime: '9:00 AM',
        status: AppointmentStatus.completed,
      ),
    ]);

    // No appointments today, so the fallback lands on the most recent
    // appointment date overall (day+3), regardless of status.
    expect(find.text('Dr. Done Sel'), findsOneWidget);
    expect(find.text('Dr. Up'), findsNothing);
    expect(find.text('No appointments on this date'), findsNothing);

    await _settleAnimations(tester);
  });
}

/// Stub target for the doctor-detail route.
class _DoctorDetailStub extends StatelessWidget {
  const _DoctorDetailStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('DOCTOR_DETAIL_STUB')));
  }
}
