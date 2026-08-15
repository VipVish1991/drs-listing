import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/doctor_slot_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/appointment/book_appointment_screen.dart';
import 'package:DrsListing/services/quantupi_payment_service.dart';

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

/// AppointmentController double: provides a VIDEO slot (fee ₹800) for
/// tomorrow — a paid consultation type, so tapping Book opens the payment
/// method sheet — and reports successful bookings without touching Supabase.
class _VideoSlotAppointmentController extends AppointmentController {
  /// How many times [bookAppointment] was invoked. Tests assert a
  /// non-confirmed ('submitted') UPI payment NEVER books, so this must stay
  /// 0 through the whole Online Pay flow.
  int bookAppointmentCalls = 0;

  /// The payment record passed to the last [bookAppointment] call.
  PaymentModel? lastPayment;
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
  }) async {
    bookAppointmentCalls++;
    lastPayment = payment;
    return true;
  }
}

/// Stub targets for the booking success navigation (not reached in most
/// tests, but required so the route table is complete).
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The UPI VPA the mocked doctors row returns. Tests flip this to
  /// exercise both the "doctor set a UPI" and "doctor hasn't set one"
  /// branches of the merge + pill rendering.
  String? dbUpiId = 'clinic@okhdfcbank';

  /// Fake quantupi responses: each [QuantupiPaymentService.pay] call pops
  /// the next raw response; an empty queue fails the payment (so a retry
  /// that was never queued still resolves instead of hanging).
  final responseQueue = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    // ── Mock Supabase client ────────────────────────────────────
    // GET on the doctors table returns the saved doctor row WITH upi_id
    // (the clinic set it on their profile). This is exactly what
    // SupabaseService.getDoctorFromDb sees during _loadSlots.
    final supabaseClient = MockClient((request) async {
      final path = request.url.path;

      http.Response respond(String body, {int status = 200}) =>
          http.Response(
            body,
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );

      // Auth settings — Supabase initialization probes this endpoint.
      if (path.endsWith('/auth/v1/settings')) {
        return respond(jsonEncode({
          'external': {'enabled': false},
          'mailer': {'enabled': false},
          'phone': {'enabled': false},
          'sms': {'enabled': false},
          'mfa': {'enabled': false},
          'password': {'enabled': false},
          'sessions': {'enabled': false},
        }));
      }

      // Doctors table: return the DB row with the saved UPI VPA (or none,
      // depending on [dbUpiId]).
      if (path.contains('/rest/v1/doctors') && request.method == 'GET') {
        return respond(jsonEncode([
          {
            'place_id': 'upi_fetch_1',
            'name': 'Dr. Smith',
            'upi_id': dbUpiId,
            'types': ['doctor', 'health'],
            'unavailable_ranges': [],
          },
        ]));
      }

      // Everything else — no-op.
      return respond('[]');
    });

    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test-anon-key',
      httpClient: supabaseClient,
    );
  });

  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<AppointmentController>(
      _VideoSlotAppointmentController(),
      permanent: true,
    );
    // Every test starts with the doctor having set a UPI VPA in the DB.
    dbUpiId = 'clinic@okhdfcbank';
    responseQueue.clear();
    // Force the Android path + fake the plugin invocation so the flow runs
    // on the test host (the real plugin only exists on Android devices).
    QuantupiPaymentService.forceAndroid = true;
    QuantupiPaymentService.transactionOverride = (upi) async {
      return responseQueue.isNotEmpty
          ? responseQueue.removeAt(0)
          : 'status=failure';
    };
  });

  tearDown(() {
    QuantupiPaymentService.transactionOverride = null;
    QuantupiPaymentService.forceAndroid = null;
    Get.reset();
  });

  /// Pumps the booking screen with a doctor whose model carries NO upiId —
  /// exactly what Google Places search/enrichment produces.
  Future<void> pumpBookingFlow(WidgetTester tester) async {
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

    final doctor = doctorBasic(
      placeId: 'upi_fetch_1',
      name: 'Dr. Smith',
    );
    // Precondition: a Places-sourced doctor model never carries upiId.
    expect(doctor.upiId, isNull);

    Get.toNamed(AppRoutes.bookAppointment, arguments: {'doctor': doctor});

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Selects tomorrow + 9:00 AM and taps Book, opening the payment sheet.
  Future<void> openPaymentSheet(WidgetTester tester) async {
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

  testWidgets(
      'payment sheet shows the doctor UPI ID fetched from the DB even when '
      'the passed model has none', (tester) async {
    await pumpBookingFlow(tester);
    await openPaymentSheet(tester);

    // Regression: the doctor model passed in had upiId == null (Places
    // never returns it), yet the modal header must show the clinic's
    // receiving VPA because _loadSlots merges it from the doctors table.
    expect(find.text('Consultation Payment'), findsOneWidget);
    expect(find.text('Video Consultation  •  ₹800'), findsOneWidget);
    expect(find.text('Pay to: clinic@okhdfcbank'), findsOneWidget);
    expect(find.text('Online Pay (UPI)'), findsOneWidget);
    expect(find.text('Offline Pay'), findsOneWidget);
  });

  testWidgets('payment sheet hides online pay entirely when the doctor has '
      'no UPI in the DB', (tester) async {
    // The doctors row has no upi_id → the merge leaves upiId null. Without
    // a real receiving VPA an online payment can never complete, so the
    // modal must NOT offer Online Pay at all (no "Pay to:" pill, no UPI
    // tile) — the patient pays at the clinic instead.
    dbUpiId = null;

    await pumpBookingFlow(tester);
    await openPaymentSheet(tester);

    expect(find.text('Consultation Payment'), findsOneWidget);
    expect(find.text('Video Consultation  •  ₹800'), findsOneWidget);
    expect(find.textContaining('Pay to:'), findsNothing);
    expect(find.text('Online Pay (UPI)'), findsNothing);
    expect(find.textContaining('Online payment not available'), findsOneWidget);
    expect(find.text('Offline Pay'), findsOneWidget);
  });

  testWidgets('a confirmed UPI payment books with an online Paid record', (
    tester,
  ) async {
    responseQueue.add('upi://pay?txnid=UPI_OK123&status=success');

    await pumpBookingFlow(tester);
    await openPaymentSheet(tester);

    await tester.tap(find.text('Online Pay (UPI)'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // The success snackbar fires, then the booking proceeds with the
    // online 'Paid' record carrying the transaction id + doctor VPA.
    final controller = Get.find<AppointmentController>()
        as _VideoSlotAppointmentController;
    expect(controller.bookAppointmentCalls, 1);
    final payment = controller.lastPayment;
    expect(payment, isNotNull);
    expect(payment!.paymentMethod, 'online');
    expect(payment.paymentStatus, 'Paid');
    expect(payment.amount, 800);
    expect(payment.transactionId, 'UPI_OK123');
    expect(payment.upiId, 'clinic@okhdfcbank');

    // The success dialog appears.
    await tester.pumpAndSettle();
    expect(find.text('Appointment Booked!'), findsOneWidget);

    // Close it, then let the post-booking navigation + its delayed
    // 'open appointment history' timer fire so no timers stay pending.
    await tester.tap(find.text('View Appointments'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // Let the success snackbar's auto-dismiss timer fire.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'online pay with a submitted UPI outcome never calls bookAppointment',
      (tester) async {
    // The UPI app reports the payment as initiated but NOT confirmed.
    responseQueue.add('txnid=UPI_SUB&status=submitted');

    await pumpBookingFlow(tester);
    await openPaymentSheet(tester);

    await tester.tap(find.text('Online Pay (UPI)'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // ...but an unconfirmed payment must NEVER book:
    final controller = Get.find<AppointmentController>()
        as _VideoSlotAppointmentController;
    expect(controller.bookAppointmentCalls, 0);

    // A dialog (not a dismissible snackbar) explains the unconfirmed
    // payment and warns against paying twice.
    expect(find.text('Payment Not Confirmed'), findsOneWidget);
    expect(find.text('Pay Offline'), findsOneWidget);
    // No success dialog, no navigation — still on the booking screen.
    expect(find.text('Appointment Booked!'), findsNothing);
    expect(find.text('Book Appointment'), findsWidgets);

    // Dismissing it books nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.bookAppointmentCalls, 0);
    expect(find.text('Payment Not Confirmed'), findsNothing);
  });

  testWidgets('a declined UPI payment offers Try Again and never books', (
    tester,
  ) async {
    // Both attempts report a DECLINED payment (status=failure) — the
    // "Payment Failed — UPI risk policy" case from the wild.
    responseQueue.add('txnid=UPI_FAIL1&status=failure');
    responseQueue.add('txnid=UPI_FAIL2&status=failure');

    await pumpBookingFlow(tester);
    await openPaymentSheet(tester);

    await tester.tap(find.text('Online Pay (UPI)'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // The failure dialog appears with the money-deducted reassurance.
    expect(find.text('Payment Failed'), findsOneWidget);
    expect(find.textContaining('No money was deducted'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Pay Offline'), findsOneWidget);

    // Try Again re-fires the UPI intent (queued response #2, still
    // declined) and the dialog returns.
    await tester.tap(find.text('Try Again'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Payment Failed'), findsOneWidget);

    // Dismissing via the barrier (outside the dialog) also cancels —
    // nothing books, still on the booking screen.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    final controller = Get.find<AppointmentController>()
        as _VideoSlotAppointmentController;
    expect(controller.bookAppointmentCalls, 0);
    expect(find.text('Appointment Booked!'), findsNothing);
    expect(find.text('Book Appointment'), findsWidgets);
  });

  testWidgets('a declined UPI payment can switch to offline pay and book', (
    tester,
  ) async {
    responseQueue.add('txnid=UPI_FAIL&status=failure');

    await pumpBookingFlow(tester);
    await openPaymentSheet(tester);

    await tester.tap(find.text('Online Pay (UPI)'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Switching to offline pay from the failure dialog books the
    // appointment with an offline 'Pending' pay-at-clinic record.
    await tester.tap(find.text('Pay Offline'));
    await tester.pumpAndSettle();

    final controller = Get.find<AppointmentController>()
        as _VideoSlotAppointmentController;
    expect(controller.bookAppointmentCalls, 1);
    expect(controller.lastPayment?.paymentMethod, 'offline');
    expect(controller.lastPayment?.paymentStatus, 'Pending');
    expect(controller.lastPayment?.amount, 800);
    expect(find.text('Appointment Booked!'), findsOneWidget);

    // Close the success dialog, then let the post-booking navigation AND
    // its delayed 'open appointment history' timer fire so no timers stay
    // pending at teardown.
    await tester.tap(find.text('View Appointments'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
