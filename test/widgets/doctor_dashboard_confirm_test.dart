import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/doctor_controller.dart';
import 'package:DrsListing/controllers/notification_center_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/models/unavailable_range.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/doctor/doctor_dashboard_screen.dart';
import 'package:DrsListing/screens/doctor/doctor_main_shell.dart';
import 'package:DrsListing/screens/profile/payment_history_screen.dart';

import '../helpers/test_data.dart';

/// Test-only AuthController that skips the secure-storage platform channel
/// (mirrors the pattern in payment_history_screen_test.dart) so the doctor
/// shell's role guard sees a logged-in doctor.
class _ShellTestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Test double that skips Supabase calls but records status updates so we
/// can assert exactly what the Confirm action requested.
class _TestDoctorController extends DoctorController {
  final List<String> updatedIds = [];
  final List<String> updatedStatuses = [];

  @override
  Future<void> updateAppointmentStatus(
    String appointmentId,
    String status,
  ) async {
    updatedIds.add(appointmentId);
    updatedStatuses.add(status);
  }
}

/// Lets the flutter_animate effects on the dashboard run to completion (the
/// header, cards and timeline use fadeIn/slideY backed by Future.delayed
/// timers, which would otherwise trip the "Timer is still pending" guard).
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// Today's appointment date key (yyyy-MM-dd). Recent Activity only shows
/// today + yesterday, so tests must use a dynamic date.
String _dateKey(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Future<_TestDoctorController> _pumpDashboard(
  WidgetTester tester,
  List<AppointmentModel> appointments,
) async {
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Get.reset();
  final controller = _TestDoctorController();
  controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
  controller.appointments.assignAll(appointments);
  Get.put<DoctorController>(controller, permanent: true);

  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: const DoctorDashboardScreen(),
    ),
  );
  await tester.pump();
  await _settleAnimations(tester);
  return controller;
}

void main() {
  testWidgets('Stats grid shows the Payments count and Income card with the '
      'Paid vs Pending breakdown', (tester) async {
    final controller = await _pumpDashboard(tester, []);

    // Default state: no payments loaded → zeroed cards.
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('₹0'), findsOneWidget);
    // Breakdown lines render (zeroed): 'Paid ₹0' + 'Pending ₹0'.
    expect(find.text('Paid ₹0'), findsOneWidget);
    expect(find.text('Pending ₹0'), findsOneWidget);

    // Simulate a loaded payment summary (what loadPayments would compute):
    // 7 payment rows — Paid ₹8,000 + ₹4,500 count as income; Pending
    // ₹3,000 shows as what's still owed; Refunded/Failed never appear.
    controller.paymentCount.value = 7;
    controller.paidIncome.value = 12500;
    controller.pendingIncome.value = 3000;
    await tester.pump();

    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('₹12500'), findsOneWidget);
    // The breakdown: big value '₹12500' + line 'Paid ₹12500' are distinct
    // Texts (amounts never collide), and Pending shows the outstanding sum.
    expect(find.text('Paid ₹12500'), findsOneWidget);
    expect(find.text('Pending ₹3000'), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets('Payments and Income cards span the full grid width, stacked '
      'one after the other', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Get.reset();
    final controller = _TestDoctorController();
    controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
    controller.paymentCount.value = 7;
    controller.paidIncome.value = 12500;
    controller.pendingIncome.value = 3000;
    Get.put<DoctorController>(controller, permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const DoctorDashboardScreen(),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);

    // Each card's InkWell is the tappable card surface.
    final todayW = tester
        .getRect(
          find.ancestor(
            of: find.text('Today'),
            matching: find.byType(InkWell),
          ).first,
        )
        .width;
    final paymentsRect = tester.getRect(
      find.ancestor(
        of: find.text('Payments'),
        matching: find.byType(InkWell),
      ).first,
    );
    final incomeRect = tester.getRect(
      find.ancestor(
        of: find.text('Income'),
        matching: find.byType(InkWell),
      ).first,
    );

    // The money cards are roughly double the width of a half-width count
    // card (they span the whole grid), and sit stacked next by next.
    expect(paymentsRect.width, greaterThan(todayW * 1.6));
    expect(incomeRect.width, greaterThan(todayW * 1.6));
    expect(paymentsRect.width, closeTo(incomeRect.width, 1));
    expect(incomeRect.top, greaterThanOrEqualTo(paymentsRect.bottom - 1));

    await _settleAnimations(tester);
  });

  testWidgets('an empty clinic payment history shows the doctor empty state '
      'and its CTA pops back to the dashboard', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Get.reset();
    final controller = _TestDoctorController();
    controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
    Get.put<DoctorController>(controller, permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        getPages: [
          GetPage(
            name: AppRoutes.doctorPaymentHistory,
            page: () => PaymentHistoryScreen(
              subtitle: 'Fees collected at your clinic',
              loadPayments: () async => const [],
            ),
          ),
        ],
        home: const DoctorDashboardScreen(),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);

    // Payments → the empty clinic history shows the DOCTOR empty state
    // (never the patient-flavored one).
    await tester.tap(find.text('Payments'));
    await tester.pumpAndSettle();

    expect(find.text('No fees collected yet'), findsOneWidget);
    expect(find.text('No payments yet'), findsNothing);
    expect(find.text('View Appointments'), findsOneWidget);

    // The CTA pops back to the dashboard (no shell is mounted here, so
    // the tab switch is a no-op — the shell-level switch is covered by
    // its own test below).
    await tester.tap(find.text('View Appointments'));
    await tester.pumpAndSettle();

    expect(find.text('No fees collected yet'), findsNothing);
    expect(find.text('Recent Activity'), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets('DoctorMainShell.switchToTab selects the Appointments tab on '
      'the mounted shell', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Get.reset();
    final auth = _ShellTestAuthController();
    auth.currentUser.value = userDoctor(id: 'user_doc_1');
    Get.put<AuthController>(auth, permanent: true);
    final controller = _TestDoctorController();
    controller.currentDoctor.value = doctorBasic(placeId: 'place_shell_1');
    Get.put<DoctorController>(controller, permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const DoctorMainShell(),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);

    // Starts on the Dashboard tab.
    expect(DoctorMainShell.activeTabIndex, 0);

    // The Payment History empty-state CTA path: switch the (already open)
    // shell to the Appointments tab.
    DoctorMainShell.switchToTab(DoctorMainShell.appointmentsTab);
    await tester.pump();
    await _settleAnimations(tester);

    expect(DoctorMainShell.activeTabIndex, DoctorMainShell.appointmentsTab);
  });

  testWidgets('Tapping the Payments stat card opens the clinic payment '
      'history', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Get.reset();
    final controller = _TestDoctorController();
    controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
    Get.put<DoctorController>(controller, permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        // Register the dashboard's real destination so the tap navigates
        // (the loader is a fixture — no Supabase needed in the test).
        getPages: [
          GetPage(
            name: AppRoutes.doctorPaymentHistory,
            page: () => PaymentHistoryScreen(
              subtitle: 'Fees collected at your clinic',
              loadPayments: () async => [
                PaymentModel(
                  appointmentId: 'APT_PAY_1',
                  patientId: 'user_1',
                  patientName: 'Clinic Patient',
                  paymentStatus: 'Paid',
                  paymentMethod: 'offline',
                  amount: 800,
                ),
              ],
            ),
          ),
        ],
        home: const DoctorDashboardScreen(),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);

    // Tap the Payments stat card → the doctor payment history opens with
    // the clinic-flavored header and the payment row led by patient name.
    await tester.tap(find.text('Payments'));
    await tester.pumpAndSettle();

    expect(find.text('Fees collected at your clinic'), findsOneWidget);
    expect(find.text('Clinic Patient'), findsOneWidget);
    // ₹800 shows twice: the summary card's settled big figure + the row.
    expect(find.text('₹800'), findsNWidgets(2));

    await _settleAnimations(tester);
  });

  testWidgets('Dashboard header shows the notification bell', (tester) async {
    await _pumpDashboard(tester, []);

    // The bell sits in the header's top row, next to the doctor info.
    expect(
      find.byKey(const ValueKey('notification_bell')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets('Dashboard bell shows the unread notification badge', (
    tester,
  ) async {
    await _pumpDashboard(tester, []);

    // No unread -> no badge.
    final bell = find.byKey(const ValueKey('notification_bell'));
    expect(
      find.descendant(of: bell, matching: find.text('0')),
      findsNothing,
    );

    // Simulate an unread push history -> the badge appears with the count.
    Get.find<NotificationCenterController>().unreadCount.value = 3;
    await tester.pump();

    expect(
      find.descendant(of: bell, matching: find.text('3')),
      findsOneWidget,
    );

    await _settleAnimations(tester);
  });

  testWidgets('Today\'s Overview \'Booked\' pill counts every non-cancelled '
      'appointment (slot only frees after Cancelled)', (tester) async {
    final todayKey = _dateKey(DateTime.now());
    await _pumpDashboard(tester, [
      appointmentBasic(
        appointmentId: 'APT_BOOKED_PENDING',
        patientName: 'Pend',
        appointmentDate: todayKey,
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.pending,
        doctorPlaceId: 'place_dash_1',
      ),
      appointmentBasic(
        appointmentId: 'APT_BOOKED_UPCOMING',
        patientName: 'Upcom',
        appointmentDate: todayKey,
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
        doctorPlaceId: 'place_dash_1',
      ),
      appointmentBasic(
        appointmentId: 'APT_BOOKED_COMPLETED',
        patientName: 'Doner',
        appointmentDate: todayKey,
        appointmentTime: '11:00 AM',
        status: AppointmentStatus.completed,
        doctorPlaceId: 'place_dash_1',
      ),
      appointmentBasic(
        appointmentId: 'APT_BOOKED_CANCELLED',
        patientName: 'Cxed',
        appointmentDate: todayKey,
        appointmentTime: '12:00 PM',
        status: AppointmentStatus.cancelled,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    // Booked = Pending + Upcoming + Completed (3) — only the Cancelled
    // appointment frees its slot, so it is NOT counted.
    expect(find.text('Booked'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // The Total pill and the Recent-Activity Today badge both show all 4
    // of today's records (including the cancelled one).
    expect(find.text('4'), findsNWidgets(2));

    await _settleAnimations(tester);
  });

  testWidgets('Pending appointment in Recent Activity shows a Confirm chip; '
      'accepting moves it to Upcoming', (tester) async {
    final controller = await _pumpDashboard(tester, [
      appointmentBasic(
        appointmentId: 'APT_DASH_PENDING',
        patientName: 'Timeline Patient',
        appointmentDate: _dateKey(DateTime.now()),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.pending,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    // The Recent Activity card shows the patient + a Confirm chip.
    expect(find.text('Timeline Patient'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);

    // Open the confirm dialog from the timeline chip.
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Confirm Appointment'), findsOneWidget);
    expect(find.text('Not Now'), findsOneWidget);

    // Accept the booking.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pump();

    expect(controller.updatedIds, ['APT_DASH_PENDING']);
    expect(controller.updatedStatuses, [AppointmentStatus.upcoming]);

    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('Upcoming timeline row has no Confirm chip', (tester) async {
    final controller = await _pumpDashboard(tester, [
      appointmentBasic(
        appointmentId: 'APT_DASH_UPCOMING',
        patientName: 'Plain Upcoming',
        appointmentDate: _dateKey(DateTime.now()),
        appointmentTime: '11:00 AM',
        status: AppointmentStatus.upcoming,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    expect(find.text('Plain Upcoming'), findsOneWidget);
    // 'Upcoming' appears in several dashboard surfaces (Today pill, analytics
    // bar, timeline chip) — the important check is that the timeline row has
    // no Confirm action for non-Pending appointments.
    expect(find.text('Upcoming'), findsWidgets);
    expect(find.text('Confirm'), findsNothing);

    await _settleAnimations(tester);
    expect(controller.updatedIds, isEmpty);
  });

  testWidgets('Recent Activity shows only today + yesterday records', (
    tester,
  ) async {
    final oldKey = _dateKey(DateTime.now().subtract(const Duration(days: 3)));
    final yesterdayKey = _dateKey(
      DateTime.now().subtract(const Duration(days: 1)),
    );

    final controller = await _pumpDashboard(tester, [
      appointmentBasic(
        appointmentId: 'APT_DASH_OLD',
        patientName: 'Old Patient',
        appointmentDate: oldKey,
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.completed,
        doctorPlaceId: 'place_dash_1',
      ),
      appointmentBasic(
        appointmentId: 'APT_DASH_YESTERDAY',
        patientName: 'Yesterday Patient',
        appointmentDate: yesterdayKey,
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.completed,
        doctorPlaceId: 'place_dash_1',
      ),
      appointmentBasic(
        appointmentId: 'APT_DASH_TODAY',
        patientName: 'Today Patient',
        appointmentDate: _dateKey(DateTime.now()),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.upcoming,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    // Today's + yesterday's records appear in the timeline…
    expect(find.text('Today Patient'), findsOneWidget);
    expect(find.text('Yesterday Patient'), findsOneWidget);
    // …but a record from 3 days ago does not.
    expect(find.text('Old Patient'), findsNothing);

    // The timeline is grouped under Today / Yesterday section headers.
    expect(find.byKey(const ValueKey('activity_group_today')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity_group_yesterday')),
      findsOneWidget,
    );

    await _settleAnimations(tester);
    expect(controller.updatedIds, isEmpty);
  });

  testWidgets('A busy Today (>= 10) does not starve the Yesterday section', (
    tester,
  ) async {
    final yesterdayKey = _dateKey(
      DateTime.now().subtract(const Duration(days: 1)),
    );

    // 12 appointments today + 1 yesterday: both sections must render,
    // because each day is capped independently (10 per group).
    final todayAppts = List.generate(
      12,
      (i) => appointmentBasic(
        appointmentId: 'APT_BUSY_$i',
        patientName: 'Busy Today $i',
        appointmentDate: _dateKey(DateTime.now()),
        appointmentTime: '09:0$i AM',
        status: AppointmentStatus.upcoming,
        doctorPlaceId: 'place_dash_1',
      ),
    );
    await _pumpDashboard(tester, [
      ...todayAppts,
      appointmentBasic(
        appointmentId: 'APT_BUSY_YESTERDAY',
        patientName: 'Busy Yesterday Patient',
        appointmentDate: yesterdayKey,
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.completed,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    // Today group is capped at 10 (not 12)…
    expect(find.text('Busy Today 11'), findsNothing);
    // …and yesterday still gets its header + row.
    expect(find.byKey(const ValueKey('activity_group_today')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity_group_yesterday')),
      findsOneWidget,
    );
    expect(find.text('Busy Yesterday Patient'), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets(
    'Recent Activity hides the Yesterday header when only today has records',
    (tester) async {
      await _pumpDashboard(tester, [
        appointmentBasic(
          appointmentId: 'APT_DASH_TODAY_ONLY',
          patientName: 'Only Today Patient',
          appointmentDate: _dateKey(DateTime.now()),
          appointmentTime: '09:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ]);

      // Today group header shows, Yesterday group header does not.
      expect(
        find.byKey(const ValueKey('activity_group_today')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('activity_group_yesterday')),
        findsNothing,
      );

      await _settleAnimations(tester);
    },
  );

  testWidgets('Recent Activity still shows the empty state when there are no '
      'today/yesterday records', (tester) async {
    await _pumpDashboard(tester, [
      appointmentBasic(
        appointmentId: 'APT_DASH_OLD_ONLY',
        patientName: 'Only Old Patient',
        appointmentDate: _dateKey(
          DateTime.now().subtract(const Duration(days: 3)),
        ),
        appointmentTime: '09:00 AM',
        status: AppointmentStatus.completed,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    expect(find.text('No recent appointments'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity_group_today')), findsNothing);
    expect(
      find.byKey(const ValueKey('activity_group_yesterday')),
      findsNothing,
    );

    await _settleAnimations(tester);
  });

  testWidgets('Availability section shows the doctor-set unavailable dates', (
    tester,
  ) async {
    final controller = await _pumpDashboard(tester, []);

    // Weekly slots come from Supabase (empty in tests) — the unavailable
    // ranges ride on the doctor object, so set those directly.
    controller.currentDoctor.value = controller.currentDoctor.value!.copyWith(
      unavailableRanges: [
        UnavailableRange(
          start: DateTime(2026, 8, 10),
          end: DateTime(2026, 8, 12),
        ),
      ],
    );
    await tester.pump();

    // Availability section renders both the available-slots header and
    // the unavailable date range the doctor set.
    expect(find.text('Availability'), findsOneWidget);
    expect(find.text('Available time slots'), findsOneWidget);
    expect(find.text('Unavailable dates'), findsOneWidget);
    expect(find.text('10 Aug 2026 – 12 Aug 2026'), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets(
    'the stats grid never overflows on a small phone with a raised '
    'system font scale',
    (tester) async {
      // 393x874 logical (typical phone) with Android's "Large" font scale
      // (1.15). The stat cards live in a content-driven 2-column Wrap, so
      // a raised font scale makes the row grow taller instead of throwing
      // a RenderFlex overflow inside a fixed-height cell — the whole
      // dashboard must stay overflow-free.
      tester.view.physicalSize = const Size(393, 874);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.15;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.platformDispatcher.clearTextScaleFactorTestValue,
      );

      final todayKey = _dateKey(DateTime.now());
      Get.reset();
      final controller = _TestDoctorController();
      controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
      controller.appointments.assignAll([
        appointmentBasic(
          appointmentId: 'APT_SCALE_PENDING',
          patientName: 'Scale Pending Patient',
          appointmentDate: todayKey,
          appointmentTime: '10:30 AM',
          status: AppointmentStatus.pending,
          doctorPlaceId: 'place_dash_1',
        ),
      ]);
      Get.put<DoctorController>(controller, permanent: true);

      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          home: const DoctorDashboardScreen(),
        ),
      );
      await tester.pump();
      await _settleAnimations(tester);

      // No RenderFlex overflow anywhere on the dashboard.
      expect(tester.takeException(), isNull);

      // The stats grid still renders its four cards (Today/Total/Completed/
      // Cancelled) with their labels.
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Total'), findsWidgets);
      expect(find.text('Completed'), findsWidgets);
      expect(find.text('Cancelled'), findsOneWidget);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'the stats grid is content-driven: cards grow past the old 124px cap '
    'at raised font scales instead of scaling down',
    (tester) async {
      // Same phone width as the overflow regression test but a higher font
      // scale (1.3 = Android's "Largest"). The old fixed-height cells
      // (mainAxisExtent: 124) forced a FittedBox to shrink the card content
      // to fit; the content-driven Wrap must instead let the card grow to
      // its intrinsic height — i.e. TALLER than the old cap — with no
      // scaling and no exception.
      tester.view.physicalSize = const Size(393, 874);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.platformDispatcher.clearTextScaleFactorTestValue,
      );

      final todayKey = _dateKey(DateTime.now());
      Get.reset();
      final controller = _TestDoctorController();
      controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
      controller.appointments.assignAll([
        appointmentBasic(
          appointmentId: 'APT_SCALE_UPCOMING',
          patientName: 'Scale Upcoming Patient',
          appointmentDate: todayKey,
          appointmentTime: '10:30 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ]);
      Get.put<DoctorController>(controller, permanent: true);

      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          home: const DoctorDashboardScreen(),
        ),
      );
      await tester.pump();
      await _settleAnimations(tester);

      // No RenderFlex overflow anywhere on the dashboard.
      expect(tester.takeException(), isNull);

      // 'Cancelled' appears only in the stats grid when there are no
      // cancelled appointments. Its nearest SizedBox ancestor is the
      // content-driven grid cell wrapping the card — which must now be
      // TALLER than the old fixed 124px cap (content grew, nothing shrank).
      final cancelled = find.text('Cancelled');
      expect(cancelled, findsOneWidget);
      final cell = find
          .ancestor(of: cancelled, matching: find.byType(SizedBox))
          .first;
      expect(tester.getSize(cell).height, greaterThan(124));

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'Recent Activity cards show all data on a narrow screen without overflow',
    (tester) async {
      // Small phone (320dp wide) — every Recent Activity datum must stay
      // on its own full-width row (Time and Date are never squeezed next
      // to the patient name or the status chip).
      tester.view.physicalSize = const Size(320, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final todayKey = _dateKey(DateTime.now());
      Get.reset();
      final controller = _TestDoctorController();
      controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
      controller.appointments.assignAll([
        appointmentBasic(
          appointmentId: 'APT_NARROW_PENDING',
          patientName: 'Narrow Pending Patient',
          appointmentDate: todayKey,
          appointmentTime: '10:30 AM',
          status: AppointmentStatus.pending,
          doctorPlaceId: 'place_dash_1',
        ),
        appointmentBasic(
          appointmentId: 'APT_NARROW_UPCOMING',
          patientName: 'A Very Long Patient Name That Ellipsizes',
          appointmentDate: todayKey,
          appointmentTime: '2:00 PM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ]);
      Get.put<DoctorController>(controller, permanent: true);

      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          home: const DoctorDashboardScreen(),
        ),
      );
      await tester.pump();
      await _settleAnimations(tester);

      // No RenderFlex overflow anywhere on the narrow screen.
      expect(tester.takeException(), isNull);

      // Both activity cards render their patient names.
      expect(find.text('Narrow Pending Patient'), findsOneWidget);
      expect(
        find.text('A Very Long Patient Name That Ellipsizes'),
        findsOneWidget,
      );
      // Each datum sits on its own row: Time and Date labels + values.
      expect(find.text('Time'), findsNWidgets(2));
      expect(find.text('Date'), findsNWidgets(2));
      expect(find.text('10:30 AM'), findsOneWidget);
      expect(find.text('2:00 PM'), findsOneWidget);
      // Pending card has the full-width Confirm action; the pending chip
      // shows too.
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);

      await _settleAnimations(tester);
    },
  );
}
