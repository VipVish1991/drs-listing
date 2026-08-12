import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/payment_history_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/appointment/appointment_history_screen.dart';

import '../helpers/test_data.dart';

/// Auth double that skips the real onInit network work.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// AppointmentController double that skips the onInit network work and the
/// post-frame loadAppointments call so the pre-seeded list stays intact.
class _TestAppointmentController extends AppointmentController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> loadAppointments() async {}
}

/// Lets the flutter_animate effects on the screen run to completion.
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// A yyyy-MM-dd key `daysFromNow` days from today — always future relative
/// to the test run so `effectiveStatus` never auto-completes these rows.
String _futureKey(int daysFromNow) {
  final d = DateTime.now().add(Duration(days: daysFromNow));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}' ;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  List<AppointmentModel> appointments, {
  List<PaymentModel> payments = const [],
}
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
  // Pre-seed the patient's payment rows so the details sheet can show the
  // fee/payment card for this appointment.
  if (payments.isNotEmpty) {
    final paymentController = PaymentHistoryController();
    paymentController.payments.assignAll(payments);
    Get.put<PaymentHistoryController>(paymentController, permanent: true);
  }

  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: const AppointmentHistoryScreen(),
      getPages: [
        GetPage(
          name: AppRoutes.rescheduleAppointment,
          page: () => const _RescheduleStub(),
        ),
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

class _RescheduleStub extends StatelessWidget {
  const _RescheduleStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('RESCHEDULE_STUB')));
  }
}

class _DoctorDetailStub extends StatelessWidget {
  const _DoctorDetailStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('DOCTOR_STUB')));
  }
}

void main() {
  testWidgets('Upcoming and Pending appointments show no Reschedule chip on '
      'the card list', (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_UP',
        doctorName: 'Dr. Upcoming',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.upcoming,
      ),
      appointmentBasic(
        appointmentId: 'APT_PEND',
        doctorName: 'Dr. Pending',
        appointmentDate: _futureKey(1),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.pending,
      ),
    ]);

    // Rescheduling moved off the card list — the details sheet is its
    // single entry point (covered by the sheet tests below).
    expect(find.text('Reschedule'), findsNothing);
  });

  testWidgets('Completed and Cancelled appointments hide the Reschedule chip',
      (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_DONE',
        doctorName: 'Dr. Done',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.completed,
      ),
      appointmentBasic(
        appointmentId: 'APT_CANCEL',
        doctorName: 'Dr. Cancelled',
        appointmentDate: _futureKey(1),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.cancelled,
      ),
    ]);

    expect(find.text('Reschedule'), findsNothing);
  });

  testWidgets('tapping Reschedule opens the reschedule screen with the '
      'appointment', (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_TAP',
        doctorName: 'Dr. Tappable',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.upcoming,
      ),
    ]);

    // The card has no chip — the sheet's Reschedule action is the entry
    // point: open the sheet, then tap its action.
    await tester.tap(find.text('Dr. Tappable'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('patient_appointment_details_reschedule')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('RESCHEDULE_STUB'), findsOneWidget);
  });

  testWidgets('details sheet shows Reschedule for an Upcoming appointment '
      'and opens the reschedule screen from it', (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_SHEET_UP',
        doctorName: 'Dr. Sheet',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.upcoming,
      ),
    ]);

    // Open the details bottom sheet from the card.
    await tester.tap(find.text('Dr. Sheet'));
    await tester.pumpAndSettle();

    // The sheet exposes the Reschedule action (in addition to the card chip).
    expect(
      find.byKey(
        const ValueKey('patient_appointment_details_reschedule'),
      ),
      findsOneWidget,
    );

    // Tapping it closes the sheet and lands on the reschedule screen.
    await tester.tap(
      find.byKey(const ValueKey('patient_appointment_details_reschedule')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('RESCHEDULE_STUB'), findsOneWidget);
  });

  testWidgets('details sheet hides Reschedule for a Completed appointment',
      (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_SHEET_DONE',
        doctorName: 'Dr. Done Sheet',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.completed,
      ),
    ]);

    await tester.tap(find.text('Dr. Done Sheet'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('patient_appointment_details_reschedule')),
      findsNothing,
    );
  });

  testWidgets('details sheet shows the appointment fee/payment card for the '
      'patient', (tester) async {
    await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_PAY_P',
          doctorName: 'Dr. Paying',
          appointmentDate: _futureKey(1),
          appointmentTime: '09:00 AM',
          status: AppointmentStatus.upcoming,
        ),
      ],
      payments: [
        PaymentModel(
          appointmentId: 'APT_PAY_P',
          patientId: 'user_1',
          amount: 800,
          paymentStatus: 'Paid',
          paymentMethod: 'online',
          transactionId: 'UPI-PATIENT-1',
          paidAt: DateTime(2026, 8, 3),
        ),
      ],
    );

    await tester.tap(find.text('Dr. Paying'));
    await tester.pumpAndSettle();

    // The fee card renders alongside the sheet's Reschedule action.
    expect(find.text('₹800'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Online (UPI)'), findsOneWidget);
    expect(find.text('UPI-PATIENT-1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('patient_appointment_details_reschedule')),
      findsOneWidget,
    );
  });

  testWidgets('details sheet shows no fee card when the appointment has no '
      'payment row', (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_NO_PAY',
        doctorName: 'Dr. No Payment',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.upcoming,
      ),
    ]);

    await tester.tap(find.text('Dr. No Payment'));
    await tester.pumpAndSettle();

    expect(find.text('Payment'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
  });

  testWidgets('Pending appointment asks for confirmation before opening the '
      'reschedule screen', (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_PEND_CONFIRM',
        doctorName: 'Dr. Pending Confirm',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.pending,
      ),
    ]);

    // Open the sheet and tap its Reschedule action — the confirmation
    // dialog stands between that and the reschedule screen.
    await tester.tap(find.text('Dr. Pending Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('patient_appointment_details_reschedule')),
    );
    await tester.pumpAndSettle();

    expect(find.text('RESCHEDULE_STUB'), findsNothing);
    expect(find.text('Reschedule pending appointment?'), findsOneWidget);
    expect(
      find.textContaining("hasn't been confirmed by the clinic"),
      findsOneWidget,
    );

    // Confirming proceeds to the reschedule screen.
    await tester.tap(
      find.byKey(const ValueKey('pending_reschedule_confirm_proceed')),
    );
    await tester.pumpAndSettle();

    expect(find.text('RESCHEDULE_STUB'), findsOneWidget);
  });

  testWidgets('declining the pending confirmation keeps the history screen',
      (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_PEND_KEEP',
        doctorName: 'Dr. Pending Keep',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.pending,
      ),
    ]);

    await tester.tap(find.text('Dr. Pending Keep'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('patient_appointment_details_reschedule')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('pending_reschedule_confirm_cancel')),
    );
    await tester.pumpAndSettle();

    expect(find.text('RESCHEDULE_STUB'), findsNothing);
    expect(find.text('Reschedule pending appointment?'), findsNothing);
    // Still on the history screen.
    expect(find.text('My Appointments'), findsOneWidget);
  });

  testWidgets('pending details-sheet Reschedule action also asks for '
      'confirmation first', (tester) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_SHEET_PEND',
        doctorName: 'Dr. Pending Sheet',
        appointmentDate: _futureKey(1),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.pending,
      ),
    ]);

    await tester.tap(find.text('Dr. Pending Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('patient_appointment_details_reschedule')),
    );
    await tester.pumpAndSettle();

    // The sheet closes and the confirmation dialog appears — the
    // reschedule screen is NOT opened yet.
    expect(find.text('Reschedule pending appointment?'), findsOneWidget);
    expect(find.text('RESCHEDULE_STUB'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('pending_reschedule_confirm_proceed')),
    );
    await tester.pumpAndSettle();

    expect(find.text('RESCHEDULE_STUB'), findsOneWidget);
  });
}
