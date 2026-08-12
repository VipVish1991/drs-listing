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

  _TestAuthController() {
    currentUser.value = userPatient(name: 'Reschedule Patient');
    isLoggedIn.value = true;
  }
}

/// AppointmentController double that skips the onInit appointment load and
/// the post-reschedule reload, and records what the service would have
/// received.
class _TestAppointmentController extends AppointmentController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> loadAppointments() async {}

  /// True → the fake service accepts the move; false → the DB trigger
  /// rejected it (slot just taken).
  bool acceptMove = true;

  String? lastAppointmentId;
  String? lastDate;
  String? lastTime;
  String? lastConsultationType;
  bool? lastInitiatedByDoctor;

  @override
  Future<bool> rescheduleAppointment(
    AppointmentModel appointment, {
    required String date,
    required String time,
    required String consultationType,
    bool initiatedByDoctor = false,
  }) async {
    lastAppointmentId = appointment.appointmentId;
    lastDate = date;
    lastTime = time;
    lastConsultationType = consultationType;
    lastInitiatedByDoctor = initiatedByDoctor;
    return acceptMove;
  }
}

/// Variant WITHOUT the reschedule override — used to exercise the real
/// `rescheduleAppointment` guard (returns false before touching Supabase
/// when no user is logged in).
class _GuardTestAppointmentController extends AppointmentController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> loadAppointments() async {}
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  test('AppointmentStatus.isReschedulable only allows Pending/Upcoming',
      () {
    // The single shared rule behind the patient card chip, the patient
    // details-sheet action and the doctor's patient-history action.
    expect(
      AppointmentStatus.isReschedulable(AppointmentStatus.pending),
      isTrue,
    );
    expect(
      AppointmentStatus.isReschedulable(AppointmentStatus.upcoming),
      isTrue,
    );
    expect(
      AppointmentStatus.isReschedulable(AppointmentStatus.completed),
      isFalse,
    );
    expect(
      AppointmentStatus.isReschedulable(AppointmentStatus.cancelled),
      isFalse,
    );
    expect(AppointmentStatus.isReschedulable(''), isFalse);
  });

  test('isSlotBookedExcluding ignores the appointment being rescheduled',
      () {
    final controller = _TestAppointmentController();
    // The appointment being rescheduled occupies 2026-08-01 at 9:00 AM.
    controller.bookedSlotKeys.assignAll({
      '2026-08-01|9:00 AM',
      '2026-08-02|10:00 AM',
    });

    // Its own slot is NOT treated as booked during reschedule.
    expect(
      controller.isSlotBookedExcluding(
        '2026-08-01',
        '9:00 AM',
        excludeDate: '2026-08-01',
        excludeTime: '9:00 AM',
      ),
      isFalse,
    );
    // Other booked slots still count as booked.
    expect(
      controller.isSlotBookedExcluding(
        '2026-08-02',
        '10:00 AM',
        excludeDate: '2026-08-01',
        excludeTime: '9:00 AM',
      ),
      isTrue,
    );
    // Free slots stay free.
    expect(
      controller.isSlotBookedExcluding(
        '2026-08-01',
        '10:00 AM',
        excludeDate: '2026-08-01',
        excludeTime: '9:00 AM',
      ),
      isFalse,
    );
    // Without an exclusion the normal booked check applies.
    expect(
      controller.isSlotBookedExcluding('2026-08-01', '9:00 AM'),
      isTrue,
    );
  });

  test('rescheduleAppointment forwards the new slot and reloads', () async {
    final controller = _TestAppointmentController();
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS1',
      doctorName: 'Dr. Alice Green',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
    );

    final ok = await controller.rescheduleAppointment(
      appointment,
      date: '2026-08-03',
      time: '11:00 AM',
      consultationType: 'clinic',
    );

    expect(ok, isTrue);
    expect(controller.lastAppointmentId, 'APT_RS1');
    expect(controller.lastDate, '2026-08-03');
    expect(controller.lastTime, '11:00 AM');
    expect(controller.lastConsultationType, 'clinic');
    // Default: patient-initiated (doctor-scoped update NOT used).
    expect(controller.lastInitiatedByDoctor, isFalse);
  });

  test('rescheduleAppointment forwards initiatedByDoctor for a clinic move',
      () async {
    final controller = _TestAppointmentController();
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS_DOC',
      doctorName: 'Dr. Alice Green',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
    );

    final ok = await controller.rescheduleAppointment(
      appointment,
      date: '2026-08-04',
      time: '10:30 AM',
      consultationType: 'video',
      initiatedByDoctor: true,
    );

    expect(ok, isTrue);
    expect(controller.lastAppointmentId, 'APT_RS_DOC');
    expect(controller.lastDate, '2026-08-04');
    expect(controller.lastTime, '10:30 AM');
    expect(controller.lastConsultationType, 'video');
    expect(controller.lastInitiatedByDoctor, isTrue);
  });

  test('rescheduleAppointment returns false when the service rejects the '
      'move (slot just taken)', () async {
    final controller = _TestAppointmentController()..acceptMove = false;
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS2',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
    );

    final ok = await controller.rescheduleAppointment(
      appointment,
      date: '2026-08-03',
      time: '11:00 AM',
      consultationType: 'video',
    );

    expect(ok, isFalse);
    // The service was still called with the requested slot.
    expect(controller.lastDate, '2026-08-03');
    expect(controller.lastTime, '11:00 AM');
  });

  test('rescheduleAppointment returns false when no user is logged in',
      () async {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.find<AuthController>().currentUser.value = null;

    // The real guard (userId == null → false) runs before any service call.
    final controller = _GuardTestAppointmentController();
    final appointment = appointmentBasic(
      appointmentId: 'APT_RS3',
      appointmentDate: '2026-08-01',
      appointmentTime: '9:00 AM',
      status: AppointmentStatus.upcoming,
    );

    final ok = await controller.rescheduleAppointment(
      appointment,
      date: '2026-08-03',
      time: '11:00 AM',
      consultationType: 'tele',
    );

    expect(ok, isFalse);
  });
}
