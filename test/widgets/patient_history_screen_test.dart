import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/doctor_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/doctor/patient_history_screen.dart';
import 'package:DrsListing/widgets/appointment_info_card.dart';
import 'package:DrsListing/widgets/zoomable_image.dart';

import '../helpers/csv_export_helpers.dart';
import '../helpers/test_data.dart';

/// Auth double that skips the real onInit (secure-storage channel) — must
/// be registered before any [AppointmentController] is constructed (its
/// field initializer does `Get.find<AuthController>()`).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// AppointmentController double that skips the onInit network work — the
/// screen only calls [AppointmentController.effectiveStatus] (a pure
/// parser) to decide whether a visit is reschedulable.
class _TestAppointmentController extends AppointmentController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> loadAppointments() async {}
}

/// Stand-in for the reschedule route the doctor's sheet action opens.
class _RescheduleStub extends StatelessWidget {
  const _RescheduleStub();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('RESCHEDULE_STUB')));
  }
}

/// A yyyy-MM-dd key `daysFromNow` days from today — always future relative
/// to the test run so `effectiveStatus` never auto-completes these rows.
String _futureKey(int daysFromNow) {
  final d = DateTime.now().add(Duration(days: daysFromNow));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Lets the flutter_animate timeline effects run to completion (fadeIn +
/// slideY backed by Future.delayed timers would otherwise trip the
/// "Timer is still pending" guard).
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  Future<void> pumpHistory(
    WidgetTester tester, {
    required List<AppointmentModel> appointments,
    String? highlightId,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Get.reset();
    // AuthController first — AppointmentController's field initializer
    // does Get.find<AuthController>() and the details sheet calls
    // effectiveStatus (needs the controller registered). DoctorController
    // powers the sheet's fee/payment lookup.
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _TestAppointmentController(),
      permanent: true,
    );
    Get.put<DoctorController>(DoctorController(), permanent: true);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: PatientHistoryScreen(
          appointments: appointments,
          highlightId: highlightId,
        ),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);
  }

  testWidgets('header shows patient identity and visit summary', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      appointments: [
        appointmentBasic(
          appointmentId: 'APT_H1',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-07-01',
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.completed,
          symptoms: 'Fever and body ache',
        ),
        appointmentBasic(
          appointmentId: 'APT_H2',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-08-01',
          appointmentTime: '11:00 AM',
          status: AppointmentStatus.upcoming,
          symptoms: 'Recurring headache',
        ),
      ],
      highlightId: 'APT_H2',
    );

    expect(find.text('Patient History'), findsOneWidget);
    expect(find.text('Reena'), findsOneWidget);
    expect(find.text('9898989898'), findsOneWidget);
    expect(find.text('2 visits at your clinic'), findsOneWidget);
    // Summary chips render as icon + count (no text labels); the
    // 'Completed' text below comes from the completed visit's status chip.
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
    expect(find.text('Cancelled'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('timeline shows each visit with symptoms and current badge', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      appointments: [
        appointmentBasic(
          appointmentId: 'APT_H1',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-07-01',
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.completed,
          symptoms: 'Fever and body ache',
        ),
        appointmentBasic(
          appointmentId: 'APT_H2',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-08-01',
          appointmentTime: '11:00 AM',
          status: AppointmentStatus.upcoming,
          symptoms: 'Recurring headache',
        ),
      ],
      highlightId: 'APT_H2',
    );

    // Both visits and both symptom notes are on the timeline. Dates render
    // in the app-wide dd-MM-yyyy display format.
    expect(find.text('01-07-2026'), findsOneWidget);
    expect(find.text('01-08-2026'), findsOneWidget);
    expect(find.text('Fever and body ache'), findsOneWidget);
    expect(find.text('Recurring headache'), findsOneWidget);
    // Newest-first numbering: the most recent visit is #1, the older #2.
    expect(find.text('Visit 1'), findsOneWidget);
    expect(find.text('Visit 2'), findsOneWidget);
    final visit1Y = tester.getTopLeft(find.text('Visit 1')).dy;
    final visit2Y = tester.getTopLeft(find.text('Visit 2')).dy;
    expect(visit1Y, lessThan(visit2Y));
    // Only the highlighted (tapped) visit is flagged Current.
    expect(find.text('Current'), findsOneWidget);

    // Date-descending order: the August (newest) visit renders above July.
    final julyY = tester.getTopLeft(find.text('01-07-2026')).dy;
    final augY = tester.getTopLeft(find.text('01-08-2026')).dy;
    expect(augY, lessThan(julyY));

    await _settleAnimations(tester);
  });

  testWidgets('same-day visits sort by real time, not string order', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      appointments: [
        // Lexically "10:00 PM" sorts before "2:00 PM" — the timeline
        // must instead show the earlier 2:00 PM visit first.
        appointmentBasic(
          appointmentId: 'APT_T3',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-08-08',
          appointmentTime: '10:00 PM',
          status: AppointmentStatus.completed,
        ),
        appointmentBasic(
          appointmentId: 'APT_T2',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-08-08',
          appointmentTime: '2:00 PM',
          status: AppointmentStatus.completed,
        ),
        appointmentBasic(
          appointmentId: 'APT_T1',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-08-08',
          appointmentTime: '9:00 AM',
          status: AppointmentStatus.completed,
        ),
      ],
    );

    // All three date labels are identical, so identify each visit card by
    // its unique appointment id's rendered time chip is ambiguous — instead
    // assert the vertical order of the time texts directly. Newest-first:
    // the 10:00 PM (latest time) visit sits on top, the 9:00 AM at bottom.
    final nineY = tester.getTopLeft(find.text('9:00 AM')).dy;
    final twoY = tester.getTopLeft(find.text('2:00 PM')).dy;
    final tenY = tester.getTopLeft(find.text('10:00 PM')).dy;
    expect(tenY, lessThan(twoY));
    expect(twoY, lessThan(nineY));

    await _settleAnimations(tester);
  });

  testWidgets('card shows all data on a narrow screen without overflow or '
      'truncation', (tester) async {
    // Small phone (320dp wide) — the old layout squeezed date + time +
    // consultation type + status into one row and hid data. The redesigned
    // card must render every field on its own full-width row with no
    // overflow exceptions.
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: PatientHistoryScreen(
          appointments: [
            appointmentBasic(
              appointmentId: 'APT_N1',
              patientName: 'Narrow Screen Patient',
              patientPhone: '9876543210',
              appointmentDate: '2026-08-08',
              appointmentTime: '10:30 AM',
              status: AppointmentStatus.upcoming,
              consultationType: 'video',
              symptoms:
                  'Severe recurring migraine with nausea and light '
                  'sensitivity that has been bothering the patient for the '
                  'past three weeks',
            ),
          ],
          // Highlighted so the Visit # + Current two-chip row is exercised
          // at the narrow width too (the only row with any horizontal
          // contention).
          highlightId: 'APT_N1',
        ),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);

    // No RenderFlex overflow on the narrow screen.
    expect(tester.takeException(), isNull);

    // Every field renders — nothing hidden or squeezed away.
    expect(find.text('08-08-2026'), findsOneWidget);
    expect(find.text('Visit 1'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('10:30 AM'), findsOneWidget);
    // The consultation type renders as the card's full-width row.
    expect(find.text('Video Consultation'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.textContaining('Severe recurring migraine'), findsOneWidget);
  });

  testWidgets('timeline renders a single appointment without a Current badge', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      appointments: [
        appointmentBasic(
          appointmentId: 'APT_ONLY',
          patientName: 'Solo',
          patientPhone: '9000000000',
          appointmentDate: '2026-08-08',
          appointmentTime: '2:00 PM',
          status: AppointmentStatus.pending,
          consultationType: 'clinic',
        ),
      ],
    );

    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('08-08-2026'), findsOneWidget);
    // The consultation type renders as the card's full-width row.
    expect(find.text('In-Clinic Visit'), findsOneWidget);
    expect(find.text('Current'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('each visit card shows its own consultation type, hidden for '
      'legacy rows', (tester) async {
    await pumpHistory(
      tester,
      appointments: [
        // Modern rows carry a stored type → the full-width row renders.
        appointmentBasic(
          appointmentId: 'APT_CT1',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-07-01',
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.completed,
          consultationType: 'tele',
        ),
        appointmentBasic(
          appointmentId: 'APT_CT2',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-08-01',
          appointmentTime: '11:00 AM',
          status: AppointmentStatus.upcoming,
          consultationType: 'clinic',
        ),
        // Legacy row without a stored type → no row, no layout jump.
        appointmentBasic(
          appointmentId: 'APT_CT3',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-06-01',
          appointmentTime: '9:00 AM',
          status: AppointmentStatus.completed,
        ),
      ],
    );

    expect(find.text('Tele Consultation'), findsOneWidget);
    expect(find.text('In-Clinic Visit'), findsOneWidget);
    // 'Consultation' label appears once per typed visit.
    expect(find.text('Consultation'), findsNWidgets(2));
    expect(find.text('Video Consultation'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets(
    'tapping a visit card opens the details sheet without an All Prescriptions action',
    (tester) async {
      await pumpHistory(
        tester,
        appointments: [
          appointmentBasic(
            appointmentId: 'APT_DET',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: '2026-07-01',
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.completed,
            prescriptionUrls: const ['https://example.com/rx1.jpg'],
          ),
        ],
      );

      await tester.tap(find.text('Visit 1'));
      await tester.pumpAndSettle();

      // The same details sheet as tapping an appointment on the
      // Appointments tab — full info plus the patient's call number.
      expect(find.text('Appointment ID'), findsOneWidget);
      expect(find.text('APT_DET'), findsOneWidget);
      expect(find.text('Call Now'), findsOneWidget);

      // The All Prescriptions action is NOT inside the modal anymore — it
      // lives on the page bottom. Scope to the sheet's scroll view (the
      // page behind it also has an All Prescriptions button).
      final sheetScroll = find.ancestor(
        of: find.byKey(const ValueKey('history_details_close')),
        matching: find.byType(SingleChildScrollView),
      );
      expect(
        find.descendant(
          of: sheetScroll,
          matching: find.text('All Prescriptions'),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('history_details_close')));
      await tester.pumpAndSettle();
      expect(find.text('Appointment ID'), findsNothing);

      await _settleAnimations(tester);
    },
  );

  testWidgets('details sheet shows the doctor Cancel / Mark Completed '
      'actions for an Upcoming visit', (tester) async {
    await pumpHistory(
      tester,
      appointments: [
        appointmentBasic(
          appointmentId: 'APT_ACT_1',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-07-01',
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
        ),
      ],
    );

    await tester.tap(find.text('Visit 1'));
    await tester.pumpAndSettle();

    // The same compact doctor actions as the Appointments-tab sheet: mark
    // the consultation complete or cancel it right from the history sheet.
    expect(find.text('Mark Completed'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history_details_close')));
    await tester.pumpAndSettle();
    await _settleAnimations(tester);
  });

  testWidgets(
    'All Prescriptions button sits on the page bottom and opens the swipeable gallery newest-first',
    (tester) async {
      await pumpHistory(
        tester,
        appointments: [
          appointmentBasic(
            appointmentId: 'APT_RX1',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: '2026-07-01',
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.completed,
            prescriptionUrls: const [
              'https://example.com/rx1.jpg',
              'https://example.com/rx2.jpg',
            ],
          ),
          appointmentBasic(
            appointmentId: 'APT_RX2',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: '2026-08-01',
            appointmentTime: '11:00 AM',
            status: AppointmentStatus.completed,
            prescriptionUrls: const ['https://example.com/rx3.jpg'],
          ),
        ],
      );

      // Button is on the page itself (not inside the card's modal).
      expect(
        find.byKey(const ValueKey('all_prescriptions_button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('all_prescriptions_button')));
      await tester.pumpAndSettle();

      // Fullscreen gallery: counter starts at 1 / 3 and the first image is
      // the NEWEST visit (Visit 1 = 01-08-2026), matching the timeline.
      expect(find.text('1 / 3'), findsOneWidget);
      // Gallery pages use the shared pinch + double-tap zoom widget, with
      // the zoom hint next to the counter.
      expect(find.byType(ZoomableImage), findsOneWidget);
      expect(find.text(AppConstants.zoomHintText), findsOneWidget);
      expect(find.text('Visit 1 • 01-08-2026 • 11:00 AM'), findsOneWidget);

      // Swipe left → second image (Visit 2 = 01-07-2026).
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('Visit 2 • 01-07-2026 • 10:00 AM'), findsOneWidget);

      // Swipe left again → third image (still Visit 2's second photo).
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('Visit 2 • 01-07-2026 • 10:00 AM'), findsOneWidget);

      // Close returns to the timeline.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsNothing);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'tapping a timeline card thumbnail opens the gallery at that exact image',
    (tester) async {
      await pumpHistory(
        tester,
        appointments: [
          // Visit 1 (newest): 1 image. Visit 2 (older): 2 images.
          appointmentBasic(
            appointmentId: 'APT_RX_A',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: '2026-08-01',
            appointmentTime: '11:00 AM',
            status: AppointmentStatus.completed,
            prescriptionUrls: const ['https://example.com/a1.jpg'],
          ),
          appointmentBasic(
            appointmentId: 'APT_RX_B',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: '2026-07-01',
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.completed,
            prescriptionUrls: const [
              'https://example.com/b1.jpg',
              'https://example.com/b2.jpg',
            ],
          ),
        ],
      );

      // Newest-first: card 0 = Visit 1 (1 image), card 1 = Visit 2 (2
      // images). Tap Visit 2's SECOND thumbnail → global image index 2
      // (a1, b1, b2) → the gallery opens at 3 / 3.
      final visit2Card = find.byType(AppointmentInfoCard).at(1);
      final thumbnails = find.descendant(
        of: visit2Card,
        matching: find.byType(Image),
      );
      expect(thumbnails, findsNWidgets(2));
      await tester.tap(thumbnails.at(1));
      await tester.pumpAndSettle();

      // Opened the SAME fullscreen gallery, positioned at the tapped image.
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('Visit 2 • 01-07-2026 • 10:00 AM'), findsOneWidget);

      // Swiping left is disabled at the last image; swiping right goes
      // back through the gallery (b1, then a1).
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsNothing);

      await _settleAnimations(tester);
    },
  );

  // ── Doctor-initiated Reschedule in the details sheet ──────────────

  /// Pumps the history with an [AppointmentController] registered and the
  /// reschedule route stubbed, so the sheet's Reschedule action can be
  /// exercised end-to-end.
  Future<void> pumpHistoryWithReschedule(
    WidgetTester tester, {
    required List<AppointmentModel> appointments,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _TestAppointmentController(),
      permanent: true,
    );
    Get.put<DoctorController>(DoctorController(), permanent: true);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: PatientHistoryScreen(appointments: appointments),
        getPages: [
          GetPage(
            name: AppRoutes.rescheduleAppointment,
            page: () => const _RescheduleStub(),
          ),
        ],
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);
  }

  testWidgets(
    'details sheet shows a Reschedule action for a Pending visit and opens '
    'the reschedule screen from it (doctor-initiated)',
    (tester) async {
      await pumpHistoryWithReschedule(
        tester,
        appointments: [
          appointmentBasic(
            appointmentId: 'APT_DOC_RS',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: _futureKey(1),
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.pending,
            doctorName: 'Dr. Alice Green',
            doctorPlaceId: 'place_doc_1',
          ),
        ],
      );

      // Open the details sheet from the visit card.
      await tester.tap(find.text('Visit 1'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('doctor_patient_history_reschedule')),
        findsOneWidget,
      );

      // Tapping it closes the sheet and shows the Pending confirmation
      // dialog (doctor-initiated copy) BEFORE the reschedule screen.
      await tester.tap(
        find.byKey(const ValueKey('doctor_patient_history_reschedule')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reschedule pending appointment?'), findsOneWidget);
      expect(find.textContaining('still pending confirmation'), findsOneWidget);
      expect(find.text('RESCHEDULE_STUB'), findsNothing);

      // Confirming proceeds to the doctor-initiated reschedule screen.
      await tester.tap(
        find.byKey(const ValueKey('pending_reschedule_confirm_proceed')),
      );
      await tester.pumpAndSettle();

      expect(find.text('RESCHEDULE_STUB'), findsOneWidget);
      await _settleAnimations(tester);
    },
  );

  testWidgets('declining the Pending confirmation keeps the history screen', (
    tester,
  ) async {
    await pumpHistoryWithReschedule(
      tester,
      appointments: [
        appointmentBasic(
          appointmentId: 'APT_DOC_KEEP',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: _futureKey(1),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.pending,
          doctorName: 'Dr. Alice Green',
          doctorPlaceId: 'place_doc_1',
        ),
      ],
    );

    await tester.tap(find.text('Visit 1'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('doctor_patient_history_reschedule')),
    );
    await tester.pumpAndSettle();

    // Declining closes the dialog and stays on the history page.
    await tester.tap(
      find.byKey(const ValueKey('pending_reschedule_confirm_cancel')),
    );
    await tester.pumpAndSettle();

    expect(find.text('RESCHEDULE_STUB'), findsNothing);
    expect(find.text('Reschedule pending appointment?'), findsNothing);
    expect(find.text('Patient History'), findsOneWidget);
    await _settleAnimations(tester);
  });

  testWidgets('details sheet hides Reschedule for a Completed visit', (
    tester,
  ) async {
    await pumpHistoryWithReschedule(
      tester,
      appointments: [
        appointmentBasic(
          appointmentId: 'APT_DOC_DONE',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-07-01',
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.completed,
        ),
      ],
    );

    await tester.tap(find.text('Visit 1'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('doctor_patient_history_reschedule')),
      findsNothing,
    );
    await _settleAnimations(tester);
  });

  testWidgets(
    'details sheet hides Reschedule for an Upcoming visit whose time has '
    'passed (effective status Completed)',
    (tester) async {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final pastKey =
          '${past.year}-${past.month.toString().padLeft(2, '0')}'
          '-${past.day.toString().padLeft(2, '0')}';
      await pumpHistoryWithReschedule(
        tester,
        appointments: [
          appointmentBasic(
            appointmentId: 'APT_DOC_LAPSED',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: pastKey,
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.upcoming,
          ),
        ],
      );

      await tester.tap(find.text('Visit 1'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('doctor_patient_history_reschedule')),
        findsNothing,
      );
      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'details sheet shows the visit fee/payment from the doctor\'s payment '
    'map',
    (tester) async {
      await pumpHistory(
        tester,
        appointments: [
          appointmentBasic(
            appointmentId: 'APT_DOC_PAY',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: '2026-08-01',
            appointmentTime: '10:00 AM',
            // Upcoming (not Pending) so the only "Pending" on the sheet is
            // the payment chip — the status header would otherwise collide.
            status: AppointmentStatus.upcoming,
          ),
        ],
      );

      // Seed the payment map the Appointments tab uses — the sheet must
      // show the same fee/status the card would.
      Get.find<DoctorController>().paymentsByAppointment.value = {
        'APT_DOC_PAY': PaymentModel(
          appointmentId: 'APT_DOC_PAY',
          patientId: 'user_p',
          amount: 800,
          paymentStatus: 'Pending',
          paymentMethod: 'offline',
        ),
      };

      await tester.tap(find.text('Visit 1'));
      await tester.pumpAndSettle();

      expect(find.text('₹800'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Offline (Clinic)'), findsOneWidget);
      await _settleAnimations(tester);
    },
  );

  testWidgets('All Prescriptions shows an empty state when there are none', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      appointments: [
        appointmentBasic(
          appointmentId: 'APT_NORX',
          patientName: 'Reena',
          patientPhone: '9898989898',
          appointmentDate: '2026-08-01',
          appointmentTime: '11:00 AM',
          status: AppointmentStatus.upcoming,
        ),
      ],
    );

    // The bottom button is still present (there are visits) and opens the
    // gallery, which shows the friendly empty state.
    await tester.tap(find.byKey(const ValueKey('all_prescriptions_button')));
    await tester.pumpAndSettle();

    expect(find.text('No prescriptions yet'), findsOneWidget);

    await _settleAnimations(tester);
  });

  // ── Share / Export CSV ────────────────────────────────────────────
  group('share/export the timeline as CSV', () {
    testWidgets('export button shares a CSV of every visit newest-first', (
      tester,
    ) async {
      final (shareCalls, _) = mockExportPlatform(tester);
      await pumpHistory(
        tester,
        appointments: [
          appointmentBasic(
            appointmentId: 'APT_EX1',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: '2026-07-01',
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.completed,
            consultationType: 'clinic',
            symptoms: 'Fever and body ache',
          ),
          appointmentBasic(
            appointmentId: 'APT_EX2',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: '2026-08-01',
            appointmentTime: '11:00 AM',
            status: AppointmentStatus.upcoming,
            consultationType: 'video',
            prescriptionUrls: const ['https://example.com/rx1.jpg'],
          ),
        ],
      );

      await tester.tap(find.byKey(const Key('patient_history_export')));
      await tester.pump();
      await settleExport(tester, done: () => shareCalls.isNotEmpty);

      expect(shareCalls, isNotEmpty);
      final path = sharedFilePath(shareCalls);
      expect(path, contains('patient_history_'));
      expect(path, endsWith('.csv'));
      final args = shareCalls.last.arguments as Map<dynamic, dynamic>;
      expect(args['subject'], 'Patient history — Reena');
      // Newest-first timeline order (August visit first), the app-wide
      // dd-MM-yyyy dates, and the role-neutral visit columns.
      final csv = File(path).readAsStringSync();
      expect(
        csv,
        startsWith(
          'Date,Time,Status,Consultation,Symptoms,Prescriptions,Appointment ID',
        ),
      );
      expect(
        csv.indexOf('01-08-2026,11:00 AM,Upcoming,Video Consultation'),
        lessThan(csv.indexOf('01-07-2026,10:00 AM,Completed,In-Clinic Visit')),
      );
      expect(csv, contains(',1,APT_EX2'));
      expect(csv, contains(',0,APT_EX1'));
      await _settleAnimations(tester);
    });

    testWidgets('export button is hidden when there are no visits', (
      tester,
    ) async {
      await pumpHistory(tester, appointments: []);

      expect(find.byKey(const Key('patient_history_export')), findsNothing);
      await _settleAnimations(tester);
    });

    testWidgets('a failing temp-dir write surfaces the Export failed '
        'snackbar', (tester) async {
      final (shareCalls, _) = mockExportPlatform(
        tester,
        failPathProvider: true,
      );
      await pumpHistory(
        tester,
        appointments: [
          appointmentBasic(
            appointmentId: 'APT_EX3',
            patientName: 'Reena',
            patientPhone: '9898989898',
            appointmentDate: '2026-08-01',
            appointmentTime: '11:00 AM',
            status: AppointmentStatus.upcoming,
          ),
        ],
      );

      await tester.tap(find.byKey(const Key('patient_history_export')));
      await tester.pumpAndSettle();

      expect(find.text('Export failed'), findsOneWidget);
      expect(shareCalls, isEmpty);
      // Let the snackbar's auto-dismiss timer fire so no timer leaks.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await _settleAnimations(tester);
    });
  });
}
