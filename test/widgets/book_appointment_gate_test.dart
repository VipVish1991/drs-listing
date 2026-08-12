import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/doctor_slot_model.dart';
import 'package:DrsListing/models/payment_model.dart';
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

/// AppointmentController double whose patient ALREADY holds bookings — the
/// one-doctor-at-a-time gate (active Pending/Upcoming booking, or within
/// the 12h cooldown of the last booking) must block the screen. Provides
/// real slots for tomorrow so a date chip is tappable, and counts how many
/// times [bookAppointment] is invoked (must stay 0 while blocked).
class _GateBlockedAppointmentController extends AppointmentController {
  static const _fullDayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// The patient's existing appointments — the gate input. Defaults to one
  /// active Upcoming booking created just now.
  final List<AppointmentModel> existing;

  /// How many times [bookAppointment] was invoked. Blocked bookings must
  /// never reach it.
  int bookAppointmentCalls = 0;

  _GateBlockedAppointmentController({List<AppointmentModel>? existing})
      : existing = existing ??
            [
              AppointmentModel(
                appointmentId: 'APT-existing-1',
                status: AppointmentStatus.upcoming,
                createdAt: DateTime.now(),
              ),
            ];

  @override
  // ignore: must_call_super
  void onInit() {}

  /// The gate check happens against the FRESHLY loaded appointments — the
  /// screen re-fetches right before booking, so the fake must supply the
  /// same list every time (no Supabase involved).
  @override
  Future<void> loadAppointments() async {
    appointments.value = existing;
  }

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
  }) async {
    bookAppointmentCalls++;
    return true;
  }
}

/// Stub targets for the routes the booking screen references (never
/// reached while blocked, but required so the route table is complete).
class _HomeStub extends StatelessWidget {
  const _HomeStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('HOME_STUB')));
  }
}

class _HistoryStub extends StatelessWidget {
  const _HistoryStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('HISTORY_STUB')));
  }
}

Future<void> _pumpBookingFlow(WidgetTester tester) async {
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
    placeId: 'book_gate_1',
    name: 'Dr. Smith',
  );
  Get.toNamed(AppRoutes.bookAppointment, arguments: {'doctor': doctor});

  // Let the screen build and load slots + appointments.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Selects tomorrow + "9:00 AM" (a fully valid booking) and taps the Book
/// button — so any block that happens is the GATE, not missing fields.
Future<void> _tapBookWithValidSelection(WidgetTester tester) async {
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

  final bookButton = find.widgetWithText(InkWell, 'Book Appointment');
  await tester.ensureVisible(bookButton);
  await tester.pump();
  await tester.tap(bookButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  testWidgets('shows the one-doctor-at-a-time banner when the patient '
      'already has an active booking', (tester) async {
    Get.put<AppointmentController>(
      _GateBlockedAppointmentController(),
      permanent: true,
    );

    await _pumpBookingFlow(tester);

    // The amber gate notice explains the rule — visible on open, before
    // any tap.
    expect(
      find.textContaining('already have an appointment booked'),
      findsOneWidget,
    );
  });

  testWidgets('blocked Book action shows the gate snackbar and never books',
      (tester) async {
    final controller = _GateBlockedAppointmentController();
    Get.put<AppointmentController>(controller, permanent: true);

    await _pumpBookingFlow(tester);

    // A fully valid selection (tomorrow + 9:00 AM) — the gate, not
    // missing fields, must block this.
    await _tapBookWithValidSelection(tester);
    // Let Get.snackbar's entrance animation fully complete before
    // asserting (the helper's final pump leaves ~300ms, right at the
    // animation edge — same workaround as book_appointment_success_test).
    await tester.pump(const Duration(milliseconds: 250));

    // The gate message appears TWICE now: the persistent banner plus the
    // Book-tap snackbar. No success popup, no booking call.
    expect(
      find.textContaining('already have an appointment booked'),
      findsNWidgets(2),
    );
    expect(controller.bookAppointmentCalls, 0);
    expect(find.text('Appointment Booked!'), findsNothing);

    // Settle the snackbar so no timers are left pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('shows the 12h-cooldown banner for a recently completed '
      'booking', (tester) async {
    // Completed bookings still trigger the wait: the next booking is only
    // allowed 12h after the last one was CREATED.
    Get.put<AppointmentController>(
      _GateBlockedAppointmentController(
        existing: [
          AppointmentModel(
            appointmentId: 'APT-completed-1',
            status: AppointmentStatus.completed,
            createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          ),
        ],
      ),
      permanent: true,
    );

    await _pumpBookingFlow(tester);

    expect(
      find.textContaining('12 hours after your last booking'),
      findsOneWidget,
    );

    // The cooldown notice names the remaining time (10 h from a 2h-old
    // booking) — not the active-booking wording.
    expect(
      find.textContaining('already have an appointment booked'),
      findsNothing,
    );
  });
}
