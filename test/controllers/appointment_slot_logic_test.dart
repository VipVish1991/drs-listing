import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';

import '../helpers/test_data.dart';

/// Auth double that skips the real onInit network work.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// AppointmentController double that skips the onInit appointment load.
class _TestAppointmentController extends AppointmentController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

String _isoDate(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  test('AppointmentStatus.occupiesSlot disables the slot for every status '
      'except Cancelled', () {
    // Any appointment status (Pending, Upcoming, Completed, …) keeps its
    // slot booked/disabled.
    expect(AppointmentStatus.occupiesSlot('Upcoming'), isTrue);
    expect(AppointmentStatus.occupiesSlot(AppointmentStatus.pending), isTrue);
    expect(AppointmentStatus.occupiesSlot('Completed'), isTrue);
    expect(AppointmentStatus.occupiesSlot('Unknown'), isTrue);
    // Only a Cancelled appointment frees the slot again.
    expect(
      AppointmentStatus.occupiesSlot(AppointmentStatus.cancelled),
      isFalse,
    );
  });

  test('isSlotBooked checks the bookedSlotKeys set', () {
    final controller = _TestAppointmentController();
    controller.bookedSlotKeys.assignAll({'2026-08-01|9:00 AM'});

    expect(controller.isSlotBooked('2026-08-01', '9:00 AM'), isTrue);
    expect(controller.isSlotBooked('2026-08-01', '9:30 AM'), isFalse);
    expect(controller.isSlotBooked('2026-08-02', '9:00 AM'), isFalse);
  });

  test('isSlotInPast returns true for a slot already passed today', () {
    final controller = _TestAppointmentController();
    final now = DateTime.now();
    // Use the earliest slot of today — before the current time.
    expect(controller.isSlotInPast(_isoDate(now), '12:00 AM'), isTrue);
    // A clearly future date is never in the past.
    final tomorrow = now.add(const Duration(days: 1));
    expect(controller.isSlotInPast(_isoDate(tomorrow), '9:00 AM'), isFalse);
    // An unparseable slot never blocks the user.
    expect(controller.isSlotInPast(_isoDate(now), ''), isFalse);
  });


  test("getAppointmentsForDate returns the day's rows sorted by real "
      'clock time', () {
    final controller = _TestAppointmentController();
    controller.appointments.assignAll([
      appointmentBasic(
        appointmentId: 'APT_NOON',
        appointmentDate: '2027-06-01',
        appointmentTime: '12:00 PM',
        status: AppointmentStatus.upcoming,
      ),
      appointmentBasic(
        appointmentId: 'APT_EARLY',
        appointmentDate: '2027-06-01',
        appointmentTime: '9:00 AM',
        status: AppointmentStatus.completed,
      ),
      appointmentBasic(
        appointmentId: 'APT_OTHER_DAY',
        appointmentDate: '2027-06-02',
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
      ),
    ]);

    // Only the rows for the requested date — all statuses share the one
    // list — sorted by real clock time ascending (9:00 AM before 12:00
    // PM, not raw string order).
    expect(
      controller
          .getAppointmentsForDate('2027-06-01')
          .map((a) => a.appointmentId)
          .toList(),
      ['APT_EARLY', 'APT_NOON'],
    );
    expect(controller.getAppointmentsForDate('2027-06-02').length, 1);
    expect(controller.getAppointmentsForDate('2025-01-01'), isEmpty);
  });

  test('uniqueAppointmentDates returns sorted distinct dates', () {
    final controller = _TestAppointmentController();
    controller.appointments.assignAll([
      appointmentBasic(
        appointmentId: 'APT_1',
        appointmentDate: '2026-08-02',
      ),
      appointmentBasic(
        appointmentId: 'APT_2',
        appointmentDate: '2026-08-01',
      ),
      appointmentBasic(
        appointmentId: 'APT_3',
        appointmentDate: '2026-08-01',
      ),
      appointmentBasic(appointmentId: 'APT_4', appointmentDate: null),
    ]);

    expect(controller.uniqueAppointmentDates, ['2026-08-01', '2026-08-02']);
  });
}
