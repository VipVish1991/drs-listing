import 'dart:async' as async;
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/notification_center_controller.dart';
import '../models/appointment_model.dart';
import '../models/doctor_model.dart';
import '../models/doctor_slot_model.dart';
import '../models/payment_model.dart';
import '../services/places_service.dart';
import '../services/room_allocation_service.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../utils/payment_summary.dart';
import '../utils/time_sorter.dart';

class DoctorController extends GetxController {
  final SupabaseService _supabase = SupabaseService();
  final PlacesService _places = PlacesService();

  /// The currently active doctor for the dashboard.
  final Rx<DoctorModel?> currentDoctor = Rx<DoctorModel?>(null);

  /// All appointments for this doctor.
  final RxList<AppointmentModel> appointments = <AppointmentModel>[].obs;

  /// Payments for this doctor's clinics, keyed by appointment_id — powers
  /// the payment line + Mark Paid / Refund actions on the appointments
  /// screen. Loaded via the doctor-scoped payments RLS policy.
  final RxMap<String, PaymentModel> paymentsByAppointment =
      <String, PaymentModel>{}.obs;

  /// Loading states.
  final RxBool isLoadingAppointments = false.obs;
  final RxBool isLoadingStats = false.obs;
  final RxBool isLoadingProfile = false.obs;
  final RxBool isLoadingSlots = false.obs;

  /// The doctor's weekly availability rows (doctor_slots) — shown as the
  /// "available time slots" on the doctor dashboard.
  final RxList<DoctorSlot> doctorSlots = <DoctorSlot>[].obs;

  /// Reactive stats.
  final RxInt totalAppointments = 0.obs;

  /// Today's booked slots — every of today's non-Cancelled appointments
  /// (a slot only frees after the appointment is Cancelled).
  final RxInt todayAppointments = 0.obs;
  final RxInt completedAppointments = 0.obs;
  final RxInt cancelledAppointments = 0.obs;

  /// Total booked slots — all non-Cancelled appointments (shared
  /// AppointmentStatus.occupiesSlot rule).
  final RxInt upcomingAppointments = 0.obs;

  /// Distinct patient count.
  final RxInt totalPatients = 0.obs;

  /// Total payment rows for this doctor's clinics — every consultation fee
  /// record regardless of settlement state (Pending / Paid / Refunded /
  /// Failed). Derived from [paymentsByAppointment] in [loadPayments].
  final RxInt paymentCount = 0.obs;

  /// Collected income — the sum of **Paid** payment amounts only
  /// (pending/refunded/failed money is not income). Powers the Income stat
  /// card on the dashboard. Derived in [loadPayments].
  final RxDouble paidIncome = 0.0.obs;

  /// Outstanding amount — the sum of **Pending** payment amounts (booked
  /// and waiting to be settled at the clinic). Shown on the Income card's
  /// breakdown so the doctor sees what's still owed. Derived in
  /// [loadPayments].
  final RxDouble pendingIncome = 0.0.obs;

  // ── Notification badge state ────────────────────────────────────
  /// Number of unseen appointments (used for badge on the Appointments
  /// tab).  Incremented when polling detects new appointments, reset
  /// to 0 when the doctor opens the Appointments tab.
  final RxInt unseenAppointmentCount = 0.obs;

  /// The number of appointments we knew about at last poll, so we can
  /// detect new ones.
  int _lastKnownAppointmentCount = 0;

  /// Optional polling timer — started/stopped by the dashboard screen.
  async.Timer? _pollTimer;

  /// Set the current doctor and load their data.
  Future<void> setDoctor(DoctorModel doctor) async {
    currentDoctor.value = doctor;
    await Future.wait([
      loadAppointments(),
      loadStats(),
      loadDoctorSlots(),
      loadPayments(),
    ]);
  }

  /// Load payments for the clinics the logged-in user owns and index them
  /// by appointment id. Non-fatal: offline / not logged in simply leaves
  /// the cards without a payment line.
  Future<void> loadPayments() async {
    final userId = Get.find<AuthController>().currentUser.value?.id;
    if (userId == null) return;
    try {
      final rows = await _supabase.getPaymentsForDoctor(userId);
      final payments = rows.map((r) => PaymentModel.fromJson(r)).toList();
      paymentsByAppointment.value = {
        for (final p in payments) p.appointmentId: p,
      };
      // Dashboard stats: total payment rows + settled (Paid) income +
      // outstanding (Pending) amount.
      paymentCount.value = payments.length;
      paidIncome.value = paidIncomeOf(payments);
      pendingIncome.value = pendingIncomeOf(payments);
    } catch (_) {
      // Non-fatal — cards simply show no payment line / zero stats.
    }
  }

  /// Mark a payment Paid / Refunded from the appointments screen. Reloads
  /// the payment map afterwards so the card updates in place. Returns
  /// `true` only when the status flip actually landed server-side — the UI
  /// must not claim a payment was settled that wasn't.
  ///
  /// [refundMethod] / [refundedAt] / [refundUpiId] /
  /// [refundTransactionId] / [refundRawResponse] record how an online or
  /// cash refund was given back (see the refund_details migration).
  Future<bool> markPaymentStatus(
    PaymentModel payment,
    String status, {
    String? refundMethod,
    DateTime? refundedAt,
    String? refundUpiId,
    String? refundTransactionId,
    String? refundRawResponse,
  }) async {
    final userId = Get.find<AuthController>().currentUser.value?.id;
    final paymentId = payment.id;
    if (userId == null || paymentId == null) return false;
    try {
      final ok = await _supabase.updatePaymentStatus(
        userId,
        paymentId,
        status: status,
        paidAt: status == 'Paid' ? DateTime.now() : null,
        refundMethod: refundMethod,
        refundedAt: refundedAt,
        refundUpiId: refundUpiId,
        refundTransactionId: refundTransactionId,
        refundRawResponse: refundRawResponse,
      );
      if (ok) {
        // Notify the patient their payment status changed (fire-and-forget).
        final doctorMobile =
            Get.find<AuthController>().currentUser.value?.mobile;
        async.unawaited(
          NotificationService.instance.notifyPaymentStatusChanged(
            appointmentId: payment.appointmentId,
            paymentStatus: status,
            senderMobile: doctorMobile ?? '',
          ),
        );
        await loadPayments();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Load the doctor's weekly availability slots from `doctor_slots`.
  Future<void> loadDoctorSlots() async {
    final doctor = currentDoctor.value;
    if (doctor == null) return;

    isLoadingSlots.value = true;
    try {
      final slots = await _supabase.getDoctorSlots(doctor.placeId);
      doctorSlots.value = slots;
    } catch (_) {
      // Non-fatal
    } finally {
      isLoadingSlots.value = false;
    }
  }

  /// Load all appointments for this doctor.
  Future<void> loadAppointments() async {
    final doctor = currentDoctor.value;
    if (doctor == null) return;

    isLoadingAppointments.value = true;
    try {
      final userId = Get.find<AuthController>().currentUser.value?.id;
      if (userId == null) return;
      final data = await _supabase.getDoctorAppointments(
        doctor.placeId,
        userId: userId,
      );
      appointments.value = data
          .map((json) => AppointmentModel.fromJson(json))
          .toList();
      _lastKnownAppointmentCount = appointments.length;
    } catch (_) {
      // Non-fatal
    } finally {
      isLoadingAppointments.value = false;
    }
  }

  /// Load stats from Supabase.
  Future<void> loadStats() async {
    final doctor = currentDoctor.value;
    if (doctor == null) return;

    isLoadingStats.value = true;
    try {
      final userId = Get.find<AuthController>().currentUser.value?.id;
      if (userId == null) return;
      final stats = await _supabase.getDoctorAppointmentStats(
        doctor.placeId,
        userId: userId,
      );
      totalAppointments.value = stats['total'] ?? 0;
      todayAppointments.value = stats['today'] ?? 0;
      completedAppointments.value = stats['completed'] ?? 0;
      cancelledAppointments.value = stats['cancelled'] ?? 0;
      upcomingAppointments.value = stats['upcoming'] ?? 0;

      final patientNames = appointments
          .map((a) => a.patientName ?? '')
          .where((n) => n.isNotEmpty)
          .toSet();
      totalPatients.value = patientNames.length;
    } catch (_) {
      // Non-fatal
    } finally {
      isLoadingStats.value = false;
    }
  }

  /// Get appointments for a specific date (date string like '2026-07-20'),
  /// sorted by actual clock time in ASCENDING order — earliest appointment
  /// first (not raw string order, so "9:00 AM" correctly sorts before
  /// "10:00 AM" and "2:00 PM" after "11:00 AM").
  List<AppointmentModel> getAppointmentsForDate(String dateKey) {
    return appointments.where((a) => a.appointmentDate == dateKey).toList()
      ..sort((a, b) {
        final ta = a.appointmentTime ?? '';
        final tb = b.appointmentTime ?? '';
        return timeToMinutes(ta).compareTo(timeToMinutes(tb));
      });
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

  /// Save (or clear, when empty) the clinic's UPI VPA — the address that
  /// receives online consultation fees. Persists to `doctors.upi_id` and
  /// refreshes [currentDoctor] so the profile card updates in place.
  Future<void> updateDoctorUpiId(String upiId) async {
    final doctor = currentDoctor.value;
    if (doctor == null) return;
    final userId = Get.find<AuthController>().currentUser.value?.id;
    if (userId == null) return;
    final trimmed = upiId.trim();
    final updated = doctor.copyWith(upiId: trimmed.isEmpty ? null : trimmed);
    await _supabase.saveDoctorUpiId(
      doctor.placeId,
      updated.upiId,
      userId: userId,
    );
    currentDoctor.value = updated;
  }

  /// Update the doctor profile's display name (doctors table) and refresh
  /// [currentDoctor] so every screen showing it — the dashboard header, the
  /// profile screen and the QR book dialog — updates in place. The name is
  /// capitalized to match the DB formatting in
  /// Update appointment status (Cancel / Complete).
  Future<void> updateAppointmentStatus(
    String appointmentId,
    String status,
  ) async {
    try {
      final userId = Get.find<AuthController>().currentUser.value?.id;
      if (userId == null) return;
      await _supabase.updateAppointmentStatus(
        appointmentId,
        status,
        userId: userId,
      );
      // Push a notification to the patient about their changed status
      // (fire-and-forget — a delivery hiccup must never fail the update).
      final doctorMobile =
          Get.find<AuthController>().currentUser.value?.mobile;
      async.unawaited(
        NotificationService.instance.notifyAppointmentStatusChanged(
          appointmentId: appointmentId,
          status: status,
          senderMobile: doctorMobile ?? '',
        ),
      );
      // The doctor has now acted on this appointment — clear its booking
      // notification from the bell (fire-and-forget, like the push above).
      async.unawaited(
        NotificationCenterController.instance.markAppointmentRead(
          appointmentId,
        ),
      );
      // Free the meeting room when the consultation ends so the next
      // booking can use it (fire-and-forget — a failure must not block
      // the status update).
      if (status == 'Completed' || status == 'Cancelled') {
        async.unawaited(
          RoomAllocationService.instance.freeRoom(appointmentId),
        );
      }
      await loadAppointments();
      await loadStats();
    } catch (_) {}
  }

  /// Save (or clear, when [link] is null) the shared Google Meet URL for
  /// a video/tele consultation. Updates the reactive list IN PLACE on
  /// success so the card / details sheet reflect the link immediately (no
  /// full reload). Returns `true` only when the write actually landed
  /// server-side.
  Future<bool> saveMeetLink(String appointmentId, String? link) async {
    final userId = Get.find<AuthController>().currentUser.value?.id;
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

  /// Mark an appointment Completed AND attach uploaded prescription
  /// photo URL(s). Used by the Tele/Video completion flow after the
  /// doctor captures a prescription photo.
  Future<void> completeAppointmentWithPrescription(
    String appointmentId,
    List<String> urls,
  ) async {
    try {
      final userId = Get.find<AuthController>().currentUser.value?.id;
      if (userId == null) return;
      await _supabase.addPrescriptionUrls(
        appointmentId,
        urls,
        userId: userId,
      );
      await _supabase.updateAppointmentStatus(
        appointmentId,
        'Completed',
        userId: userId,
      );
      // Notify the patient their consultation is complete (fire-and-forget).
      final doctorMobile =
          Get.find<AuthController>().currentUser.value?.mobile;
      async.unawaited(
        NotificationService.instance.notifyAppointmentStatusChanged(
          appointmentId: appointmentId,
          status: 'Completed',
          senderMobile: doctorMobile ?? '',
        ),
      );
      // Clear this appointment's booking notification from the bell too.
      async.unawaited(
        NotificationCenterController.instance.markAppointmentRead(
          appointmentId,
        ),
      );
      // Free the meeting room so the next booking can use it.
      async.unawaited(
        RoomAllocationService.instance.freeRoom(appointmentId),
      );
      await loadAppointments();
      await loadStats();
    } catch (_) {}
  }

  // ── Appointment notification polling ───────────────────────────

  /// Start polling for new appointments every 30 seconds.
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = async.Timer.periodic(const Duration(seconds: 30), (_) {
      _checkForNewAppointments();
    });
  }

  /// Stop polling.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _checkForNewAppointments() async {
    final doctor = currentDoctor.value;
    if (doctor == null) return;

    try {
      final userId = Get.find<AuthController>().currentUser.value?.id;
      if (userId == null) return;
      final data = await _supabase.getDoctorAppointments(
        doctor.placeId,
        userId: userId,
      );
      final currentCount = data.length;
      if (currentCount > _lastKnownAppointmentCount) {
        final newCount = currentCount - _lastKnownAppointmentCount;
        unseenAppointmentCount.value += newCount;
        _lastKnownAppointmentCount = currentCount;
      }
    } catch (_) {
      // Silently ignore poll errors
    }
  }

  /// Reset the unseen badge count (called when the Appointments tab is
  /// opened) and reload the full list.
  Future<void> markAppointmentsSeen() async {
    unseenAppointmentCount.value = 0;
    await loadAppointments();
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  /// Merge Google Places-enriched details with the doctor-set fields from
  /// the DB row (`unavailableRanges`, `experienceYears`) that the
  /// Places API never returns. Without this merge, reloading/saving the
  /// Places model silently drops those fields and screens show "Not set"
  /// even though the DB value is intact.
  ///
  /// Every Places-enrichment site must go through this so the merge can
  /// never drift apart: [loadDoctorFromDb] and
  /// [AuthController.navigateToRoleBasedHome] (both login paths) call it.
  static DoctorModel mergeDoctorSetFields(
    DoctorModel placesDetails,
    DoctorModel? dbDoctor,
    String? userId,
  ) {
    return placesDetails.copyWith(
      userId: userId,
      unavailableRanges: dbDoctor?.unavailableRanges ?? const [],
      experienceYears: dbDoctor?.experienceYears,
      // Doctor-set payment details (UPI VPA) never come from Google
      // Places — without the merge a re-login silently drops the saved
      // VPA and the profile / booking flow shows "Not set".
      upiId: dbDoctor?.upiId,
    );
  }

  /// Load a doctor profile from the DB by placeId and enrich with
  /// full Place Details from the Google Places API (phone, hours,
  /// address, etc.) so the profile page shows complete information.
  Future<void> loadDoctorFromDb(String placeId) async {
    isLoadingProfile.value = true;
    try {
      final userId = Get.find<AuthController>().currentUser.value?.id;

      // 1. Load basic data from Supabase DB
      final dbDoctor = await _supabase.getDoctorFromDb(placeId);

      // 2. Try to fetch complete details from Google Places API
      try {
        final fullDetails = await _places.getDoctorDetails(placeId);
        if (fullDetails != null) {
          // Merge the Places-enriched model with doctor-set fields from the
          // DB (unavailableRanges, experienceYears) that Google Places
          // never returns. Without this, saving the Places model
          // overwrites the local currentDoctor with a model that has no
          // doctor-set state, and the profile screen shows "Not set" even
          // though the DB value is intact.
          final enriched = mergeDoctorSetFields(fullDetails, dbDoctor, userId);
          currentDoctor.value = enriched;
          await _supabase.saveDoctorToDb(enriched);
          return;
        }
      } catch (_) {
        // Non-fatal; fall through to DB data
      }

      // 3. Fall back to whatever DB data we have
      if (dbDoctor != null) {
        currentDoctor.value = dbDoctor;
      }
    } finally {
      isLoadingProfile.value = false;
    }
  }
}
