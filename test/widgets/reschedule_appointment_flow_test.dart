import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/models/doctor_slot_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/appointment/reschedule_appointment_screen.dart';

import '../helpers/test_data.dart';

/// Auth double that skips the real onInit network work and carries a
/// logged-in patient.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}

  _TestAuthController() {
    currentUser.value = userPatient(name: 'John Patient');
    isLoggedIn.value = true;
  }
}

/// AppointmentController double: provides a slot on tomorrow (so a date
/// chip is tappable) and records reschedule requests without Supabase.
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
  Future<void> loadAppointments() async {}

  bool acceptMove = true;
  bool rescheduleCalled = false;
  String? rescheduleDate;
  String? rescheduleTime;
  String? rescheduleType;
  bool? rescheduleInitiatedByDoctor;

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
  Future<void> loadBookedSlots(String doctorPlaceId) async {}

  @override
  Future<bool> rescheduleAppointment(
    AppointmentModel appointment, {
    required String date,
    required String time,
    required String consultationType,
    bool initiatedByDoctor = false,
  }) async {
    rescheduleCalled = true;
    rescheduleDate = date;
    rescheduleTime = time;
    rescheduleType = consultationType;
    rescheduleInitiatedByDoctor = initiatedByDoctor;
    return acceptMove;
  }
}

/// Variant that pre-seeds booked slots (incl. the appointment's own slot)
/// so the own-slot-stays-selectable path can be exercised through the UI.
class _SeededBookedSlotsController extends _FakeAppointmentController {
  _SeededBookedSlotsController(this.seededKeys);

  final Set<String> seededKeys;

  @override
  Future<void> loadBookedSlots(String doctorPlaceId) async {
    bookedSlotKeys.assignAll(seededKeys);
  }
}

/// Lets the flutter_animate effects on the screen run to completion.
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// Tomorrow's ISO date key — always inside the 14-day booking window.
String _tomorrowKey() {
  final d = DateTime.now().add(const Duration(days: 1));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Future<_FakeAppointmentController> _pumpScreen(
  WidgetTester tester, {
  required AppointmentModel appointment,
  bool acceptMove = true,
  bool initiatedByDoctor = false,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Get.reset();
  Get.put<AuthController>(_TestAuthController(), permanent: true);
  final controller = _FakeAppointmentController()..acceptMove = acceptMove;
  Get.put<AppointmentController>(controller, permanent: true);

  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      // A concrete `home` is required so Get's route middleware doesn't
      // hit its null-check on first build (see doctor_detail_screen_test).
      home: const SizedBox(),
      getPages: [
        GetPage(
          name: AppRoutes.rescheduleAppointment,
          page: () => const RescheduleAppointmentScreen(),
        ),
      ],
    ),
  );

  Get.toNamed(
    AppRoutes.rescheduleAppointment,
    arguments: {
      'appointment': appointment,
      if (initiatedByDoctor) 'initiatedByDoctor': true,
    },
  );

  // Let the screen build and load slots.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await _settleAnimations(tester);
  return controller;
}

/// Taps tomorrow's date chip, then the [slotText] time chip.
Future<void> _pickSlot(WidgetTester tester, String slotText) async {
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

  final slotChip = find.text(slotText);
  await tester.ensureVisible(slotChip);
  await tester.pump();
  await tester.tap(slotChip);
  await tester.pump();
}

void main() {
  testWidgets('reschedule screen shows the current appointment summary and '
      'the new-slot picker', (tester) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS',
      doctorName: 'Dr. Alice Green',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
      doctorPlaceId: 'place_resched_1',
      consultationType: 'clinic',
    );

    await _pumpScreen(tester, appointment: appointment);

    // Header + current-appointment summary (dd-MM-yyyy display format).
    expect(find.text('Reschedule'), findsOneWidget);
    expect(find.text('Dr. Alice Green'), findsOneWidget);
    expect(find.textContaining('Current appointment'), findsOneWidget);
    expect(find.textContaining('01-08-2026'), findsOneWidget);
    expect(find.textContaining('9:00 AM'), findsWidgets);

    // Date strip header present.
    expect(find.text('Select New Date'), findsOneWidget);
  });

  testWidgets('header shows the consultation-type chip for typed rows', (
    tester,
  ) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS_CHIP',
      doctorName: 'Dr. Alice Green',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
      doctorPlaceId: 'place_resched_chip',
      consultationType: 'clinic',
    );

    await _pumpScreen(tester, appointment: appointment);

    // The header chip mirrors the details sheet's — same info-tinted pill,
    // storefront icon for in-clinic visits.
    expect(
      find.byKey(const ValueKey('reschedule_screen_consultation_chip')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    // The value renders in the header chip AND the current-appointment
    // card's subtitle (the card falls back to the type label).
    expect(find.text('In-Clinic Visit'), findsNWidgets(2));
  });

  testWidgets('video-type rows show the chip with the videocam icon', (
    tester,
  ) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS_CHIP_VIDEO',
      doctorName: 'Dr. Alice Green',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
      doctorPlaceId: 'place_resched_chip_video',
      consultationType: 'video',
    );

    await _pumpScreen(tester, appointment: appointment);

    // Tele/Video rows map to the videocam icon — same mapping as the
    // details sheet chip (clinic rows use the storefront icon instead).
    expect(
      find.byKey(const ValueKey('reschedule_screen_consultation_chip')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
    expect(find.byIcon(Icons.storefront_rounded), findsNothing);
    // Chip + the current-appointment card's subtitle (falls back to the
    // type label) render the value.
    expect(find.text('Video Consultation'), findsNWidgets(2));
  });

  testWidgets('no consultation chip for legacy rows without a stored type', (
    tester,
  ) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS_LEGACY',
      doctorName: 'Dr. Alice Green',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
      doctorPlaceId: 'place_resched_legacy',
    );

    await _pumpScreen(tester, appointment: appointment);

    expect(
      find.byKey(const ValueKey('reschedule_screen_consultation_chip')),
      findsNothing,
    );
  });

  testWidgets('patient can pick a new slot and confirm the reschedule', (
    tester,
  ) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS',
      doctorName: 'Dr. Alice Green',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
      doctorPlaceId: 'place_resched_2',
      consultationType: 'clinic',
    );

    final controller = await _pumpScreen(tester, appointment: appointment);

    // Pick tomorrow + the 9:30 AM slot.
    await _pickSlot(tester, '9:30 AM');

    // Bottom bar reflects the selection and confirms.
    final confirmButton = find.widgetWithText(InkWell, 'Confirm Reschedule');
    await tester.ensureVisible(confirmButton);
    await tester.pump();
    await tester.tap(confirmButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _settleAnimations(tester);

    expect(controller.rescheduleCalled, isTrue);
    expect(controller.rescheduleDate, _tomorrowKey());
    expect(controller.rescheduleTime, '9:30 AM');
    expect(controller.rescheduleType, 'clinic');
    expect(controller.rescheduleInitiatedByDoctor, isFalse);

    // Success dialog appears with the new slot.
    expect(find.text('Appointment Rescheduled!'), findsOneWidget);
    expect(find.textContaining('9:30 AM'), findsWidgets);
  });

  testWidgets('doctor-initiated mode shows the patient as the subject and '
      'notifies them on confirm', (tester) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS_DOC',
      doctorName: 'Dr. Alice Green',
      patientName: 'Ravi Kumar',
      patientPhone: '9898989898',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
      doctorPlaceId: 'place_resched_doc',
      consultationType: 'clinic',
    );

    final controller = await _pumpScreen(
      tester,
      appointment: appointment,
      initiatedByDoctor: true,
    );

    // The current-appointment card is about the PATIENT (not the doctor).
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('9898989898'), findsOneWidget);

    await _pickSlot(tester, '9:30 AM');
    final confirmButton = find.widgetWithText(InkWell, 'Confirm Reschedule');
    await tester.ensureVisible(confirmButton);
    await tester.pump();
    await tester.tap(confirmButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _settleAnimations(tester);

    // The doctor-initiated flag reached the controller, so the doctor-
    // scoped DB update + patient notification path runs.
    expect(controller.rescheduleCalled, isTrue);
    expect(controller.rescheduleInitiatedByDoctor, isTrue);

    // Success dialog: subject is the patient and the copy reflects who was
    // notified.
    expect(find.text('Appointment Rescheduled!'), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsWidgets);
    expect(
      find.text('The patient has been notified of the new time.'),
      findsOneWidget,
    );
  });

  testWidgets('the appointment\'s own slot stays selectable while other '
      'booked slots are disabled', (tester) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    // The appointment being rescheduled sits on tomorrow at 9:00 AM; the
    // doctor also has another booking at 10:00 AM that day.
    final appointment = appointmentBasic(
      appointmentId: 'APT_OWN',
      doctorName: 'Dr. Alice Green',
      appointmentDate: _tomorrowKey(),
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
      doctorPlaceId: 'place_resched_own',
      consultationType: 'clinic',
    );

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    final controller = _SeededBookedSlotsController({
      // Its own slot — must stay available during reschedule.
      '${_tomorrowKey()}|9:00 AM',
      // Another patient's slot — must render as disabled.
      '${_tomorrowKey()}|10:00 AM',
    });
    Get.put<AppointmentController>(controller, permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const SizedBox(),
        getPages: [
          GetPage(
            name: AppRoutes.rescheduleAppointment,
            page: () => const RescheduleAppointmentScreen(),
          ),
        ],
      ),
    );
    Get.toNamed(
      AppRoutes.rescheduleAppointment,
      arguments: {'appointment': appointment},
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _settleAnimations(tester);

    // Tap tomorrow's date chip.
    final dateChip = find.descendant(
      of: find.byType(GestureDetector),
      matching: find.text('${tomorrow.day}'),
    );
    await tester.ensureVisible(dateChip.first);
    await tester.pump();
    await tester.tap(dateChip.first);
    await tester.pump();

    // Its own slot (9:00 AM) shows as an enabled tappable chip; the other
    // patient's slot (10:00 AM) renders as disabled "Booked".
    final ownChip = find.text('9:00 AM');
    expect(ownChip, findsOneWidget);
    expect(find.text('Booked'), findsOneWidget);

    // Tapping its own slot selects it (not locked).
    await tester.ensureVisible(ownChip);
    await tester.pump();
    await tester.tap(ownChip);
    await tester.pump();
    final confirmButton = find.widgetWithText(InkWell, 'Confirm Reschedule');
    await tester.ensureVisible(confirmButton);
    await tester.pump();
    await tester.tap(confirmButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _settleAnimations(tester);

    expect(controller.rescheduleCalled, isTrue);
    expect(controller.rescheduleDate, _tomorrowKey());
    expect(controller.rescheduleTime, '9:00 AM');
  });

  testWidgets('a rejected move (slot just taken) shows no success dialog', (
    tester,
  ) async {
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS',
      doctorName: 'Dr. Alice Green',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
      doctorPlaceId: 'place_resched_3',
      consultationType: 'clinic',
    );

    final controller = await _pumpScreen(
      tester,
      appointment: appointment,
      acceptMove: false,
    );

    await _pickSlot(tester, '9:30 AM');
    final confirmButton = find.widgetWithText(InkWell, 'Confirm Reschedule');
    await tester.ensureVisible(confirmButton);
    await tester.pump();
    await tester.tap(confirmButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _settleAnimations(tester);

    expect(controller.rescheduleCalled, isTrue);
    expect(find.text('Appointment Rescheduled!'), findsNothing);

    // The error snackbar leaves a 3s auto-dismiss timer pending — close it
    // so the test framework doesn't flag it (same as the booking UPI test).
    Get.closeAllSnackbars();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });
}
