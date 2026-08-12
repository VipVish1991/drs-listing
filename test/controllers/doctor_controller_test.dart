import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/doctor_controller.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/utils/payment_summary.dart';
import '../helpers/test_data.dart';

/// Test-only AuthController that skips the secure-storage platform channel
/// (same pattern as the other controller tests).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  late DoctorController controller;
  late DoctorModel doctor;

  setUp(() {
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<DoctorController>(DoctorController(), permanent: true);
    controller = Get.find<DoctorController>();
    doctor = doctorBasic(placeId: 'place_doctor_1', name: 'Dr. Test');

    // Set the current doctor so loadStats() doesn't early-return on null
    controller.currentDoctor.value = doctor;

    // Set up local appointments list for pure-logic tests.
    // Note: loadStats() reads stats from Supabase (not local list),
    // but totalPatients is also calculated from the local list.
    // However, it's inside the try block that wraps the Supabase call,
    // so if Supabase throws, totalPatients won't be updated either.
    controller.appointments.assignAll([
      appointmentBasic(
        appointmentId: 'APT001',
        patientName: 'Alice',
        doctorName: 'Dr. Test',
        doctorPlaceId: 'place_doctor_1',
        appointmentDate: _todayKey(),
        appointmentTime: '10:00 AM',
        status: 'Upcoming',
      ),
      appointmentBasic(
        appointmentId: 'APT002',
        patientName: 'Bob',
        doctorName: 'Dr. Test',
        doctorPlaceId: 'place_doctor_1',
        appointmentDate: _todayKey(),
        appointmentTime: '11:00 AM',
        status: 'Completed',
      ),
      appointmentBasic(
        appointmentId: 'APT003',
        patientName: 'Charlie',
        doctorName: 'Dr. Test',
        doctorPlaceId: 'place_doctor_1',
        appointmentDate: _yesterdayKey(),
        appointmentTime: '09:00 AM',
        status: 'Completed',
      ),
      appointmentBasic(
        appointmentId: 'APT004',
        patientName: 'Diana',
        doctorName: 'Dr. Test',
        doctorPlaceId: 'place_doctor_1',
        appointmentDate: _tomorrowKey(),
        appointmentTime: '02:00 PM',
        status: 'Upcoming',
      ),
      appointmentBasic(
        appointmentId: 'APT005',
        patientName: 'Eve',
        doctorName: 'Dr. Test',
        doctorPlaceId: 'place_doctor_1',
        appointmentDate: _tomorrowKey(),
        appointmentTime: '03:00 PM',
        status: 'Upcoming',
      ),
      appointmentBasic(
        appointmentId: 'APT006',
        patientName: 'Frank',
        doctorName: 'Dr. Test',
        doctorPlaceId: 'place_doctor_1',
        appointmentDate: '2026-07-15',
        appointmentTime: '04:00 PM',
        status: 'Cancelled',
      ),
    ]);
  });

  tearDown(() {
    Get.reset();
  });

  group('getAppointmentsForDate', () {
    test('returns appointments for today', () {
      final todayAppts = controller.getAppointmentsForDate(_todayKey());
      expect(todayAppts.length, 2);
      // Should be sorted by time ascending
      expect(todayAppts[0].appointmentTime, '10:00 AM');
      expect(todayAppts[1].appointmentTime, '11:00 AM');
    });

    test('returns appointments for tomorrow', () {
      final tomorrowAppts = controller.getAppointmentsForDate(_tomorrowKey());
      expect(tomorrowAppts.length, 2);
      expect(tomorrowAppts[0].appointmentTime, '02:00 PM');
      expect(tomorrowAppts[1].appointmentTime, '03:00 PM');
    });

    test('returns empty list for date with no appointments', () {
      final appts = controller.getAppointmentsForDate('2025-01-01');
      expect(appts, isEmpty);
    });

    test('returns single appointment for a specific date', () {
      final appts = controller.getAppointmentsForDate('2026-07-15');
      expect(appts.length, 1);
      expect(appts[0].patientName, 'Frank');
      expect(appts[0].status, 'Cancelled');
    });

    test('returns early morning time before late morning time', () {
      controller.appointments.add(
        appointmentBasic(
          appointmentId: 'APT007',
          patientName: 'Grace',
          appointmentDate: _todayKey(),
          appointmentTime: '09:00 AM',
          status: 'Upcoming',
        ),
      );

      final todayAppts = controller.getAppointmentsForDate(_todayKey());
      expect(todayAppts.length, 3);
      expect(todayAppts[0].appointmentTime, '09:00 AM');
      expect(todayAppts[1].appointmentTime, '10:00 AM');
      expect(todayAppts[2].appointmentTime, '11:00 AM');
    });

    test('sorts by real clock time, not raw string order', () {
      // 9:00 AM (no leading zero) vs 10:00 AM: raw string compare would put
      // 10:00 AM first ('1' < '9'); real clock time puts 9:00 AM first.
      controller.appointments.assignAll([
        appointmentBasic(
          appointmentId: 'APT009',
          patientName: 'Helen',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: 'Upcoming',
        ),
        appointmentBasic(
          appointmentId: 'APT008',
          patientName: 'Ivan',
          appointmentDate: _todayKey(),
          appointmentTime: '9:00 AM',
          status: 'Upcoming',
        ),
      ]);

      final todayAppts = controller.getAppointmentsForDate(_todayKey());
      expect(todayAppts.length, 2);
      expect(todayAppts[0].appointmentTime, '9:00 AM');
      expect(todayAppts[1].appointmentTime, '10:00 AM');
    });

    test('sorts 12:00 PM after the morning hours it should follow', () {
      // Raw string compare puts '12:00 PM' before '2:00 AM' ('1' < '2'),
      // but 2:00 AM is 120 minutes after midnight while 12:00 PM is 720 —
      // real clock time puts 2:00 AM first.
      controller.appointments.assignAll([
        appointmentBasic(
          appointmentId: 'APT012',
          patientName: 'Jack',
          appointmentDate: _todayKey(),
          appointmentTime: '12:00 PM',
          status: 'Upcoming',
        ),
        appointmentBasic(
          appointmentId: 'APT011',
          patientName: 'Kate',
          appointmentDate: _todayKey(),
          appointmentTime: '2:00 AM',
          status: 'Upcoming',
        ),
        appointmentBasic(
          appointmentId: 'APT010',
          patientName: 'Leo',
          appointmentDate: _todayKey(),
          appointmentTime: '9:00 PM',
          status: 'Upcoming',
        ),
      ]);

      final todayAppts = controller.getAppointmentsForDate(_todayKey());
      expect(todayAppts.length, 3);
      expect(todayAppts[0].appointmentTime, '2:00 AM');
      expect(todayAppts[1].appointmentTime, '12:00 PM');
      expect(todayAppts[2].appointmentTime, '9:00 PM');
    });
  });

  group('uniqueAppointmentDates', () {
    test('returns sorted unique dates', () {
      final dates = controller.uniqueAppointmentDates;
      expect(dates.length, 4);
      expect(dates[0], '2026-07-15');
      expect(dates[1], _yesterdayKey());
      expect(dates[2], _todayKey());
      expect(dates[3], _tomorrowKey());
    });

    test('excludes empty/null dates', () {
      controller.appointments.add(
        appointmentBasic(
          appointmentId: 'APT_NO_DATE',
          patientName: 'Test',
          appointmentDate: null,
        ),
      );
      final dates = controller.uniqueAppointmentDates;
      expect(dates.length, 4);
      expect(dates, isNot(contains('')));
    });

    test('returns empty list when no appointments', () {
      controller.appointments.clear();
      expect(controller.uniqueAppointmentDates, isEmpty);
    });
  });

  group('paidIncomeOf (shared payment_summary util)', () {
    test('sums only Paid payments (excludes Pending/Refunded/Failed)', () {
      final income = paidIncomeOf([
        _payment(amount: 800, status: 'Paid'),
        _payment(amount: 500, status: 'Paid'),
        _payment(amount: 300, status: 'Pending'),
        _payment(amount: 200, status: 'Refunded'),
        _payment(amount: 100, status: 'Failed'),
      ]);
      expect(income, 1300.0);
    });

    test('returns 0 when nothing is Paid or the list is empty', () {
      expect(
        paidIncomeOf([_payment(amount: 300, status: 'Pending')]),
        0.0,
      );
      expect(paidIncomeOf([]), 0.0);
    });
  });

  group('pendingIncomeOf (shared payment_summary util)', () {
    test('sums only Pending payments (excludes Paid/Refunded/Failed)', () {
      final owed = pendingIncomeOf([
        _payment(amount: 300, status: 'Pending'),
        _payment(amount: 700, status: 'Pending'),
        _payment(amount: 800, status: 'Paid'),
        _payment(amount: 200, status: 'Refunded'),
        _payment(amount: 100, status: 'Failed'),
      ]);
      expect(owed, 1000.0);
    });

    test('returns 0 when nothing is Pending or the list is empty', () {
      expect(
        pendingIncomeOf([_payment(amount: 800, status: 'Paid')]),
        0.0,
      );
      expect(pendingIncomeOf([]), 0.0);
    });
  });

  group('loadPayments (with Supabase unavailable)', () {
    test('payment stats default to zero when Supabase is unavailable', () async {
      // A logged-in user (so loadPayments passes the null guard) whose
      // Supabase call throws in the test env — the catch keeps the
      // dashboard stats at their defaults instead of crashing.
      Get.find<AuthController>().currentUser.value =
          userPatient(id: 'user_pay_test', mobile: '9876543210');
      await controller.loadPayments();

      expect(controller.paymentCount.value, 0);
      expect(controller.paidIncome.value, 0.0);
      expect(controller.pendingIncome.value, 0.0);
      expect(controller.paymentsByAppointment, isEmpty);
    });
  });

  group('loadStats (with Supabase unavailable)', () {
    test('defaults to zero when Supabase is unavailable', () async {
      // currentDoctor is set, so loadStats proceeds past the null guard.
      // Supabase call will throw (not initialized in test env).
      // The catch block silently handles the error, so all reactive
      // stat values stay at their defaults (0).
      await controller.loadStats();

      expect(controller.totalAppointments.value, 0);
      expect(controller.completedAppointments.value, 0);
      expect(controller.cancelledAppointments.value, 0);
      expect(controller.upcomingAppointments.value, 0);
      expect(controller.todayAppointments.value, 0);
      // totalPatients is inside the same try block — also stays at 0
      expect(controller.totalPatients.value, 0);
      // isLoadingStats must be reset even after failure
      expect(controller.isLoadingStats.value, isFalse);
    });

    test('resets isLoadingStats after error', () async {
      await controller.loadStats();
      expect(controller.isLoadingStats.value, isFalse);
    });
  });

  group('setDoctor', () {
    test('sets current doctor', () async {
      await controller.setDoctor(doctor);
      expect(controller.currentDoctor.value?.placeId, 'place_doctor_1');
      expect(controller.currentDoctor.value?.name, 'Dr. Test');
    });

    test('triggers loading states', () async {
      expect(controller.isLoadingAppointments.value, isFalse);
      expect(controller.isLoadingStats.value, isFalse);

      final future = controller.setDoctor(doctor);
      expect(controller.currentDoctor.value?.placeId, 'place_doctor_1');
      await future;

      expect(controller.isLoadingStats.value, isFalse);
    });
  });

  group('updateAppointmentStatus', () {
    test('handles gracefully when Supabase is unavailable', () async {
      await controller.updateAppointmentStatus('APT_UPDATE', 'Completed');
      expect(controller.isLoadingAppointments.value, isFalse);
    });
  });
}

/// Minimal [PaymentModel] fixture for the pure income-fold tests.
PaymentModel _payment({required double amount, required String status}) {
  return PaymentModel(
    appointmentId: 'APT_PAY_$amount$status',
    patientId: 'patient-test',
    amount: amount,
    paymentStatus: status,
  );
}

/// Helper: today's date in yyyy-MM-dd format.
String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

/// Helper: yesterday's date in yyyy-MM-dd format.
String _yesterdayKey() {
  final d = DateTime.now().subtract(const Duration(days: 1));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Helper: tomorrow's date in yyyy-MM-dd format.
String _tomorrowKey() {
  final d = DateTime.now().add(const Duration(days: 1));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
