import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/payment_history_controller.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/screens/profile/payment_history_screen.dart';
import 'package:DrsListing/services/local_storage_service.dart';
import '../helpers/csv_export_helpers.dart';
import '../helpers/test_data.dart';

/// Fixed clock anchoring the yearly strip's 12-month window AND the
/// quick presets at Aug 15 2026 in tests, so everything (the window
/// Aug 2026 … Sep 2025, "This month" = Aug 1–15, "Last 30 days" =
/// Jul 16 – Aug 15) is deterministic.
DateTime _testClock() => DateTime(2026, 8, 15);

/// Test-only AuthController that skips the secure-storage platform channel.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Minimal, predictable payment row factory.
PaymentModel makePayment({
  String? id = 'pay_1',
  String appointmentId = 'APT1001',
  String? doctorName = 'Dr. Smith',
  String? patientName,
  String? consultationType = 'video',
  String paymentStatus = 'Paid',
  String paymentMethod = 'online',
  double amount = 800,
  String? transactionId = 'TXN123456',
  String? upiId = 'clinic@upi',
  DateTime? paidAt,
}) {
  return PaymentModel(
    id: id,
    appointmentId: appointmentId,
    patientId: 'user_1',
    doctorName: doctorName,
    patientName: patientName,
    consultationType: consultationType,
    paymentStatus: paymentStatus,
    paymentMethod: paymentMethod,
    amount: amount,
    transactionId: transactionId,
    upiId: upiId,
    paidAt: paidAt ?? DateTime(2026, 8, 6, 10, 30),
  );
}

void main() {
  setUp(() async {
    // Fresh prefs per test so a saved payment-history filter never leaks
    // into the next test (the LocalStorageService singleton re-reads the
    // mock store on init).
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService().init();
    Get.reset();
    final auth = Get.put<AuthController>(
      _TestAuthController(),
      permanent: true,
    );
    auth.currentUser.value = userPatient(id: 'user_1', mobile: '9876543210');
  });

  tearDown(() {
    Get.reset();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    PaymentHistoryController? controller,
    Size size = const Size(1400, 1600),
  }) async {
    // Tall surface so the details bottom sheet fits without scrolling
    // (its lower rows would otherwise be below the fold and unbuilt);
    // the default width comfortably covers the four filter-bar chips
    // (horizontal ListViews build lazily).
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    if (controller != null) {
      Get.put(controller, permanent: true);
    }
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const PaymentHistoryScreen(clock: _testClock),
      ),
    );
    // Let the async load() settle (Supabase unavailable in tests →
    // non-fatal) and the header fadeIn animation finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// A controller with three payments spread across three months inside
  /// the 12-month window (Aug/Jul/Jun 2026) — used to exercise the
  /// yearly strip's window total and the quick presets.
  PaymentHistoryController multiMonthController() {
    final controller = PaymentHistoryController();
    controller.payments.value = [
      makePayment(
        id: 'pay_m1',
        appointmentId: 'APT_M1',
        doctorName: 'Dr. Alpha',
        paymentStatus: 'Paid',
        paymentMethod: 'online',
        amount: 800,
        paidAt: DateTime(2026, 8, 6, 10, 30),
      ),
      makePayment(
        id: 'pay_m2',
        appointmentId: 'APT_M2',
        doctorName: 'Dr. Beta',
        paymentStatus: 'Paid',
        paymentMethod: 'online',
        amount: 500,
        paidAt: DateTime(2026, 7, 10, 9, 0),
      ),
      makePayment(
        id: 'pay_m3',
        appointmentId: 'APT_M3',
        doctorName: 'Dr. Gamma',
        paymentStatus: 'Pending',
        paymentMethod: 'offline',
        amount: 300,
        paidAt: DateTime(2026, 6, 15, 12, 0),
      ),
    ];
    return controller;
  }

  /// Doctor-mode pump: the clinic payment history fed by [payments] —
  /// the SAME shared screen as the patient side, driven through its
  /// [PaymentHistoryScreen.loadPayments] path.
  Future<void> pumpDoctorScreen(
    WidgetTester tester,
    List<PaymentModel> payments,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: PaymentHistoryScreen(
          subtitle: 'Fees collected at your clinic',
          clock: _testClock,
          loadPayments: () async => payments,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Three payments: two inside Aug 10–12 2026, one in July 2026.
  PaymentHistoryController rangeController() {
    final controller = PaymentHistoryController();
    controller.payments.value = [
      makePayment(
        id: 'pay_r1',
        appointmentId: 'APT_R1',
        doctorName: 'Dr. Alpha',
        paymentStatus: 'Paid',
        amount: 800,
        paidAt: DateTime(2026, 8, 10, 10, 0),
      ),
      makePayment(
        id: 'pay_r2',
        appointmentId: 'APT_R2',
        doctorName: 'Dr. Beta',
        paymentStatus: 'Paid',
        amount: 500,
        paidAt: DateTime(2026, 8, 12, 9, 0),
      ),
      makePayment(
        id: 'pay_r3',
        appointmentId: 'APT_R3',
        doctorName: 'Dr. Gamma',
        paymentStatus: 'Pending',
        paymentMethod: 'offline',
        amount: 300,
        paidAt: DateTime(2026, 7, 20, 12, 0),
      ),
    ];
    return controller;
  }

  /// Opens the custom-range picker and applies [fromDay]–[toDay] of the
  /// visible month (the picker's current date is pinned to the test
  /// clock, Aug 2026).
  Future<void> applyRange(
    WidgetTester tester,
    String fromDay,
    String toDay,
  ) async {
    await tester.tap(find.text('Custom range'));
    await tester.pumpAndSettle();
    expect(find.text('Select payment date range'), findsOneWidget);
    await tester.tap(find.text(fromDay));
    await tester.pump();
    await tester.tap(find.text(toDay));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  }

  /// Seeds the saved payment-history filter before the screen opens (the
  /// setUp already initialized the LocalStorageService singleton against
  /// the empty mock store).
  Future<void> seedSavedFilter(Map<String, String> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('payment_history_filter', jsonEncode(data));
  }

  testWidgets('shows an empty state when there are no payments', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('No payments yet'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    // No data → no summary card (it only renders above a non-empty list).
    expect(find.text('Payment Summary'), findsNothing);
    expect(find.text('total paid'), findsNothing);
    // The View Appointments CTA is doctor-only.
    expect(find.text('View Appointments'), findsNothing);
  });

  testWidgets('doctor mode shows the clinic-flavored empty state with a '
      'View Appointments action', (tester) async {
    await pumpDoctorScreen(tester, []);
    await tester.pumpAndSettle();

    // Doctor-flavored title + body — no patient text anywhere.
    expect(find.text('No fees collected yet'), findsOneWidget);
    expect(find.text('No payments yet'), findsNothing);
    expect(
      find.text(
        'Consultation fees from your patients — online via UPI or offline '
        'at the clinic — will show up here as they book and settle.',
      ),
      findsOneWidget,
    );
    // The call to action renders in doctor mode…
    expect(find.text('View Appointments'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('doctor_payment_empty_cta')),
      findsOneWidget,
    );

    // …and tapping it is safe even with no shell mounted: the tab switch
    // is a no-op and the back is a no-op on the root route.
    await tester.tap(find.byKey(const ValueKey('doctor_payment_empty_cta')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('doctor mode lists clinic payments led by patient names', (
    tester,
  ) async {
    // Doctor mode: a custom loader replaces the patient controller, the
    // header subtitle is clinic-flavored, and cards lead with the patient.
    // Wide enough for the Aug chip (its badge feeds the ₹2000 count).
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: PaymentHistoryScreen(
          subtitle: 'Fees collected at your clinic',
          clock: _testClock,
          loadPayments: () async => [
            makePayment(
              id: 'pay_d1',
              appointmentId: 'APT_D1',
              patientName: 'Rahul Sharma',
              paymentStatus: 'Pending',
              paymentMethod: 'offline',
              amount: 800,
            ),
            makePayment(
              id: 'pay_d2',
              appointmentId: 'APT_D2',
              patientName: 'Priya Patel',
              paymentStatus: 'Paid',
              paymentMethod: 'online',
              amount: 1200,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Clinic-flavored header + the patient names on the cards.
    expect(find.text('Fees collected at your clinic'), findsOneWidget);
    expect(find.text('Rahul Sharma'), findsOneWidget);
    expect(find.text('Priya Patel'), findsOneWidget);
    // ₹1200 is the settled total (one Paid row), so the summary big figure
    // AND the card show it; ₹800 (one Pending row) only on the card.
    expect(find.text('₹800'), findsOneWidget);
    expect(find.text('₹1200'), findsNWidgets(2));
    expect(find.text('Pending'), findsOneWidget);
    // The income summary leads the list with the Paid vs Pending split.
    expect(find.text('Payment Summary'), findsOneWidget);
    expect(find.text('Paid ₹1200'), findsOneWidget);
    expect(find.text('Pending ₹800'), findsOneWidget);
    expect(find.text('2 payment records'), findsOneWidget);
    // Yearly strip: both payments are in Aug 2026, so the window total
    // and the current-month total are both ₹2000 (800+1200).
    expect(find.text('₹2000'), findsNWidgets(2));
  });

  testWidgets('summary card shows the settled total and Paid vs Pending '
      'split', (tester) async {
    final controller = PaymentHistoryController();
    controller.payments.value = [
      makePayment(
        id: 'pay_s1',
        appointmentId: 'APT_S1',
        doctorName: 'Dr. A',
        paymentStatus: 'Paid',
        amount: 800,
      ),
      makePayment(
        id: 'pay_s2',
        appointmentId: 'APT_S2',
        doctorName: 'Dr. B',
        paymentStatus: 'Paid',
        amount: 500,
      ),
      makePayment(
        id: 'pay_s3',
        appointmentId: 'APT_S3',
        doctorName: 'Dr. C',
        paymentStatus: 'Pending',
        paymentMethod: 'offline',
        amount: 300,
      ),
    ];
    await pumpScreen(tester, controller: controller);

    // Settled figure up front + the breakdown pills.
    expect(find.text('Payment Summary'), findsOneWidget);
    expect(find.text('₹1300'), findsOneWidget);
    expect(find.text('Paid ₹1300'), findsOneWidget);
    expect(find.text('Pending ₹300'), findsOneWidget);
    expect(find.text('3 payment records'), findsOneWidget);
    // The per-card amounts still render (summary + card share ₹800? No —
    // the big figure is the ₹1300 total; each card keeps its own amount).
    expect(find.text('₹800'), findsOneWidget);
    expect(find.text('₹500'), findsOneWidget);
    expect(find.text('₹300'), findsOneWidget);
  });

  testWidgets('shows a loading spinner while the list loads', (tester) async {
    // No logged-in user → load() early-returns without resetting
    // isLoading, so the spinner stays up for the whole test.
    Get.find<AuthController>().currentUser.value = null;
    final controller = PaymentHistoryController();
    controller.isLoading.value = true;
    await pumpScreen(tester, controller: controller);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders payment rows with amount, method and status', (
    tester,
  ) async {
    final controller = PaymentHistoryController();
    controller.payments.value = [
      makePayment(
        id: 'pay_1',
        appointmentId: 'APT1001',
        doctorName: 'Dr. Smith',
        consultationType: 'video',
        paymentStatus: 'Paid',
        paymentMethod: 'online',
        amount: 800,
      ),
      makePayment(
        id: 'pay_2',
        appointmentId: 'APT1002',
        doctorName: 'Dr. Green',
        consultationType: 'clinic',
        paymentStatus: 'Pending',
        paymentMethod: 'offline',
        amount: 1000,
      ),
    ];
    await pumpScreen(tester, controller: controller);

    expect(find.text('Dr. Smith'), findsOneWidget);
    expect(find.text('Dr. Green'), findsOneWidget);
    // Amounts: the summary card's big settled figure repeats the ₹800
    // paid total (one Paid row), so it appears twice; ₹1000 (one Pending
    // row) only on the card — the summary pill is the combined
    // 'Pending ₹1000' string.
    expect(find.text('₹800'), findsNWidgets(2));
    expect(find.text('₹1000'), findsOneWidget);
    // Consultation type labels.
    expect(find.text('Video Consultation'), findsOneWidget);
    expect(find.text('In-Clinic Visit'), findsOneWidget);
    // Method chips.
    expect(find.text('Online (UPI)'), findsOneWidget);
    expect(find.text('Offline (Clinic)'), findsOneWidget);
    // Status chips.
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('tapping a row opens the details sheet with the full record', (
    tester,
  ) async {
    final controller = PaymentHistoryController();
    controller.payments.value = [
      makePayment(
        appointmentId: 'APT1001',
        doctorName: 'Dr. Smith',
        consultationType: 'tele',
        paymentStatus: 'Paid',
        paymentMethod: 'online',
        amount: 500,
        transactionId: 'TXN123456',
        upiId: 'clinic@upi',
        paidAt: DateTime(2026, 8, 6, 10, 30),
      ),
    ];
    await pumpScreen(tester, controller: controller);

    await tester.tap(find.text('Dr. Smith'));
    await tester.pumpAndSettle();

    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('Online (UPI)'), findsWidgets);
    expect(find.text('Appointment ID'), findsOneWidget);
    expect(find.text('APT1001'), findsOneWidget);
    expect(find.text('Transaction ID'), findsOneWidget);
    expect(find.text('TXN123456'), findsOneWidget);
    expect(find.text('UPI ID'), findsOneWidget);
    expect(find.text('clinic@upi'), findsOneWidget);
    expect(find.text('Paid on'), findsOneWidget);
    // The consultation label renders on the card behind the sheet AND in
    // the sheet's detail row.
    expect(find.text('Tele Consultation'), findsNWidgets(2));

    // Close the sheet.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction ID'), findsNothing);
  });

  // ── Filter bar ────────────────────────────────────────────────
  group('the filter bar scopes the history', () {
    testWidgets('renders All / Custom range / Last 30 days / This month '
        'and no month chips', (tester) async {
      await pumpScreen(tester, controller: multiMonthController());

      // The bar is exactly the four scope chips — no 12-month window.
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Custom range'), findsOneWidget);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('Aug 2026'), findsNothing);
      expect(find.text('Jul 2026'), findsNothing);
      expect(find.text('Jun 2026'), findsNothing);
      // Yearly strip inside the summary card: whole 12-month window
      // (800+500+300 = 1600) vs the current month (Aug = 800).
      expect(find.text('Last 12 months'), findsOneWidget);
      expect(find.text('Current month'), findsOneWidget);
      expect(find.text('₹1600'), findsOneWidget);
      // The all-time summary shows the settled total + the Paid/Pending
      // split pills (800+500 paid, 300 pending).
      expect(find.text('₹1300'), findsOneWidget);
      expect(find.text('Paid ₹1300'), findsOneWidget);
      expect(find.text('Pending ₹300'), findsOneWidget);
      // Unfiltered summary keeps the generic title.
      expect(find.text('Payment Summary'), findsOneWidget);
      expect(find.text('3 payment records'), findsOneWidget);
    });

    testWidgets("tapping 'This month' filters the list and scopes the "
        'summary', (tester) async {
      await pumpScreen(tester, controller: multiMonthController());

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();

      // Only August's payment (Aug 6, inside Aug 1–15) remains.
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsNothing);
      expect(find.text('Dr. Gamma'), findsNothing);
      // The summary card is scoped to the range: title shows the span and
      // the record count reflects the filtered list.
      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('1 payment record in 1 – 15 Aug 2026'), findsOneWidget);
      // Summary pills reflect the range only: Paid ₹800, no pending.
      expect(find.text('Paid ₹800'), findsOneWidget);
      expect(find.text('Pending ₹0'), findsOneWidget);
      // The all-time totals are gone once a range is selected.
      expect(find.text('Paid ₹1300'), findsNothing);
      // The filtered-out payments leave the list entirely.
      expect(find.text('Dr. Beta'), findsNothing);
      expect(find.text('Dr. Gamma'), findsNothing);
    });

    testWidgets('tapping the All chip resets the filter', (tester) async {
      await pumpScreen(tester, controller: multiMonthController());

      // Narrow to this month first.
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Beta'), findsNothing);

      // Back to everything.
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      // All three payments are visible again and the summary reverts to
      // the all-time figures.
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Payment Summary'), findsOneWidget);
      expect(find.text('3 payment records'), findsOneWidget);
      // The all-time figures come back with the filter cleared.
      expect(find.text('₹1300'), findsOneWidget);
      expect(find.text('Paid ₹1300'), findsOneWidget);
      expect(find.text('Pending ₹300'), findsOneWidget);
    });

    testWidgets('the filter bar works in doctor mode (loadPayments path)', (
      tester,
    ) async {
      // Doctor mode: a custom loader returns clinic payments across two
      // months; the same four-chip bar renders and filters by range.
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          home: PaymentHistoryScreen(
            subtitle: 'Fees collected at your clinic',
            clock: _testClock,
            loadPayments: () async => [
              makePayment(
                id: 'pay_dm1',
                appointmentId: 'APT_DM1',
                patientName: 'Rahul Sharma',
                paymentStatus: 'Paid',
                amount: 800,
                paidAt: DateTime(2026, 8, 2, 10, 0),
              ),
              makePayment(
                id: 'pay_dm2',
                appointmentId: 'APT_DM2',
                patientName: 'Priya Patel',
                paymentStatus: 'Pending',
                paymentMethod: 'offline',
                amount: 500,
                paidAt: DateTime(2026, 7, 18, 9, 0),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // The bar is exactly the four scope chips — no month chips.
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Custom range'), findsOneWidget);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('Aug 2026'), findsNothing);
      expect(find.text('Jul 2026'), findsNothing);
      // Summary + strip: window total 800+500 = 1300 (Rahul paid in Aug,
      // Priya pending in Jul); current month (Aug) = 800.
      expect(find.text('₹1300'), findsOneWidget);
      expect(find.text('Paid ₹800'), findsOneWidget);
      expect(find.text('Pending ₹500'), findsOneWidget);

      // Tap "This month" (Aug 1–15) → only Rahul's payment remains and
      // the summary scopes to the range (no pending in it → ₹0 pill).
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Priya Patel'), findsNothing);
      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('Paid ₹800'), findsOneWidget);
      expect(find.text('Pending ₹0'), findsOneWidget);
      expect(find.text('1 payment record in 1 – 15 Aug 2026'), findsOneWidget);
    });

    testWidgets('no month chips render even for a single month of '
        'payments', (tester) async {
      final controller = PaymentHistoryController();
      controller.payments.value = [
        makePayment(
          id: 'pay_w1',
          appointmentId: 'APT_W1',
          doctorName: 'Dr. Smith',
          paymentStatus: 'Paid',
          amount: 800,
        ), // paidAt defaults to Aug 2026
      ];
      await pumpScreen(
        tester,
        controller: controller,
        size: const Size(3000, 1600),
      );

      // Just the four scope chips — no window months, no ₹0 badges.
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Custom range'), findsOneWidget);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('Aug 2026'), findsNothing);
      expect(find.text('Jul 2026'), findsNothing);
      expect(find.text('Sep 2025'), findsNothing);
      expect(find.text('₹0'), findsNothing);
      // The yearly strip: window total = current month (single Aug
      // payment) → 'Last 12 months' and 'Current month' both show ₹800
      // (summary big figure + card + both strip halves = 4).
      expect(find.text('Last 12 months'), findsOneWidget);
      expect(find.text('Current month'), findsOneWidget);
      expect(find.text('₹800'), findsNWidgets(4));
    });

    testWidgets('payments older than the window stay reachable under '
        'All (no chip of their own)', (tester) async {
      final controller = PaymentHistoryController();
      controller.payments.value = [
        makePayment(
          id: 'pay_old',
          appointmentId: 'APT_OLD',
          doctorName: 'Dr. Old',
          paymentStatus: 'Paid',
          amount: 500,
          paidAt: DateTime(2024, 3, 5, 9, 0), // outside Aug 2026…Sep 2025
        ),
        makePayment(
          id: 'pay_cur',
          appointmentId: 'APT_CUR',
          doctorName: 'Dr. Smith',
          paymentStatus: 'Paid',
          amount: 800,
        ), // paidAt defaults to Aug 2026
      ];
      await pumpScreen(tester, controller: controller);

      // The 2024 payment is listed under All (no month chips exist).
      expect(find.text('Dr. Old'), findsOneWidget);
      expect(find.text('₹500'), findsOneWidget); // card only
      // The yearly window total excludes the 2024 payment: the summary
      // big figure (all payments) is ₹1300, but the strip shows the
      // window's ₹800 (Smith card + both strip halves = 3).
      expect(find.text('₹1300'), findsOneWidget);
      expect(find.text('₹800'), findsNWidgets(3));
      // Tapping "This month" (Aug 1–15) filters the old payment out…
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Old'), findsNothing);
      // …and All brings it back.
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Old'), findsOneWidget);
      expect(find.text('₹500'), findsOneWidget);
    });

    testWidgets('a range with no matching records scopes the view to '
        'zero totals', (tester) async {
      final controller = PaymentHistoryController();
      controller.payments.value = [
        makePayment(
          id: 'pay_w2',
          appointmentId: 'APT_W2',
          doctorName: 'Dr. Smith',
          paymentStatus: 'Paid',
          amount: 800,
        ), // paidAt defaults to Aug 6 2026
      ];
      await pumpScreen(tester, controller: controller);

      // A 7–15 Aug range excludes the Aug 6 payment.
      await applyRange(tester, '7', '15');

      // Summary is scoped to the empty range with zero totals.
      expect(find.text('Payment Summary — 7 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('0 payment records in 7 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('Paid ₹0'), findsOneWidget);
      expect(find.text('Pending ₹0'), findsOneWidget);
      // The August payment is filtered out of the list…
      expect(find.text('Dr. Smith'), findsNothing);
      // …and the yearly strip now compares the window against the
      // SELECTED period (the range's ₹0): ₹800 remains only on the
      // window stat, while ₹0 shows on the big figure + the strip's
      // range stat.
      expect(find.text('₹800'), findsOneWidget);
      expect(find.text('₹0'), findsNWidgets(2));
    });

    testWidgets("the yearly strip follows a quick preset", (tester) async {
      await pumpScreen(tester, controller: multiMonthController());

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();

      // The strip's right stat becomes the SELECTED period (the range's
      // span) instead of the calendar month — its label + the range's
      // combined total.
      expect(find.text('Current month'), findsNothing);
      // '1 – 15 Aug 2026' appears on the chip badge AND as the strip's
      // right-stat label.
      expect(find.text('1 – 15 Aug 2026'), findsNWidgets(2));
      // Window total stays global (800+500+300).
      expect(find.text('₹1600'), findsOneWidget);
      // The range's ₹800: summary big figure + Alpha's card + the strip's
      // right stat.
      expect(find.text('₹800'), findsNWidgets(3));
    });

    testWidgets('the yearly strip follows a quick preset in doctor '
        'mode', (tester) async {
      // Doctor side (loadPayments): Rahul paid ₹800 in Aug, Priya has a
      // ₹500 pending in Jul — the shared screen's strip must adapt here
      // exactly like on the patient side.
      await pumpDoctorScreen(tester, [
        makePayment(
          id: 'pay_ds1',
          appointmentId: 'APT_DS1',
          patientName: 'Rahul Sharma',
          paymentStatus: 'Paid',
          amount: 800,
          paidAt: DateTime(2026, 8, 2, 10, 0),
        ),
        makePayment(
          id: 'pay_ds2',
          appointmentId: 'APT_DS2',
          patientName: 'Priya Patel',
          paymentStatus: 'Pending',
          paymentMethod: 'offline',
          amount: 500,
          paidAt: DateTime(2026, 7, 18, 9, 0),
        ),
      ]);

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();

      // The strip follows the selected period on the doctor side too.
      expect(find.text('Current month'), findsNothing);
      // '1 – 15 Aug 2026' appears on the chip badge AND as the strip
      // stat label.
      expect(find.text('1 – 15 Aug 2026'), findsNWidgets(2));
      // Window total (800+500) stays the left stat.
      expect(find.text('₹1300'), findsOneWidget);
      // The range's ₹800: summary big figure + Rahul's card + the strip's
      // right stat.
      expect(find.text('₹800'), findsNWidgets(3));
      // The pending pill reflects the SCOPE (no pending in Aug 1–15).
      expect(find.text('Pending ₹0'), findsOneWidget);
    });
  });

  // ── Chip tooltips ─────────────────────────────────────────────────
  group('the filter chips show tooltips', () {
    testWidgets('long-pressing the "This month" chip shows its tooltip '
        "without selecting it", (tester) async {
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      // Long-press the preset chip: the hint appears, and the long-press
      // is NOT a tap — the range stays unselected.
      await tester.longPress(find.text('This month'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text("Show this month's records"), findsOneWidget);
      expect(find.text('Payment Summary'), findsOneWidget); // not scoped
      expect(find.text('Dr. Beta'), findsOneWidget); // nothing filtered

      // Let the tooltip's dismiss timer fire so no timer leaks.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('a normal tap still filters through the tooltip', (
      tester,
    ) async {
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      // The Tooltip must not swallow the chip's tap — the ripple/filter
      // action still fires (regression guard for the wrapper).
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();

      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsNothing);
    });
  });

  // ── Custom date range ──────────────────────────────────────────
  group('custom date range', () {
    test('range labels cover same-month, cross-month and cross-year spans', () {
      expect(
        PaymentHistoryScreen.rangeLabel(
          DateTimeRange(
            start: DateTime(2026, 8, 10),
            end: DateTime(2026, 8, 12),
          ),
        ),
        '10 – 12 Aug 2026',
      );
      expect(
        PaymentHistoryScreen.rangeLabel(
          DateTimeRange(
            start: DateTime(2026, 7, 28),
            end: DateTime(2026, 8, 2),
          ),
        ),
        '28 Jul – 2 Aug 2026',
      );
      expect(
        PaymentHistoryScreen.rangeLabel(
          DateTimeRange(
            start: DateTime(2025, 12, 28),
            end: DateTime(2026, 1, 2),
          ),
        ),
        '28 Dec 2025 – 2 Jan 2026',
      );
    });

    testWidgets('a custom range filters the list and scopes the summary', (
      tester,
    ) async {
      await pumpScreen(tester, controller: rangeController());

      await applyRange(tester, '10', '12');

      // Only the two August payments within 10–12 remain.
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsNothing);
      // The summary is scoped to the range: title, record count, the
      // selected range chip badge, and the paid/pending split (800+500
      // paid, 0 pending).
      expect(find.text('Payment Summary — 10 – 12 Aug 2026'), findsOneWidget);
      expect(
        find.text('2 payment records in 10 – 12 Aug 2026'),
        findsOneWidget,
      );
      // The range label appears on the chip badge AND as the yearly
      // strip's right-hand stat label (which follows the selected period).
      expect(find.text('10 – 12 Aug 2026'), findsNWidgets(2));
      expect(find.text('Paid ₹1300'), findsOneWidget);
      expect(find.text('Pending ₹0'), findsOneWidget);
    });

    testWidgets("the yearly strip compares the window with the selected "
        'range', (tester) async {
      await pumpScreen(tester, controller: rangeController());

      await applyRange(tester, '10', '12');

      // The strip's right stat is the SELECTED PERIOD, not the calendar
      // month: its label + the range's combined (paid + pending) total.
      expect(find.text('Last 12 months'), findsOneWidget);
      expect(find.text('Current month'), findsNothing);
      // The range label appears on the chip badge AND as the strip label.
      expect(find.text('10 – 12 Aug 2026'), findsNWidgets(2));
      // Window total (800+500+300) — the left stat, always global.
      expect(find.text('₹1600'), findsOneWidget);
      // Range total (800+500 paid, 0 pending) — the summary big figure
      // and the strip's right stat (no month chips render anymore).
      expect(find.text('₹1300'), findsNWidgets(2));
    });

    testWidgets('the yearly strip follows a custom range in doctor mode', (
      tester,
    ) async {
      // Doctor side: Rahul paid ₹800 on Aug 10, Priya has ₹500 pending on
      // Jul 20. A 10–12 Aug range must adapt the strip on this side too.
      await pumpDoctorScreen(tester, [
        makePayment(
          id: 'pay_dr1',
          appointmentId: 'APT_DR1',
          patientName: 'Rahul Sharma',
          paymentStatus: 'Paid',
          amount: 800,
          paidAt: DateTime(2026, 8, 10, 10, 0),
        ),
        makePayment(
          id: 'pay_dr2',
          appointmentId: 'APT_DR2',
          patientName: 'Priya Patel',
          paymentStatus: 'Pending',
          paymentMethod: 'offline',
          amount: 500,
          paidAt: DateTime(2026, 7, 20, 12, 0),
        ),
      ]);

      await applyRange(tester, '10', '12');

      // The strip's right stat is the selected period on the doctor side
      // too: label = the range, total = the range's combined amount.
      expect(find.text('Last 12 months'), findsOneWidget);
      expect(find.text('Current month'), findsNothing);
      // The range label appears on the chip badge AND as the strip label.
      expect(find.text('10 – 12 Aug 2026'), findsNWidgets(2));
      // Window total (800+500) — the left stat, always global.
      expect(find.text('₹1300'), findsOneWidget);
      // Range total (Rahul's ₹800): summary big figure + Rahul's card +
      // the strip's right stat (no month chips render anymore).
      expect(find.text('₹800'), findsNWidgets(3));
    });

    testWidgets('cancelling the picker keeps the current filter', (
      tester,
    ) async {
      await pumpScreen(tester, controller: rangeController());

      await tester.tap(find.text('Custom range'));
      await tester.pumpAndSettle();
      // Dismiss via the barrier (the cancel button's label varies with
      // the theme's M2/M3 localizations).
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // Still unfiltered — every payment visible, generic summary title.
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Payment Summary'), findsOneWidget);
      expect(find.text('Custom range'), findsOneWidget);
    });

    testWidgets('the All chip clears an applied range', (tester) async {
      await pumpScreen(tester, controller: rangeController());

      await applyRange(tester, '10', '12');
      expect(find.text('Dr. Gamma'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Payment Summary'), findsOneWidget);
    });

    testWidgets('a quick preset clears the custom range (and vice versa)', (
      tester,
    ) async {
      await pumpScreen(tester, controller: rangeController());

      await applyRange(tester, '10', '12');
      expect(find.text('Payment Summary — 10 – 12 Aug 2026'), findsOneWidget);

      // A preset takes over from the range.
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();

      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsNothing); // Jul 20 is outside
      expect(find.text('Dr. Alpha'), findsOneWidget);
      // The range badge is gone (the custom chip is unselected again).
      expect(find.text('10 – 12 Aug 2026'), findsNothing);

      // The preset holds until a NEW range is applied — reopen the picker
      // and re-apply one to confirm the range wins again.
      await applyRange(tester, '10', '12');
      expect(find.text('Payment Summary — 10 – 12 Aug 2026'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsNothing);
    });

    testWidgets('exporting a custom range uses the range filename and '
        'subject', (tester) async {
      final (shareCalls, _) = mockExportPlatform(tester);
      await pumpScreen(tester, controller: rangeController());

      await applyRange(tester, '10', '12');
      await tester.tap(find.byKey(const Key('payment_history_export')));
      await tester.pump();
      await settleExport(tester, done: () => shareCalls.isNotEmpty);

      final path = sharedFilePath(shareCalls);
      expect(path, contains('payments_2026-08-10_2026-08-12.csv'));
      final args = shareCalls.last.arguments as Map<dynamic, dynamic>;
      expect(args['subject'], 'Payment history — 10 – 12 Aug 2026');
      final csv = File(path).readAsStringSync();
      expect(csv, contains('Dr. Alpha'));
      expect(csv, contains('Dr. Beta'));
      expect(csv, isNot(contains('Dr. Gamma')));
    });
  });

  // ── Quick range presets ──────────────────────────────────────────
  group('quick range presets', () {
    /// The test clock is Aug 15 2026, so the presets resolve to:
    /// "This month" = Aug 1–15, "Last 30 days" = Jul 16 – Aug 15.
    testWidgets("'This month' filters to the current month", (tester) async {
      await pumpScreen(tester, controller: rangeController());
      await tester.pumpAndSettle();

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();

      // Aug 1–15: Alpha (Aug 10) and Beta (Aug 12) in, Gamma (Jul 20) out.
      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsNothing);
      // The chip's span badge renders only while the preset is selected —
      // a standalone Text distinct from the summary title's full string,
      // proving the preset's selected-state logic fired. It appears twice:
      // on the chip and as the yearly strip's (range-following) label.
      expect(find.text('1 – 15 Aug 2026'), findsNWidgets(2));
    });

    testWidgets("'Last 30 days' reaches into the trailing month", (
      tester,
    ) async {
      await pumpScreen(tester, controller: rangeController());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();

      // Jul 16 – Aug 15 includes Gamma (Jul 20) plus Alpha and Beta.
      expect(
        find.text('Payment Summary — 16 Jul – 15 Aug 2026'),
        findsOneWidget,
      );
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsOneWidget);
      // Selected chip badge (standalone span text) + the yearly strip's
      // (range-following) stat label.
      expect(find.text('16 Jul – 15 Aug 2026'), findsNWidgets(2));
    });

    testWidgets('one preset replaces another (ranges are mutually '
        'exclusive)', (tester) async {
      await pumpScreen(tester, controller: rangeController());
      await tester.pumpAndSettle();

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);

      // 'Last 30 days' takes over from 'This month'.
      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();
      expect(
        find.text('Payment Summary — 16 Jul – 15 Aug 2026'),
        findsOneWidget,
      );
      // The wider range includes Gamma's Jul 20 payment again.
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsOneWidget);

      // And back — 'This month' narrows it again.
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsNothing);
    });

    testWidgets('a preset persists as its concrete range', (tester) async {
      await pumpScreen(tester, controller: rangeController());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();

      final saved = LocalStorageService().getPaymentHistoryFilter();
      expect(saved?['range_start'], '2026-07-16T00:00:00.000');
      expect(saved?['range_end'], '2026-08-15T00:00:00.000');
      expect(saved?.containsKey('month'), isFalse);
    });
  });

  // ── Tappable yearly strip ─────────────────────────────────────────
  group('the yearly strip doubles as a filter shortcut', () {
    testWidgets('tapping the left stat resets the filter to All', (
      tester,
    ) async {
      await pumpScreen(tester, controller: multiMonthController());

      // Narrow to this month first.
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Beta'), findsNothing);

      // Tap the window stat → everything is back under All.
      await tester.tap(find.byKey(const Key('year_strip_left')));
      await tester.pumpAndSettle();

      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Payment Summary'), findsOneWidget);
      // The reset persists as "All" (an empty saved filter).
      expect(LocalStorageService().getPaymentHistoryFilter(), isEmpty);
    });

    testWidgets("tapping the right stat jumps to 'This month' when "
        'nothing is selected', (tester) async {
      await pumpScreen(tester, controller: multiMonthController());

      // Nothing selected → the right stat is 'Current month' (Aug, per
      // the test clock). Tapping it applies the 'This month' preset.
      expect(find.text('Current month'), findsOneWidget);
      await tester.tap(find.byKey(const Key('year_strip_right')));
      await tester.pumpAndSettle();

      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('1 payment record in 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsNothing);
      // The jump persists as the concrete This-month range.
      expect(LocalStorageService().getPaymentHistoryFilter(), {
        'range_start': '2026-08-01T00:00:00.000',
        'range_end': '2026-08-15T00:00:00.000',
      });
    });

    testWidgets("tapping the right stat keeps a selected preset", (
      tester,
    ) async {
      await pumpScreen(tester, controller: multiMonthController());

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);

      // The right stat now shows the range's span — tapping it re-applies
      // the same filter (a harmless no-op).
      await tester.tap(find.byKey(const Key('year_strip_right')));
      await tester.pumpAndSettle();

      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsNothing);
      expect(LocalStorageService().getPaymentHistoryFilter(), {
        'range_start': '2026-08-01T00:00:00.000',
        'range_end': '2026-08-15T00:00:00.000',
      });
    });

    testWidgets('tapping the right stat keeps an applied custom range', (
      tester,
    ) async {
      await pumpScreen(tester, controller: rangeController());

      await applyRange(tester, '10', '12');
      expect(find.text('Payment Summary — 10 – 12 Aug 2026'), findsOneWidget);

      // The right stat shows the range's span — tapping re-applies it.
      await tester.tap(find.byKey(const Key('year_strip_right')));
      await tester.pumpAndSettle();

      expect(find.text('Payment Summary — 10 – 12 Aug 2026'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsNothing);
    });

    testWidgets('the strip taps work in doctor mode too', (tester) async {
      await pumpDoctorScreen(tester, [
        makePayment(
          id: 'pay_st1',
          appointmentId: 'APT_ST1',
          patientName: 'Rahul Sharma',
          paymentStatus: 'Paid',
          amount: 800,
          paidAt: DateTime(2026, 8, 2, 10, 0),
        ),
        makePayment(
          id: 'pay_st2',
          appointmentId: 'APT_ST2',
          patientName: 'Priya Patel',
          paymentStatus: 'Pending',
          paymentMethod: 'offline',
          amount: 500,
          paidAt: DateTime(2026, 7, 18, 9, 0),
        ),
      ]);

      // Right stat = 'Current month' (Aug) → tap applies 'This month'.
      await tester.tap(find.byKey(const Key('year_strip_right')));
      await tester.pumpAndSettle();

      expect(find.text('Payment Summary — 1 – 15 Aug 2026'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Priya Patel'), findsNothing);

      // Left stat → back to All.
      await tester.tap(find.byKey(const Key('year_strip_left')));
      await tester.pumpAndSettle();

      expect(find.text('Payment Summary'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Priya Patel'), findsOneWidget);
    });
  });

  // ── Tappable status pills ─────────────────────────────────────────
  group('the Paid/Pending pills filter by status', () {
    testWidgets('tapping Pending narrows the list to pending records', (
      tester,
    ) async {
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      // All three payments visible initially (two paid, one pending).
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summary_pill_pending')));
      await tester.pumpAndSettle();

      // Only the pending record remains — the paid ones are filtered out.
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsNothing);
      expect(find.text('Dr. Beta'), findsNothing);
      // The footer reflects the visible (pending) records…
      expect(find.text('1 Pending payment record'), findsOneWidget);
      // …but the pills keep the full scope split: the card is the money
      // picture, the pill is a filter toggle (not a re-scope).
      expect(find.text('Paid ₹1300'), findsOneWidget);
      expect(find.text('Pending ₹300'), findsOneWidget);
      // The status filter persists for the next open.
      expect(LocalStorageService().getPaymentHistoryFilter(), {
        'status': 'Pending',
      });
    });

    testWidgets('tapping the active pill again clears the status filter', (
      tester,
    ) async {
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('summary_pill_pending')));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsNothing);

      // Re-tapping the now-active pill is the escape hatch back to all
      // statuses.
      await tester.tap(find.byKey(const Key('summary_pill_pending')));
      await tester.pumpAndSettle();

      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('3 payment records'), findsOneWidget);
      // The cleared filter persists as "All" (an empty saved filter).
      expect(LocalStorageService().getPaymentHistoryFilter(), isEmpty);
    });

    testWidgets('tapping Paid narrows the list to settled records', (
      tester,
    ) async {
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('summary_pill_paid')));
      await tester.pumpAndSettle();

      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsNothing);
      expect(find.text('2 Paid payment records'), findsOneWidget);
      expect(LocalStorageService().getPaymentHistoryFilter(), {
        'status': 'Paid',
      });
    });

    testWidgets('the status composes with a quick preset', (tester) async {
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      // Narrow to the pending scope first…
      await tester.tap(find.byKey(const Key('summary_pill_pending')));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsNothing);

      // …then 'This month' (Aug 1–15): the pending record is in Jun, so
      // it drops out — zero pending records visible.
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Gamma'), findsNothing);
      expect(
        find.text('0 Pending payment records in 1 – 15 Aug 2026'),
        findsOneWidget,
      );

      // 'Last 30 days' (Jul 16 – Aug 15) still excludes the Jun record.
      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Gamma'), findsNothing);
      expect(
        find.text('0 Pending payment records in 16 Jul – 15 Aug 2026'),
        findsOneWidget,
      );

      // All clears the range AND the status together.
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(LocalStorageService().getPaymentHistoryFilter(), isEmpty);
    });

    testWidgets("the strip's window stat resets the status too", (
      tester,
    ) async {
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('summary_pill_pending')));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Alpha'), findsNothing);

      // The left stat resets EVERYTHING — including the status pill.
      await tester.tap(find.byKey(const Key('year_strip_left')));
      await tester.pumpAndSettle();

      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(LocalStorageService().getPaymentHistoryFilter(), isEmpty);
    });

    testWidgets('the status pills work in doctor mode too', (tester) async {
      await pumpDoctorScreen(tester, [
        makePayment(
          id: 'pay_pd1',
          appointmentId: 'APT_PD1',
          patientName: 'Rahul Sharma',
          paymentStatus: 'Paid',
          amount: 800,
          paidAt: DateTime(2026, 8, 2, 10, 0),
        ),
        makePayment(
          id: 'pay_pd2',
          appointmentId: 'APT_PD2',
          patientName: 'Priya Patel',
          paymentStatus: 'Pending',
          paymentMethod: 'offline',
          amount: 500,
          paidAt: DateTime(2026, 7, 18, 9, 0),
        ),
      ]);

      await tester.tap(find.byKey(const Key('summary_pill_pending')));
      await tester.pumpAndSettle();

      expect(find.text('Priya Patel'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsNothing);
      expect(find.text('1 Pending payment record'), findsOneWidget);

      // Switching to Paid flips the view to the settled patient.
      await tester.tap(find.byKey(const Key('summary_pill_paid')));
      await tester.pumpAndSettle();

      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Priya Patel'), findsNothing);
    });

    testWidgets('a saved status is restored on open', (tester) async {
      await seedSavedFilter({'status': 'Pending'});
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      // The screen reopens with the pending-only view.
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Dr. Alpha'), findsNothing);
      expect(find.text('1 Pending payment record'), findsOneWidget);
      expect(LocalStorageService().getPaymentHistoryFilter(), {
        'status': 'Pending',
      });
    });

    testWidgets('exporting after a pill tap shares only that status rows', (
      tester,
    ) async {
      final (shareCalls, _) = mockExportPlatform(tester);
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('summary_pill_pending')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment_history_export')));
      await tester.pump();
      await settleExport(tester, done: () => shareCalls.isNotEmpty);

      // The filename + subject carry the active status so the export can't
      // masquerade as the full scope.
      final path = sharedFilePath(shareCalls);
      expect(path, contains('payments_all_pending.csv'));
      final args = shareCalls.last.arguments as Map<dynamic, dynamic>;
      expect(args['subject'], 'Payment history — all records · Pending');
      final csv = File(path).readAsStringSync();
      expect(csv, contains('Dr. Gamma'));
      expect(csv, isNot(contains('Dr. Alpha')));
      expect(csv, isNot(contains('Dr. Beta')));
    });
  });

  // ── Share / Export CSV ────────────────────────────────────────────
  group('export CSV', () {
    testWidgets('export button shares a CSV of all records (All selected)', (
      tester,
    ) async {
      final (shareCalls, _) = mockExportPlatform(tester);
      final controller = PaymentHistoryController();
      controller.payments.value = [
        makePayment(
          id: 'pay_e1',
          appointmentId: 'APT_E1',
          doctorName: 'Dr. Smith',
          paymentStatus: 'Paid',
          amount: 800,
          transactionId: 'TXN123',
          upiId: 'clinic@upi',
        ),
        makePayment(
          id: 'pay_e2',
          appointmentId: 'APT_E2',
          doctorName: 'Dr. Green',
          paymentStatus: 'Pending',
          paymentMethod: 'offline',
          amount: 1000,
        ),
      ];
      await pumpScreen(tester, controller: controller);

      await tester.tap(find.byKey(const Key('payment_history_export')));
      await tester.pump();
      await settleExport(tester, done: () => shareCalls.isNotEmpty);

      expect(shareCalls, isNotEmpty);
      final path = sharedFilePath(shareCalls);
      expect(path, contains('payments_all.csv'));
      final args = shareCalls.last.arguments as Map<dynamic, dynamic>;
      expect(args['subject'], 'Payment history — all records');
      // The CSV written to disk carries the role-labeled header + both
      // rows. On the PATIENT side the counterparty column is the doctor
      // who was paid.
      final csv = File(path).readAsStringSync();
      expect(
        csv,
        startsWith(
          'Date,Doctor Name,Consultation,Method,Status,Amount (INR),'
          'Transaction ID,UPI ID,Appointment ID',
        ),
      );
      expect(csv, contains('Dr. Smith'));
      expect(csv, contains('TXN123'));
      expect(csv, contains('Dr. Green'));
    });

    testWidgets('doctor-mode export uses the Patient Name header and '
        'patient rows', (tester) async {
      final (shareCalls, _) = mockExportPlatform(tester);
      await pumpDoctorScreen(tester, [
        makePayment(
          id: 'pay_de1',
          appointmentId: 'APT_DE1',
          // doctorName pinned to null so the isNot(contains('Dr. Smith'))
          // assertion below stays meaningful if the factory default ever
          // changes.
          doctorName: null,
          patientName: 'Rahul Sharma',
          paymentStatus: 'Paid',
          amount: 800,
          transactionId: 'TXN321',
          upiId: 'clinic@upi',
        ),
        makePayment(
          id: 'pay_de2',
          appointmentId: 'APT_DE2',
          doctorName: null,
          patientName: 'Priya Patel',
          paymentStatus: 'Pending',
          paymentMethod: 'offline',
          amount: 500,
        ),
      ]);

      await tester.tap(find.byKey(const Key('payment_history_export')));
      await tester.pump();
      await settleExport(tester, done: () => shareCalls.isNotEmpty);

      expect(shareCalls, isNotEmpty);
      final path = sharedFilePath(shareCalls);
      expect(path, contains('payments_all.csv'));
      // The doctor/clinic side names the counterparty column after the
      // PATIENT who paid — and the rows carry the patient names.
      final csv = File(path).readAsStringSync();
      expect(
        csv,
        startsWith(
          'Date,Patient Name,Consultation,Method,Status,Amount (INR),'
          'Transaction ID,UPI ID,Appointment ID',
        ),
      );
      expect(csv, contains('Rahul Sharma'));
      expect(csv, contains('Priya Patel'));
      expect(csv, contains('TXN321'));
      // The doctor's own name is not in a doctor-mode export.
      expect(csv, isNot(contains('Dr. Smith')));
    });

    testWidgets("exporting a preset writes only the preset's records", (
      tester,
    ) async {
      final (shareCalls, _) = mockExportPlatform(tester);
      final controller = PaymentHistoryController();
      controller.payments.value = [
        makePayment(
          id: 'pay_ea',
          appointmentId: 'APT_EA',
          doctorName: 'Dr. Alpha',
          paymentStatus: 'Paid',
          amount: 800,
          paidAt: DateTime(2026, 8, 6),
        ),
        makePayment(
          id: 'pay_eb',
          appointmentId: 'APT_EB',
          doctorName: 'Dr. Beta',
          paymentStatus: 'Paid',
          amount: 500,
          paidAt: DateTime(2026, 7, 10),
        ),
      ];
      await pumpScreen(tester, controller: controller);

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment_history_export')));
      await tester.pump();
      await settleExport(tester, done: () => shareCalls.isNotEmpty);

      final path = sharedFilePath(shareCalls);
      expect(path, contains('payments_2026-08-01_2026-08-15.csv'));
      final args = shareCalls.last.arguments as Map<dynamic, dynamic>;
      expect(args['subject'], 'Payment history — 1 – 15 Aug 2026');
      final csv = File(path).readAsStringSync();
      expect(csv, contains('Dr. Alpha'));
      expect(csv, isNot(contains('Dr. Beta')));
    });

    testWidgets('export button is hidden when there are no payments', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('payment_history_export')), findsNothing);
    });

    testWidgets('a failing temp-dir write surfaces the Export failed '
        'snackbar', (tester) async {
      final (shareCalls, _) = mockExportPlatform(
        tester,
        failPathProvider: true,
      );
      final controller = PaymentHistoryController();
      controller.payments.value = [
        makePayment(
          id: 'pay_f',
          appointmentId: 'APT_F',
          doctorName: 'Dr. Smith',
          paymentStatus: 'Paid',
          amount: 800,
        ),
      ];
      await pumpScreen(tester, controller: controller);

      await tester.tap(find.byKey(const Key('payment_history_export')));
      await tester.pumpAndSettle();

      expect(find.text('Export failed'), findsOneWidget);
      expect(shareCalls, isEmpty);
      // Let the snackbar's auto-dismiss timer fire so no timer leaks.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('exporting a range with no records shows a snackbar and '
        'skips the share sheet', (tester) async {
      final (shareCalls, _) = mockExportPlatform(tester);
      final controller = PaymentHistoryController();
      controller.payments.value = [
        makePayment(
          id: 'pay_z',
          appointmentId: 'APT_Z',
          doctorName: 'Dr. Smith',
          paymentStatus: 'Paid',
          amount: 800,
        ), // paidAt defaults to Aug 6 2026
      ];
      await pumpScreen(tester, controller: controller);

      // A 7–15 Aug range excludes the Aug 6 payment.
      await applyRange(tester, '7', '15');
      await tester.tap(find.byKey(const Key('payment_history_export')));
      await tester.pumpAndSettle();

      expect(find.text('Nothing to export'), findsOneWidget);
      expect(shareCalls, isEmpty);
      // Let the snackbar's auto-dismiss timer fire so no timer leaks.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  // ── Persistence ──────────────────────────────────────────────────
  group('persists the filter across opens', () {
    testWidgets('a saved month key from before the bar change is ignored', (
      tester,
    ) async {
      // Older builds persisted a 'month' key — month chips no longer
      // exist, so the screen must fall back to "All" instead of applying
      // an invisible filter.
      await seedSavedFilter({'month': '2026-08'});
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      // Unfiltered: every payment visible with the generic summary title.
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsOneWidget);
      expect(find.text('Payment Summary'), findsOneWidget);
      expect(find.text('3 payment records'), findsOneWidget);
    });

    testWidgets('a saved custom range is restored on open', (tester) async {
      await seedSavedFilter({
        'range_start': '2026-08-10T00:00:00.000',
        'range_end': '2026-08-12T00:00:00.000',
      });
      await pumpScreen(tester, controller: rangeController());
      await tester.pumpAndSettle();

      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsOneWidget);
      expect(find.text('Dr. Gamma'), findsNothing);
      expect(find.text('Payment Summary — 10 – 12 Aug 2026'), findsOneWidget);
      // Chip badge + the strip's (range-following) stat label.
      expect(find.text('10 – 12 Aug 2026'), findsNWidgets(2));
    });

    testWidgets('selecting a filter persists it for the next open', (
      tester,
    ) async {
      await pumpScreen(tester, controller: multiMonthController());
      await tester.pumpAndSettle();

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(LocalStorageService().getPaymentHistoryFilter(), {
        'range_start': '2026-08-01T00:00:00.000',
        'range_end': '2026-08-15T00:00:00.000',
      });

      // Tapping All remembers "All" (an empty map — not a stale range).
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(LocalStorageService().getPaymentHistoryFilter(), isEmpty);
    });

    testWidgets('reopening the picker with a saved single-day range on '
        'the earliest payment day does not assert', (tester) async {
      // The earliest payment is Aug 10, so a single-day range ending that
      // day makes end == firstDate — showDateRangePicker asserts on
      // initialDateRange unless the screen drops it first.
      await seedSavedFilter({
        'range_start': '2026-08-10T00:00:00.000',
        'range_end': '2026-08-10T00:00:00.000',
      });
      await pumpScreen(tester, controller: rangeController());
      await tester.pumpAndSettle();
      expect(find.text('Payment Summary — 10 – 10 Aug 2026'), findsOneWidget);

      // The range filters to Aug 10 only — Alpha paid that day, Beta
      // (Aug 12) and Gamma (Jul 20) fall outside.
      expect(find.text('Dr. Alpha'), findsOneWidget);
      expect(find.text('Dr. Beta'), findsNothing);
      expect(find.text('Dr. Gamma'), findsNothing);

      // Reopening the picker must not crash; it opens with no selection.
      await tester.tap(find.text('Custom range'));
      await tester.pumpAndSettle();
      expect(find.text('Select payment date range'), findsOneWidget);

      // Dismiss via the barrier and confirm the range is untouched.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Payment Summary — 10 – 10 Aug 2026'), findsOneWidget);
    });

    testWidgets('doctor mode restores the saved filter too', (tester) async {
      // A saved Jul range (Jul 16–31) — only Priya's Jul 18 payment fits.
      await seedSavedFilter({
        'range_start': '2026-07-16T00:00:00.000',
        'range_end': '2026-07-31T00:00:00.000',
      });
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          home: PaymentHistoryScreen(
            subtitle: 'Fees collected at your clinic',
            clock: _testClock,
            loadPayments: () async => [
              makePayment(
                id: 'pay_dm1',
                appointmentId: 'APT_DM1',
                patientName: 'Rahul Sharma',
                paymentStatus: 'Paid',
                amount: 800,
                paidAt: DateTime(2026, 8, 2, 10, 0),
              ),
              makePayment(
                id: 'pay_dm2',
                appointmentId: 'APT_DM2',
                patientName: 'Priya Patel',
                paymentStatus: 'Pending',
                paymentMethod: 'offline',
                amount: 500,
                paidAt: DateTime(2026, 7, 18, 9, 0),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // July's payment (Priya) is shown; August's (Rahul) is filtered out.
      expect(find.text('Payment Summary — 16 – 31 Jul 2026'), findsOneWidget);
      expect(find.text('Priya Patel'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsNothing);
    });
  });
}
