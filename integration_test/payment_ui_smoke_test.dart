/// On-device end-to-end smoke test for the two UI features added in this
/// session:
///
/// 1. The **UPI payment modal** — the "Consultation Payment" bottom sheet
///    shows the doctor's UPI ID (`Pay to: <upi>`) in its header, and the
///    UPI app picker shows the payee badge (`Dr. Name (upi)`).
/// 2. The **payment history filter bar** — the bar renders exactly the four
///    scope chips (All / Custom range / Last 30 days / This month — the old
///    per-month chips are gone), the yearly strip shows the 12-month window
///    vs the current month, tapping a preset scopes the list + summary, and
///    All resets the filter.
///
/// Run on an emulator/device with:
///   flutter test integration_test/payment_ui_smoke_test.dart -d `<device>`
///
/// Uses test doubles (GetX controllers + fakes) exactly like the widget
/// tests — no live Supabase data required.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upi_india/upi_india.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/payment_history_controller.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/doctor_slot_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/appointment/book_appointment_screen.dart';
import 'package:DrsListing/screens/profile/payment_history_screen.dart';
import 'package:DrsListing/widgets/upi_app_picker_sheet.dart';

import '../test/helpers/test_data.dart';

/// Auth double that skips the real onInit network work and carries a
/// logged-in patient so the booking screen can pre-fill the name.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}

  _TestAuthController() {
    currentUser.value = userPatient(name: 'Smoke Patient');
    isLoggedIn.value = true;
  }
}

/// AppointmentController double: provides a VIDEO slot (fee ₹800) for
/// tomorrow — a paid consultation type, so tapping Book opens the payment
/// method sheet — and reports successful bookings without Supabase.
class _VideoSlotAppointmentController extends AppointmentController {
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
        scheduleType: 'video',
        startTime: '09:00',
        endTime: '12:00',
        durationMinutes: 30,
        fee: 800,
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

/// Stub targets for the booking success navigation (home → history).
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

/// Pumps the booking screen and navigates to it with a doctor that has its
/// own UPI ID set (the app-wide default otherwise).
Future<void> _pumpBookingFlow(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
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

  final doctor = doctorBasic(placeId: 'smoke_doc_1', name: 'Dr. Smoke')
      .copyWith(upiId: 'clinic@okhdfcbank');
  Get.toNamed(AppRoutes.bookAppointment, arguments: {'doctor': doctor});

  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Selects tomorrow's date + 9:00 AM slot and taps Book, opening the
/// payment method sheet (video is a paid consultation type).
Future<void> _openPaymentSheet(WidgetTester tester) async {
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

/// Pumps the patient payment history screen with a pre-seeded controller.
Future<void> _pumpPaymentHistory(
  WidgetTester tester,
  PaymentHistoryController controller,
) async {
  Get.put(controller, permanent: true);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: const PaymentHistoryScreen(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Minimal, predictable payment row (mirrors the widget-test factory).
PaymentModel _makePayment({
  String? id,
  String appointmentId = 'APT_SMOKE',
  String? doctorName,
  String paymentStatus = 'Paid',
  String paymentMethod = 'online',
  double amount = 800,
  DateTime? paidAt,
}) {
  return PaymentModel(
    id: id,
    appointmentId: appointmentId,
    patientId: 'user_1',
    doctorName: doctorName,
    patientName: null,
    consultationType: 'video',
    paymentStatus: paymentStatus,
    paymentMethod: paymentMethod,
    amount: amount,
    transactionId: null,
    upiId: 'clinic@upi',
    paidAt: paidAt ?? DateTime(2026, 8, 6, 10, 30),
  );
}

/// Screenshot helper: captures the current frame under `flutter drive` and
/// records the name. Never fails the test if the platform can't capture —
/// screenshots are an aid for the visual check, not an assertion.
Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  try {
    await binding.takeScreenshot(name);
  } catch (_) {
    // Screenshot infrastructure unavailable — the UI assertions above
    // still stand on their own.
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Android requires the Flutter surface to be converted to an image
    // before `takeScreenshot` can capture a frame. The try/catch keeps the
    // test harmless under plain `flutter test` (no driver attached), where
    // the platform channel may be unavailable.
    try {
      await binding.convertFlutterSurfaceToImage();
    } catch (_) {
      // Screenshots become no-ops; the UI assertions still run.
    }
  });

  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets(
      'ON-DEVICE: payment method sheet shows the doctor UPI ID in the '
      'header and booking completes', (tester) async {
    Get.put<AppointmentController>(
      _VideoSlotAppointmentController(),
      permanent: true,
    );

    await _pumpBookingFlow(tester);
    await _openPaymentSheet(tester);

    // The modal header: title + type/fee + the doctor's UPI pill.
    expect(find.text('Consultation Payment'), findsOneWidget);
    expect(find.text('Video Consultation  •  ₹800'), findsOneWidget);
    expect(find.text('Pay to: clinic@okhdfcbank'), findsOneWidget);
    // The two payment choices render under the header.
    expect(find.text('Online Pay (UPI)'), findsOneWidget);
    expect(find.text('Offline Pay'), findsOneWidget);

    // Freeze the frame for the on-device screenshot of the modal header.
    await _capture(binding, 'upi_payment_modal');

    // Pick Offline Pay → the fake books successfully → success popup.
    await tester.tap(find.text('Offline Pay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Appointment Booked!'), findsOneWidget);

    // Dismiss → success flow navigates home, then history after 1s.
    await tester.tap(find.text('View Appointments'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HOME_STUB'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HISTORY_STUB'), findsOneWidget);
  });

  testWidgets('ON-DEVICE: UPI app picker shows the payee badge with the '
      'doctor UPI ID', (tester) async {
    final apps = [
      UpiApp('GPay', 'com.google.android.apps.nbu.paisa.user'),
      UpiApp('PhonePe', 'com.phonepe.app'),
    ];

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: UpiAppPickerSheet(
              apps: apps,
              payeeUpiId: 'clinic@okhdfcbank',
              payeeName: 'Dr. Smoke',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pay with'), findsOneWidget);
    expect(find.text('2 apps'), findsOneWidget);
    expect(find.text('Dr. Smoke (clinic@okhdfcbank)'), findsOneWidget);
    expect(find.text('GPay'), findsOneWidget);
    expect(find.text('PhonePe'), findsOneWidget);

    await _capture(binding, 'upi_app_picker');
  });

  testWidgets('ON-DEVICE: filter bar renders, presets scope the list and '
      'All resets', (tester) async {
    final controller = PaymentHistoryController();
    controller.payments.value = [
      _makePayment(
        id: 'pay_m1',
        appointmentId: 'APT_M1',
        doctorName: 'Dr. Alpha',
        amount: 800,
        paidAt: DateTime(2026, 8, 6, 10, 30),
      ),
      _makePayment(
        id: 'pay_m2',
        appointmentId: 'APT_M2',
        doctorName: 'Dr. Beta',
        amount: 500,
        paidAt: DateTime(2026, 7, 10, 9, 0),
      ),
      _makePayment(
        id: 'pay_m3',
        appointmentId: 'APT_M3',
        doctorName: 'Dr. Gamma',
        paymentStatus: 'Pending',
        paymentMethod: 'offline',
        amount: 300,
        paidAt: DateTime(2026, 6, 15, 12, 0),
      ),
    ];
    await _pumpPaymentHistory(tester, controller);

    // The bar is exactly the four scope chips — no per-month chips (the
    // old month chips were replaced by the quick presets + yearly strip).
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Custom range'), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Aug 2026'), findsNothing);
    expect(find.text('Jul 2026'), findsNothing);
    expect(find.text('Jun 2026'), findsNothing);

    // Yearly strip in the summary card: the whole 12-month window
    // (800+500+300 = 1600) vs the current month (Aug = 800), and the
    // all-time summary with the Paid/Pending split pills.
    expect(find.text('Last 12 months'), findsOneWidget);
    expect(find.text('Current month'), findsOneWidget);
    expect(find.text('₹1600'), findsOneWidget);
    expect(find.text('₹1300'), findsOneWidget);
    expect(find.text('Paid ₹1300'), findsOneWidget);
    expect(find.text('Pending ₹300'), findsOneWidget);
    expect(find.text('3 payment records'), findsOneWidget);

    await _capture(binding, 'filter_all');

    // The filter bar is a lazy horizontal ListView — chips scrolled out of
    // view are disposed from the element tree, so scroll the bar until the
    // last chip ('This month') re-materializes before tapping it.
    Finder chipBar() => find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );
    await tester.dragUntilVisible(
      find.text('This month'),
      chipBar(),
      const Offset(-50, 0), // drag content left → scroll right toward the end
      maxIteration: 20,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();

    // Only August's payment (Aug 6, inside the current month on the device
    // clock) remains; the summary scopes to the range.
    expect(find.text('Dr. Alpha'), findsOneWidget);
    expect(find.text('Dr. Beta'), findsNothing);
    expect(find.text('Dr. Gamma'), findsNothing);
    expect(find.text('Paid ₹800'), findsOneWidget);
    expect(find.text('Pending ₹0'), findsOneWidget);
    // The all-time figures leave once a range is active.
    expect(find.text('Paid ₹1300'), findsNothing);

    await _capture(binding, 'filter_this_month');

    // All resets back to the all-time figures. "All" was culled when the
    // bar scrolled right, so drag the bar back to its start first.
    await tester.dragUntilVisible(
      find.text('All'),
      chipBar(),
      const Offset(50, 0), // drag content right → scroll back to the start
      maxIteration: 20,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Dr. Alpha'), findsOneWidget);
    expect(find.text('Dr. Beta'), findsOneWidget);
    expect(find.text('Dr. Gamma'), findsOneWidget);
    expect(find.text('3 payment records'), findsOneWidget);
    expect(find.text('Paid ₹1300'), findsOneWidget);
    expect(find.text('Pending ₹300'), findsOneWidget);

    await _capture(binding, 'filter_all_reset');
  });
}
