import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/payment_history_controller.dart';
import 'package:DrsListing/models/payment_model.dart';
import '../helpers/test_data.dart';

/// Test-only AuthController that skips the secure-storage platform channel.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

PaymentModel _payment({
  String? id,
  DateTime? createdAt,
  String paymentStatus = 'Paid',
  String paymentMethod = 'online',
  double amount = 800,
}) =>
    PaymentModel(
      id: id,
      appointmentId: 'APT1001',
      patientId: 'user_1',
      doctorName: 'Dr. Smith',
      paymentStatus: paymentStatus,
      paymentMethod: paymentMethod,
      amount: amount,
      createdAt: createdAt ?? DateTime(2026, 8, 6),
    );

void main() {
  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  test('load failure keeps the existing list and resets isLoading', () async {
    Get.find<AuthController>().currentUser.value =
        userPatient(id: 'user_1', mobile: '9876543210');

    final controller = PaymentHistoryController();
    controller.payments.value = [_payment(id: 'pay_1')];
    controller.isLoading.value = false;

    // Supabase is uninitialized in tests, so getPaymentsForUser throws —
    // exactly the transient-failure path the contract must survive.
    await controller.load();

    // The pre-seeded list survives and the spinner state resets.
    expect(controller.payments.length, 1);
    expect(controller.payments.first.id, 'pay_1');
    expect(controller.isLoading.value, isFalse);
  });

  test('paidTotal sums only Paid and pendingTotal only Pending', () {
    final controller = PaymentHistoryController();
    controller.payments.value = [
      _payment(id: 'pay_paid_1', createdAt: DateTime(2026, 8, 1)),
      _payment(id: 'pay_paid_2', createdAt: DateTime(2026, 8, 2)),
      _payment(
        id: 'pay_pending_1',
        createdAt: DateTime(2026, 8, 3),
        paymentStatus: 'Pending',
        paymentMethod: 'offline',
        amount: 300,
      ),
      _payment(
        id: 'pay_refunded_1',
        createdAt: DateTime(2026, 8, 4),
        paymentStatus: 'Refunded',
        paymentMethod: 'offline',
        amount: 200,
      ),
    ];

    // The two paid fixtures (₹800 + ₹800) vs the single pending one.
    expect(controller.paidTotal, 1600.0);
    expect(controller.pendingTotal, 300.0);
  });

  test('totals are zero when there are no payments', () {
    final controller = PaymentHistoryController();
    expect(controller.paidTotal, 0.0);
    expect(controller.pendingTotal, 0.0);
  });

  test('load is a no-op when no user is logged in', () async {
    Get.find<AuthController>().currentUser.value = null;

    final controller = PaymentHistoryController();
    controller.isLoading.value = true;

    await controller.load();

    expect(controller.payments, isEmpty);
    // isLoading untouched (stays true) — mirrors NotificationCenter's
    // contract where the screen keeps the spinner while logged out.
    expect(controller.isLoading.value, isTrue);
  });
}
