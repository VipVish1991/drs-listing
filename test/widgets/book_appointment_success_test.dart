import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/doctor_slot_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/models/unavailable_range.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/appointment/book_appointment_screen.dart';

import '../helpers/test_data.dart';

/// Auth double that skips the real onInit network work and carries a
/// logged-in patient so the booking screen can pre-fill the name.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}

  _TestAuthController() {
    currentUser.value = userPatient(name: 'John Patient');
    isLoggedIn.value = true;
  }
}

/// AppointmentController double: returns real slots for tomorrow (so a date
/// chip is tappable) and reports a successful booking without touching
/// Supabase.
class _FakeAppointmentController extends AppointmentController {
  static const _fullDayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> loadDoctorSlots(String doctorPlaceId) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final dayOfWeek = _fullDayNames[tomorrow.weekday - 1];
    doctorSlots.value = [
      DoctorSlot(
        doctorPlaceId: doctorPlaceId,
        dayOfWeek: dayOfWeek,
        scheduleType: 'clinic',
        startTime: '09:00',
        endTime: '12:00',
        durationMinutes: 30,
        fee: 500,
        slots: ['9:00 AM', '9:30 AM', '10:00 AM'],
        isEnabled: true,
      ),
    ];
  }

  @override
  Future<bool> bookAppointment(
    DoctorModel doctor, {
    PaymentModel? payment,
  }) async => true;
}

/// Stub target for the home route (the success flow clears the whole
/// stack back to Home first, then redirects to history after 1s).
class _HomeStub extends StatelessWidget {
  const _HomeStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('HOME_STUB')));
  }
}

/// Stub target for the appointment-history route.
class _HistoryStub extends StatelessWidget {
  const _HistoryStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('HISTORY_STUB')));
  }
}

Future<void> _pumpBookingFlow(
  WidgetTester tester, {
  List<UnavailableRange> unavailableRanges = const [],
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      // A concrete `home` is required so Get's route middleware doesn't
      // hit its null-check on first build (see doctor_detail_screen_test).
      home: const SizedBox(),
      getPages: [
        GetPage(name: AppRoutes.home, page: () => const _HomeStub()),
        GetPage(
          name: AppRoutes.bookAppointment,
          page: () => const BookAppointmentScreen(),
        ),
        GetPage(
          name: AppRoutes.appointmentHistory,
          page: () => const _HistoryStub(),
        ),
      ],
    ),
  );

  final doctor = doctorBasic(
    placeId: 'book_success_1',
    name: 'Dr. Smith',
    unavailableRanges: unavailableRanges,
  );
  Get.toNamed(AppRoutes.bookAppointment, arguments: {'doctor': doctor});

  // Let the screen build and load slots.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Taps the first tappable day (tomorrow) and the "9:00 AM" slot chip,
/// then scrolls the Book button into view and taps it. The booking screen
/// is taller than the 800×600 test surface, so taps on off-screen widgets
/// silently miss — every target must be scrolled into view first.
Future<void> _bookAppointment(WidgetTester tester) async {
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  final dateChip = find.descendant(
    of: find.byType(GestureDetector),
    matching: find.text('${tomorrow.day}'),
  );
  expect(dateChip, findsWidgets);
  await tester.ensureVisible(dateChip.first);
  await tester.pump();
  await tester.tap(dateChip.first);
  await tester.pump();

  final slotChip = find.text('9:00 AM');
  await tester.ensureVisible(slotChip);
  await tester.pump();
  await tester.tap(slotChip);
  await tester.pump();

  // The Book button is an InkWell inside the bottom bar (not an
  // ElevatedButton) — keep the finder in sync with the widget type.
  final bookButton = find.widgetWithText(InkWell, 'Book Appointment');
  await tester.ensureVisible(bookButton);
  await tester.pump();
  await tester.tap(bookButton);
  await tester.pump();

  // Every paid consultation (even in-clinic) now asks how to pay — pick
  // Offline Pay to complete the booking (the test doctor has no UPI ID,
  // so the sheet offers only the offline tile).
  final offlineTile = find.text('Offline Pay');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(offlineTile);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _FakeAppointmentController(),
      permanent: true,
    );
  });

  testWidgets('successful booking shows success popup then navigates to '
      'Appointment History', (tester) async {
    await _pumpBookingFlow(tester);
    await _bookAppointment(tester);

    // The success popup must be visible.
    expect(find.text('Appointment Booked!'), findsOneWidget);
    expect(find.text('Dr. Smith'), findsWidgets);

    // The summary chip shows the appointment in the app-wide dd-MM-yyyy
    // display format (not the stored yyyy-MM-dd key).
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final expectedDate =
        '${tomorrow.day.toString().padLeft(2, '0')}-'
        '${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.year}';
    expect(find.text('$expectedDate  •  9:00 AM'), findsOneWidget);

    // Tapping "View Appointments" first clears the whole previous stack
    // back to Home… (Tap the label text: ElevatedButton.icon builds a
    // private _ElevatedButtonWithIcon, which find.byType(ElevatedButton)
    // misses.)
    await tester.tap(find.text('View Appointments'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('HOME_STUB'), findsOneWidget);
    expect(find.text('HISTORY_STUB'), findsNothing);

    // …then after 1 second the patient is redirected to Appointment
    // History (pushed on top of Home, so Home stays in the route stack
    // underneath — assert the top route instead of the widget vanishing).
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('HISTORY_STUB'), findsOneWidget);
    expect(Get.currentRoute, AppRoutes.appointmentHistory);
  });

  testWidgets('already-booked slot is disabled and can\'t be selected', (
    tester,
  ) async {
    // Swap in a controller that reports '9:00 AM' on tomorrow as booked.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _BookedSlotAppointmentController(),
      permanent: true,
    );

    await _pumpBookingFlow(tester);

    // Tap tomorrow (the fake provides slots for tomorrow).
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final dateChip = find.descendant(
      of: find.byType(GestureDetector),
      matching: find.text('${tomorrow.day}'),
    );
    await tester.ensureVisible(dateChip.first);
    await tester.pump();
    await tester.tap(dateChip.first);
    await tester.pump();

    // The booked slot renders as a disabled 'Booked' chip; the free slots
    // still show their time.
    expect(find.text('Booked'), findsOneWidget);
    expect(find.text('9:30 AM'), findsOneWidget);
    expect(find.text('10:00 AM'), findsOneWidget);

    // Tapping the Booked chip must NOT select it.
    await tester.tap(find.text('Booked'));
    await tester.pump();

    // With nothing selected, booking asks for a time slot instead of
    // booking the disabled one.
    final bookButton = find.widgetWithText(InkWell, 'Book Appointment');
    await tester.ensureVisible(bookButton);
    await tester.pump();
    await tester.tap(bookButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Please select a time slot'), findsOneWidget);
    expect(find.text('Appointment Booked!'), findsNothing);

    // Settle the snackbar so no timers are left pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('failed booking shows error snackbar and no popup', (
    tester,
  ) async {
    // Swap in a failing controller for this test.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _FailingAppointmentController(),
      permanent: true,
    );

    await _pumpBookingFlow(tester);
    await _bookAppointment(tester);
    // Let Get.snackbar's entrance animation fully complete before asserting
    // (the helper's final pump leaves ~300ms, right at the animation edge).
    await tester.pump(const Duration(milliseconds: 250));

    // No success popup; error feedback instead.
    expect(find.text('Appointment Booked!'), findsNothing);
    expect(find.text('Failed to book appointment'), findsOneWidget);

    // Let Get.snackbar's auto-dismiss timer fire, then settle the exit
    // animation so the test doesn't end with a pending timer or a running
    // Ticker on the disposed Overlay.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('today\'s next available future slot is auto-selected on open', (
    tester,
  ) async {
    // Swap in a controller that provides slots for TODAY.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _TodaySlotsAppointmentController(),
      permanent: true,
    );

    await _pumpBookingFlow(tester);

    // Today's date is auto-selected, so the slot chips render without any
    // tap: the earliest free slot (9:00 AM) is pre-highlighted.
    expect(find.text('9:00 AM'), findsWidgets);
    expect(find.text('9:30 AM'), findsOneWidget);

    // The bottom-bar summary shows today's date + the pre-selected slot.
    expect(find.text(_todaySummary('9:00 AM')), findsOneWidget);
  });

  testWidgets('auto-select skips a booked slot and picks the next free one', (
    tester,
  ) async {
    // Today's 9:00 AM is already booked — the next available future slot
    // (9:30 AM) must be pre-selected instead.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _TodayBookedFirstSlotController(),
      permanent: true,
    );

    await _pumpBookingFlow(tester);

    expect(find.text('Booked'), findsOneWidget);
    expect(find.text('9:30 AM'), findsOneWidget);
    expect(find.text(_todaySummary('9:30 AM')), findsOneWidget);
  });

  testWidgets('date the doctor marked unavailable is disabled and can\'t be '
      'booked', (tester) async {
    // Today's slots exist but the doctor marked today unavailable — the
    // date chip must render disabled, no slot is auto-selected, and the
    // slots section explains the doctor is unavailable.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _TodaySlotsAppointmentController(),
      permanent: true,
    );

    await _pumpBookingFlow(
      tester,
      unavailableRanges: [
        UnavailableRange(start: DateTime.now(), end: DateTime.now()),
      ],
    );

    // No slot was auto-selected (today is unavailable), so the summary is
    // absent and the booking button needs a date+time.
    expect(find.textContaining('•  9:00 AM'), findsNothing);

    // The bottom-bar Book button must not produce a success popup.
    final bookButton = find.widgetWithText(InkWell, 'Book Appointment');
    await tester.ensureVisible(bookButton);
    await tester.pump();
    await tester.tap(bookButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Please select a date'), findsOneWidget);
    expect(find.text('Appointment Booked!'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('unavailable date chip is disabled and can\'t be selected', (
    tester,
  ) async {
    // Tomorrow has slots, but the doctor marked tomorrow unavailable.
    // Because the passed doctor model already carries the ranges, the date
    // chip is disabled — picking another day (day 2) still works.
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _FakeAppointmentController(),
      permanent: true,
    );

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await _pumpBookingFlow(
      tester,
      unavailableRanges: [UnavailableRange(start: tomorrow, end: tomorrow)],
    );

    // The tomorrow chip is disabled — tapping it must not select it.
    final tomorrowChip = find.descendant(
      of: find.byType(GestureDetector),
      matching: find.text('${tomorrow.day}'),
    );
    await tester.ensureVisible(tomorrowChip.first);
    await tester.pump();
    await tester.tap(tomorrowChip.first);
    await tester
        .pump(); // Nothing was selected, so the slots section for tomorrow never opens
    // (no slot chips render) and the Book button still asks for a date.
    expect(find.text('9:00 AM'), findsNothing);

    final bookButton = find.widgetWithText(InkWell, 'Book Appointment');
    await tester.ensureVisible(bookButton);
    await tester.pump();
    await tester.tap(bookButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Please select a date'), findsOneWidget);
    expect(find.text('Appointment Booked!'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}

/// Builds the booking screen's bottom-bar summary string for TODAY with
/// the given pre-selected slot. Mirrors the widget's exact format so a
/// change to that format breaks these tests instead of silently drifting.
String _todaySummary(String slot) {
  const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const monthNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final today = DateTime.now();
  return '${dayLabels[today.weekday - 1]}, ${today.day} '
      '${monthNames[today.month]}  •  $slot';
}

class _FailingAppointmentController extends _FakeAppointmentController {
  @override
  Future<bool> bookAppointment(
    DoctorModel doctor, {
    PaymentModel? payment,
  }) async => false;
}

/// Fake whose tomorrow '9:00 AM' slot is already booked (Upcoming) by
/// another patient, so the booking screen must render it disabled.
class _BookedSlotAppointmentController extends _FakeAppointmentController {
  @override
  Future<void> loadBookedSlots(String doctorPlaceId) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final isoDate =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    bookedSlotKeys.assignAll({'$isoDate|9:00 AM'});
  }
}

/// Fake whose TODAY has available slots, so the booking screen must
/// auto-select today's next available (future) slot on open.
class _TodaySlotsAppointmentController extends _FakeAppointmentController {
  @override
  Future<void> loadDoctorSlots(String doctorPlaceId) async {
    final today = DateTime.now();
    final dayOfWeek =
        _FakeAppointmentController._fullDayNames[today.weekday - 1];
    doctorSlots.value = [
      DoctorSlot(
        doctorPlaceId: doctorPlaceId,
        dayOfWeek: dayOfWeek,
        scheduleType: 'clinic',
        startTime: '09:00',
        endTime: '12:00',
        durationMinutes: 30,
        fee: 500,
        slots: ['9:00 AM', '9:30 AM', '10:00 AM'],
        isEnabled: true,
      ),
    ];
  }

  // The real implementation compares against DateTime.now(), so morning
  // slots would read as 'past' depending on when the suite runs. Force
  // today's slots bookable so the auto-select test is deterministic.
  @override
  bool isSlotInPast(String isoDate, String timeSlot) => false;
}

/// Fake whose today '9:00 AM' slot is already booked — auto-select must
/// skip it and pre-highlight the next free slot (9:30 AM).
class _TodayBookedFirstSlotController extends _TodaySlotsAppointmentController {
  @override
  Future<void> loadBookedSlots(String doctorPlaceId) async {
    final today = DateTime.now();
    final isoDate =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    bookedSlotKeys.assignAll({'$isoDate|9:00 AM'});
  }
}
