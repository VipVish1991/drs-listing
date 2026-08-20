import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/appointment_model.dart';
import '../models/doctor_model.dart';
import '../models/doctor_slot_model.dart';
import '../models/payment_model.dart';
import '../services/meet_consult_service.dart';
import '../services/supabase_service.dart';
import '../controllers/auth_controller.dart';
import '../controllers/doctor_controller.dart';
import '../services/notification_service.dart';
import '../utils/text_capitalizer.dart';
import '../utils/time_sorter.dart';

class AppointmentController extends GetxController {
  final SupabaseService _supabase = SupabaseService();
  final AuthController _authController = Get.find<AuthController>();

  final RxList<AppointmentModel> appointments = <AppointmentModel>[].obs;
  final RxBool isLoading = false.obs;

  // Booking form fields
  final RxString patientName = ''.obs;
  final RxString appointmentDate = ''.obs;
  final RxString appointmentTime = ''.obs;
  final RxString symptoms = ''.obs;

  // ── Slot-based booking ───────────────────────────────────────
  /// All available slots for the currently-viewed doctor.
  final RxList<DoctorSlot> doctorSlots = <DoctorSlot>[].obs;

  /// The day-of-week corresponding to the selected date.
  final RxString selectedDayOfWeek = ''.obs;

  /// Load slots for a doctor from the [doctor_slots] table.
  Future<void> loadDoctorSlots(String doctorPlaceId) async {
    try {
      final slots = await _supabase.getDoctorSlots(doctorPlaceId);
      doctorSlots.value = slots;
    } catch (_) {
      doctorSlots.clear();
    }
  }

  /// Get all available time slot strings for a given day of the week.
  /// Returns a sorted list of unique time strings like "09:00 AM".
  List<String> getTimeSlotsForDay(String dayOfWeek) {
    final daySlots = doctorSlots.where(
      (s) => s.dayOfWeek == dayOfWeek && s.isEnabled && s.slots.isNotEmpty,
    );
    final allSlots = <String>{};
    for (final s in daySlots) {
      allSlots.addAll(s.slots);
    }
    final sorted = allSlots.toList()..sort(compareTimeStrings);
    return sorted;
  }

  /// Get the schedule type label for a given time slot.
  String getSlotTypeLabel(String timeSlot) {
    for (final s in doctorSlots) {
      if (s.slots.contains(timeSlot)) {
        return s.scheduleType;
      }
    }
    return 'general';
  }

  /// Check if a given day-of-week has any available slots.
  bool hasSlotsForDay(String dayOfWeek) {
    return doctorSlots.any(
      (s) => s.dayOfWeek == dayOfWeek && s.isEnabled && s.slots.isNotEmpty,
    );
  }

  /// Keys of already-booked slots for the doctor currently being booked,
  /// in the form `yyyy-MM-dd|HH:MM AM`. Populated by [loadBookedSlots]
  /// so the booking screen can disable slots that are already taken.
  final RxSet<String> bookedSlotKeys = <String>{}.obs;

  /// Fetch which date|time combinations are already booked for
  /// [doctorPlaceId] and record them so the booking screen can disable
  /// taken slots. Uses the minimal `get_booked_slot_keys` RPC — the
  /// booking flow must NOT read other patients' appointment rows, so it
  /// never calls the owner-scoped appointments SELECT directly. Every
  /// appointment status (Pending / Upcoming / Completed / …) disables its
  /// slot — the slot is only freed again once the appointment is
  /// Cancelled. See [AppointmentStatus.occupiesSlot].
  Future<void> loadBookedSlots(String doctorPlaceId) async {
    try {
      final keys = await _supabase.getBookedSlotKeys(doctorPlaceId);
      bookedSlotKeys.assignAll(
        keys.where((key) => !key.startsWith('|') && !key.endsWith('|')),
      );
    } catch (_) {
      // Network/connection errors — treat nothing as booked so the user
      // can still attempt to book; the server enforces the real rule.
      bookedSlotKeys.clear();
    }
  }

  /// True if the given date+time slot is already booked — any appointment
  /// status occupies the slot; only a Cancelled appointment frees it.
  /// See [AppointmentStatus.occupiesSlot].
  bool isSlotBooked(String isoDate, String timeSlot) {
    return bookedSlotKeys.contains('$isoDate|$timeSlot');
  }

  /// True if the given date+time slot is booked, ignoring the appointment
  /// currently being rescheduled — its own slot is naturally in
  /// [bookedSlotKeys] (it occupies its slot), but it must stay selectable
  /// so the patient can keep the same slot or move away from it. See
  /// [isSlotBooked].
  bool isSlotBookedExcluding(
    String isoDate,
    String timeSlot, {
    String? excludeDate,
    String? excludeTime,
  }) {
    if (excludeDate != null &&
        excludeTime != null &&
        isoDate == excludeDate &&
        timeSlot == excludeTime) {
      return false;
    }
    return isSlotBooked(isoDate, timeSlot);
  }

  /// True if the given date+time slot has already passed by the current
  /// time (so it can't be booked any more).
  bool isSlotInPast(String isoDate, String timeSlot) {
    final dt = _parseSlotDateTime(isoDate, timeSlot);
    return dt != null && dt.isBefore(DateTime.now());
  }

  /// Parse a `yyyy-MM-dd` + `HH:MM AM/PM` pair into a [DateTime].
  DateTime? _parseSlotDateTime(String isoDate, String timeSlot) {
    try {
      final dateParts = isoDate.split('-');
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);
      final cleaned = timeSlot.trim().toUpperCase();
      final isPm = cleaned.endsWith('PM');
      final timeOnly = cleaned.replaceAll('AM', '').replaceAll('PM', '').trim();
      final timeParts = timeOnly.split(':');
      var hour = int.parse(timeParts[0]);
      final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  /// Get all unique appointment dates (sorted) for the date picker.
  List<String> get uniqueAppointmentDates {
    final dates = appointments
        .map((a) => a.appointmentDate ?? '')
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    dates.sort();
    return dates;
  }

  /// Appointments for [dateKey] sorted by real clock time ascending, so
  /// the earliest consultation of the day sits on top (matches the
  /// doctor's appointments screen ordering).
  List<AppointmentModel> getAppointmentsForDate(String dateKey) {
    return appointments.where((a) => a.appointmentDate == dateKey).toList()
      ..sort((a, b) {
        final ta = a.appointmentTime ?? '';
        final tb = b.appointmentTime ?? '';
        return timeToMinutes(ta).compareTo(timeToMinutes(tb));
      });
  }

  /// The status an appointment effectively shows right now: Cancelled
  /// stays Cancelled, Pending bookings are never auto-completed, and an
  /// Upcoming appointment whose time has passed renders as Completed. This
  /// is the single source of truth shared by the history screen's cards
  /// (via their display status).
  String effectiveStatus(AppointmentModel appointment) {
    if (appointment.status == 'Cancelled') return 'Cancelled';
    if (appointment.status == AppointmentStatus.pending) {
      return AppointmentStatus.pending;
    }
    final dt = _parseAppointmentDateTime(appointment);
    if (dt != null && dt.isBefore(DateTime.now())) return 'Completed';
    return appointment.status;
  }

  /// Parse an appointment's `yyyy-MM-dd` + `HH:MM AM/PM` into a [DateTime].
  static DateTime? _parseAppointmentDateTime(AppointmentModel appointment) {
    final dateStr = appointment.appointmentDate;
    final timeStr = appointment.appointmentTime;
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      final dateParts = dateStr.split('-');
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);
      var hour = 0;
      var minute = 0;
      if (timeStr != null && timeStr.isNotEmpty) {
        final cleaned = timeStr.trim().toUpperCase();
        final isPm = cleaned.endsWith('PM');
        final timeOnly = cleaned
            .replaceAll('AM', '')
            .replaceAll('PM', '')
            .trim();
        final timeParts = timeOnly.split(':');
        hour = int.parse(timeParts[0]);
        minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
        if (isPm && hour != 12) hour += 12;
        if (!isPm && hour == 12) hour = 0;
      }
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  @override
  void onInit() {
    super.onInit();
    if (_authController.isLoggedIn.value) {
      loadAppointments();
    }
  }

  Future<void> loadAppointments() async {
    final userId = _authController.currentUser.value?.id;
    if (userId == null) return;

    isLoading.value = true;
    try {
      final data = await _supabase.getUserAppointments(userId);
      appointments.value = data
          .map((json) => AppointmentModel.fromJson(json))
          .toList();
    } on TimeoutException {
      // Network timeout — keep existing list, don't crash
    } catch (_) {
      // Network/connection errors — keep existing list, don't crash
    } finally {
      isLoading.value = false;
    }
  }

  /// The "one patient, one doctor at a time" cooldown: a patient may hold
  /// at most ONE active (Pending/Upcoming) appointment, and the next
  /// booking is only allowed once this much time has passed since their
  /// most recent booking was CREATED (Completed / Cancelled bookings still
  /// trigger the wait). Mirrored server-side by the booking-page Edge
  /// Function (supabase/functions/booking-page/index.ts) so the web/QR
  /// flow can't bypass it.
  /// Set when the DB-level gate (the `enforce_one_active_booking_rule`
  /// trigger) rejects an insert with the one-active-booking-per-doctor
  /// marker — i.e. the patient booked on another device (or their earlier
  /// booking landed) in the window between the screen's pre-book check and
  /// the actual insert. The booking screen surfaces this instead of the
  /// generic failure snackbar, then clears it. Null when no gate rejection
  /// has happened. Plain field (not reactive) — the booking screen is its
  /// only consumer.
  String? serverBookingBlockMessage;

  /// Maps a booking-insert exception to the friendly per-doctor gate
  /// message, or null when the error is NOT a gate rejection (slot taken,
  /// network, RLS, …). Matches the marker prefix raised by the DB trigger
  /// `enforce_one_active_booking_rule` (same wording the Edge Function
  /// maps it to).
  static String? bookingBlockMessageFromError(Object error) {
    final message = error.toString();
    if (message.contains('appointments_one_active_booking')) {
      return 'You already have an active appointment with this doctor. '
          'Please wait for it to be completed or cancelled before '
          'booking again.';
    }
    return null;
  }

  /// The message to show when the "one active booking per doctor" gate
  /// blocks a new booking, or null when booking is allowed.
  ///
  /// [appointments] must be the patient's CURRENT appointments — call
  /// [loadAppointments] first so the check reflects the latest bookings
  /// (the booking screen refreshes right before the check).
  ///
  /// [doctorPlaceId] is the doctor being booked. Only an active
  /// (Pending/Upcoming) appointment with the SAME doctor blocks — the
  /// patient may hold active bookings with other doctors simultaneously,
  /// and may book the same doctor again immediately once the current
  /// booking is Completed or Cancelled (no cooldown). When
  /// [doctorPlaceId] is null (no specific doctor, e.g. the history
  /// screen), a neutral notice is returned only while the patient holds
  /// ANY active booking.
  static String? bookingBlockMessage(
    List<AppointmentModel> appointments, {
    String? doctorPlaceId,
  }) {
    var hasActive = false;
    for (final a in appointments) {
      // Use effective-status logic: an Upcoming appointment whose
      // time has passed is effectively Completed, so it must not
      // block a new booking.
      final isActive = a.status == AppointmentStatus.pending ||
          a.status == AppointmentStatus.upcoming;
      if (!isActive) continue;
      if (a.status == AppointmentStatus.upcoming) {
        final dt = _parseAppointmentDateTime(a);
        if (dt != null && dt.isBefore(DateTime.now())) continue;
      }
      hasActive = true;
      if (doctorPlaceId != null && a.doctorPlaceId == doctorPlaceId) {
        return 'You already have an active appointment with this doctor. '
            'Please wait for it to be completed or cancelled before '
            'booking again.';
      }
    }
    // No specific doctor target (e.g. the history screen): surface the
    // notice while any active booking exists, so the patient isn't
    // surprised when their next attempt at the same doctor is blocked.
    if (doctorPlaceId == null && hasActive) {
      return 'You have an active appointment. Complete or cancel it '
          'before booking with the same doctor again.';
    }
    return null;
  }

  /// Book an appointment, optionally recording the consultation payment.
  ///
  /// [payment] is an offline "pay at clinic" record (status 'Pending',
  /// method 'offline') built by the booking screen. The payment row's
  /// `appointment_id` is filled with the generated appointment id so the
  /// history links both tables. A payment insert failure never fails the
  /// booking itself (the appointment already exists and the patient can
  /// pay later / at the clinic).
  Future<bool> bookAppointment(
    DoctorModel doctor, {
    PaymentModel? payment,
  }) async {
    final userId = _authController.currentUser.value?.id;
    if (userId == null) return false;

    isLoading.value = true;
    try {
      // Generate a globally-unique appointment ID. A sequential ID based
      // on the local list length (APT1001, APT1002, …) collides across
      // users and after re-booking, failing the insert with a duplicate
      // primary key. Timestamp-based IDs match the format used by the
      // browser booking-page function and are collision-proof.
      final aptId = 'APT${DateTime.now().millisecondsSinceEpoch}';

      final data = <String, dynamic>{
        'appointment_id': aptId,
        'user_id': userId,
        'patient_name': capitalizeWords(patientName.value),
        'doctor_name': capitalizeWords(doctor.name),
        'doctor_place_id': doctor.placeId,
        'doctor_details': doctor.toJson(),
        'appointment_date': appointmentDate.value,
        'appointment_time': appointmentTime.value,
        'symptoms': capitalizeWords(symptoms.value),
        'status': 'Upcoming',
        // The schedule type of the selected slot (tele/video/clinic) —
        // used by the doctor side to offer the prescription upload only
        // for Tele/Video consultations.
        'consultation_type': getSlotTypeLabel(appointmentTime.value),
        // Every new appointment carries the SAME static Google Meet room
        // so the patient and clinic always join one fixed meeting — never
        // a fresh per-appointment event.
        'meet_link': kStaticMeetLink,
      };
      // Never persist an unknown/empty type (would read as legacy row).
      if ((data['consultation_type'] ?? '').isEmpty) {
        data.remove('consultation_type');
      }

      // Optional fields — omitted entirely when the doctor record doesn't
      // provide them, so the insert never fails on null JSONB/text columns.
      if ((doctor.phoneNumber ?? '').isNotEmpty) {
        data['call_number'] = doctor.phoneNumber;
      }
      // The patient's own mobile — the doctor side uses it to call the
      // patient back (call_number above is the doctor's number).
      final patientMobile = _authController.currentUser.value?.mobile;
      if ((patientMobile ?? '').isNotEmpty) {
        data['patient_phone'] = patientMobile;
      }
      if (doctor.latitude != null && doctor.longitude != null) {
        data['map_location'] = {
          'latitude': doctor.latitude,
          'longitude': doctor.longitude,
        };
      }

      await _supabase.createAppointment(data);

      // Record the consultation payment (offline pay-at-clinic)
      // linked to this appointment. Failure is non-fatal — the appointment
      // is booked either way.
      if (payment != null) {
        try {
          await _supabase.createPayment(
            userId,
            payment
                .copyWith(
                  appointmentId: aptId,
                  paidAt: payment.isPaid ? DateTime.now() : null,
                )
                .toJson(),
          );
        } catch (e) {
          debugPrint('⚠️ Failed to record payment $aptId: $e');
        }
      }

      // Push a notification to the doctor (fire-and-forget — a delivery
      // hiccup must never fail the booking).
      unawaited(
        NotificationService.instance.notifyAppointmentBooked(
          appointmentId: aptId,
          senderMobile: patientMobile ?? '',
        ),
      );
      await loadAppointments();
      return true;
    } catch (e) {
      // The DB-level rules rejected the insert — e.g. the slot rule
      // (enforce_slot_booking_rule: a slot is occupied by every status
      // except Cancelled) caught another patient taking the slot in the
      // instant since the screen's pre-check, or the one-active-booking
      // gate (enforce_one_active_booking_rule) caught the patient booking
      // elsewhere within the 12h window. Return false so the screen shows
      // its failure snackbar instead of crashing on the thrown exception
      // — and when the gate markers are present, record WHICH gate message
      // to surface instead of the generic "Failed to book appointment".
      serverBookingBlockMessage = bookingBlockMessageFromError(e);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Move a Pending/Upcoming appointment to a new date+time slot.
  ///
  /// [consultationType] is the schedule type of the NEW slot (tele /
  /// video / clinic) — derived by the screen via [getSlotTypeLabel] so
  /// the stored type stays in sync with the slot the patient picked. The
  /// DB trigger `enforce_slot_booking_rule` rejects the move if the new
  /// slot was just taken by someone else (returns false).
  ///
  /// [initiatedByDoctor] switches the flow from the patient (default) to
  /// the clinic: the DB update is not scoped to a patient `user_id` (the
  /// doctor isn't the row's owner — see
  /// [SupabaseService.rescheduleAppointmentAsDoctor]), the PATIENT is the
  /// one notified (distinct `appointment_rescheduled_by_doctor` event so
  /// the two directions are distinguishable + separately opt-out-able),
  /// and the doctor's clinic list reloads instead of the patient's.
  Future<bool> rescheduleAppointment(
    AppointmentModel appointment, {
    required String date,
    required String time,
    required String consultationType,
    bool initiatedByDoctor = false,
  }) async {
    final userId = _authController.currentUser.value?.id;
    if (userId == null) return false;

    isLoading.value = true;
    try {
      final ok = initiatedByDoctor
          ? await _supabase.rescheduleAppointmentAsDoctor(
              appointment.appointmentId,
              userId: userId,
              date: date,
              time: time,
              consultationType: consultationType,
            )
          : await _supabase.rescheduleAppointment(
              appointment.appointmentId,
              userId: userId,
              date: date,
              time: time,
              consultationType: consultationType,
            );
      if (!ok) return false;

      if (initiatedByDoctor) {
        // Let the PATIENT know the clinic moved their booking
        // (fire-and-forget — a delivery hiccup must never fail the
        // reschedule).
        unawaited(
          NotificationService.instance.notifyAppointmentRescheduledByDoctor(
            appointmentId: appointment.appointmentId,
            senderMobile: _authController.currentUser.value?.mobile ?? '',
          ),
        );
        // Refresh the doctor's clinic appointments so the moved booking
        // shows its new slot on return (non-fatal — the appointments
        // screen reloads on open anyway).
        try {
          await Get.find<DoctorController>().loadAppointments();
        } catch (_) {}
      } else {
        // Let the doctor know the patient moved the booking (fire-and-
        // forget — a delivery hiccup must never fail the reschedule).
        unawaited(
          NotificationService.instance.notifyAppointmentRescheduled(
            appointmentId: appointment.appointmentId,
            senderMobile: _authController.currentUser.value?.mobile ?? '',
          ),
        );
        await loadAppointments();
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> cancelAppointment(String appointmentId) async {
    final userId = _authController.currentUser.value?.id;
    if (userId == null) return;
    try {
      await _supabase.updateAppointmentStatus(
        appointmentId,
        'Cancelled',
        userId: userId,
      );
      // Let the doctor know the patient cancelled (fire-and-forget).
      unawaited(
        NotificationService.instance.notifyAppointmentCancelled(
          appointmentId: appointmentId,
          senderMobile: _authController.currentUser.value?.mobile ?? '',
        ),
      );
      await loadAppointments();
    } catch (_) {}
  }

  /// Save (or clear, when [link] is null) the shared Google Meet URL for
  /// a video/tele consultation. Updates the reactive list IN PLACE on
  /// success so the card / details sheet reflect the link immediately (no
  /// full reload). Returns `true` only when the write actually landed
  /// server-side.
  Future<bool> saveMeetLink(String appointmentId, String? link) async {
    final userId = _authController.currentUser.value?.id;
    if (userId == null) return false;
    try {
      final ok = await _supabase.updateAppointmentMeetLink(
        appointmentId,
        link,
        userId: userId,
      );
      if (ok) {
        final i = appointments.indexWhere(
          (a) => a.appointmentId == appointmentId,
        );
        if (i >= 0) appointments[i] = appointments[i].copyWith(meetLink: link);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> completeAppointment(String appointmentId) async {
    final userId = _authController.currentUser.value?.id;
    if (userId == null) return;
    try {
      await _supabase.updateAppointmentStatus(
        appointmentId,
        'Completed',
        userId: userId,
      );
      await loadAppointments();
    } catch (_) {}
  }

  void resetForm() {
    patientName.value = '';
    appointmentDate.value = '';
    appointmentTime.value = '';
    symptoms.value = '';
  }
}
