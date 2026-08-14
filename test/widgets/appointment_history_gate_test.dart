import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/screens/appointment/appointment_history_screen.dart';
import 'package:DrsListing/widgets/booking_block_banner.dart';

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
    ),
  );
  await tester.pump();
  await _settleAnimations(tester);
}

/// A yyyy-MM-dd key `daysFromNow` days from today — always future/past
/// relative to the test run so `_effectiveStatus` auto-completion is stable.
String _dayKey(int daysFromNow) {
  final d = DateTime.now().add(Duration(days: daysFromNow));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets('shows the active-booking notice while the patient holds an '
      'active booking', (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_ACTIVE',
        doctorName: 'Dr. Active',
        appointmentDate: _dayKey(1),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
        createdAt: DateTime.now(),
      ),
    ]);

    // The amber notice explains the rule right above the list (no doctor
    // context here — the neutral per-doctor wording).
    expect(
      find.textContaining('Complete or cancel it'),
      findsOneWidget,
    );
    expect(find.byType(BookingBlockBanner), findsOneWidget);

    // The list itself still renders the booking underneath the banner.
    expect(find.text('Dr. Active'), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets('shows no notice for a recently completed booking '
      '(no cooldown)', (tester) async {
    // Completed bookings no longer trigger a wait — the same doctor can
    // be re-booked immediately, so no banner appears even right after.
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_DONE',
        doctorName: 'Dr. Done',
        appointmentDate: _dayKey(-1),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.completed,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ]);

    expect(find.byType(BookingBlockBanner), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('hides the banner when the patient is free to book again', (
    tester,
  ) async {
    // A Completed booking (or an empty history) must not show any notice.
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_OLD',
        doctorName: 'Dr. Old',
        appointmentDate: _dayKey(-3),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.completed,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
    ]);

    expect(find.byType(BookingBlockBanner), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('the banner appears reactively when a booking lands', (
    tester,
  ) async {
    await _pumpScreen(tester, const []);

    // No appointments — no gate notice.
    expect(find.byType(BookingBlockBanner), findsNothing);

    // The patient books (the list updates in place) — the Obx-driven
    // banner must appear without reopening the screen.
    Get.find<AppointmentController>().appointments.assignAll([
      appointmentBasic(
        appointmentId: 'APT_JUST_BOOKED',
        doctorName: 'Dr. New',
        appointmentDate: _dayKey(1),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
        createdAt: DateTime.now(),
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(BookingBlockBanner), findsOneWidget);
    expect(
      find.textContaining('Complete or cancel it'),
      findsOneWidget,
    );

    await _settleAnimations(tester);
  });
}
