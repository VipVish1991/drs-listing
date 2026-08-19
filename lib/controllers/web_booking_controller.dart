import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/auth_controller.dart';
import '../models/appointment_model.dart';
import '../models/doctor_model.dart';
import '../models/doctor_slot_model.dart';
import '../models/payment_model.dart';
import '../services/meet_consult_service.dart';
import '../services/supabase_service.dart';

/// Controller for the web-based booking screen (browser / Flutter web).
///
/// Manages doctor data loading, slot availability, form state, UPI
/// payment flow, booking submission, and full history with details.
class WebBookingController extends GetxController {
  final SupabaseService _supabase = SupabaseService();

  // ── Web user registration (browser-only) ───────────────────────
  final RxBool isRegistered = false.obs;
  final RxString webUserName = ''.obs;
  final RxString webUserPhone = ''.obs;
  final RxString webUserSymptoms = ''.obs;
  final RxString regError = ''.obs;
  final RxBool isRegistering = false.obs;
  String _webUserId = '';

  // ── Doctor data ──────────────────────────────────────────────────
  final Rxn<DoctorModel> doctor = Rxn<DoctorModel>();
  final RxBool isLoadingDoctor = true.obs;
  final RxString doctorError = ''.obs;

  // ── Slots ────────────────────────────────────────────────────────
  final RxList<DoctorSlot> doctorSlots = <DoctorSlot>[].obs;
  final RxString selectedDayOfWeek = ''.obs;
  final RxSet<String> bookedSlotKeys = <String>{}.obs;
  final RxBool isLoadingSlots = true.obs;

  // ── Form state ───────────────────────────────────────────────────
  final RxString patientName = ''.obs;
  final RxString patientPhone = ''.obs;
  final RxString symptoms = ''.obs;
  final RxString selectedDate = ''.obs;
  final RxString selectedTimeSlot = ''.obs;
  final RxString selectedType = ''.obs;
  final RxInt selectedDateIndex = (-1).obs;

  // ── Payment ──────────────────────────────────────────────────────
  final RxBool isProcessingPayment = false.obs;
  final RxString paymentMethod = ''.obs; // 'online' | 'offline'

  // ── Booking result ───────────────────────────────────────────────
  final RxBool isBooking = false.obs;
  final RxBool bookingSuccess = false.obs;
  final RxString bookingError = ''.obs;
  final Rxn<String> bookedAppointmentId = Rxn<String>();

  // ── History ──────────────────────────────────────────────────────
  final RxList<AppointmentModel> historyAppointments =
      <AppointmentModel>[].obs;
  final RxMap<String, PaymentModel> historyPayments =
      <String, PaymentModel>{}.obs;
  final RxBool isLoadingHistory = false.obs;

  // ── Expanded history card (detail view) ──────────────────────────
  final RxString expandedAppointmentId = ''.obs;

  // ── Date options ─────────────────────────────────────────────────

  List<DateOption> get dateOptions {
    final now = DateTime.now();
    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return List.generate(14, (i) {
      final d = now.add(Duration(days: i));
      return DateOption(date: d, dayOfWeek: dayNames[d.weekday - 1]);
    });
  }

  // ── Slot helpers ─────────────────────────────────────────────────

  List<DoctorSlot> daySchedules(String dayOfWeek) {
    const order = ['tele', 'video', 'clinic'];
    return doctorSlots
        .where((s) =>
            s.dayOfWeek == dayOfWeek && s.isEnabled && s.slots.isNotEmpty)
        .toList()
      ..sort((a, b) =>
          order.indexOf(a.scheduleType).compareTo(order.indexOf(b.scheduleType)));
  }

  bool isDateUnavailable(DateOption opt) {
    final doc = doctor.value;
    if (doc == null) return false;
    return doc.unavailableRanges.any((r) => r.contains(opt.date));
  }

  bool isSlotBooked(String isoDate, String timeSlot) =>
      bookedSlotKeys.contains('$isoDate|$timeSlot');

  bool isSlotInPast(String isoDate, String timeSlot) {
    final dt = _parseSlotDateTime(isoDate, timeSlot);
    return dt != null && dt.isBefore(DateTime.now());
  }

  int feeFor(String dayOfWeek, String type) {
    for (final s in doctorSlots) {
      if (s.dayOfWeek == dayOfWeek && s.scheduleType == type && s.isEnabled) {
        return s.fee;
      }
    }
    switch (type) {
      case 'tele': return 500;
      case 'video': return 800;
      case 'clinic': return 1000;
      default: return 0;
    }
  }

  int get selectedFee {
    if (selectedType.isEmpty || selectedDate.isEmpty) return 0;
    final opt = dateOptions.where((o) => o.isoDate == selectedDate.value).firstOrNull;
    if (opt == null) return 0;
    return feeFor(opt.dayOfWeek, selectedType.value);
  }

  String? get upiId => doctor.value?.upiId;

  bool get canBook =>
      doctor.value != null &&
      selectedDate.value.isNotEmpty &&
      selectedTimeSlot.value.isNotEmpty &&
      selectedType.value.isNotEmpty &&
      patientName.value.trim().isNotEmpty &&
      patientPhone.value.trim().isNotEmpty &&
      !isBooking.value;

  // ── Web user registration / login ───────────────────────────────

  /// Restores a previous web session from SharedPreferences.
  Future<void> restoreWebSession() async {
    if (!kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('web_user_name') ?? '';
      final phone = prefs.getString('web_user_phone') ?? '';
      final uid = prefs.getString('web_user_id') ?? '';
      if (name.isNotEmpty && phone.isNotEmpty && uid.isNotEmpty) {
        webUserName.value = name;
        webUserPhone.value = phone;
        _webUserId = uid;
        isRegistered.value = true;
        patientName.value = name;
        patientPhone.value = phone;
      }
    } catch (_) {}
  }

  /// Registers a new web user (name + mobile) in Supabase or
  /// finds an existing one by mobile, then persists the session.
  Future<void> registerWebUser() async {
    regError.value = '';
    final name = webUserName.value.trim();
    final phone = webUserPhone.value.trim();
    if (name.isEmpty) { regError.value = 'Please enter your name.'; return; }
    if (phone.isEmpty || phone.length < 10) { regError.value = 'Please enter a valid 10-digit mobile number.'; return; }

    isRegistering.value = true;
    try {
      // Try to find existing user by mobile
      final existing = await _supabase.findUserByMobile(phone);
      if (existing != null && existing['id'] != null) {
        _webUserId = existing['id'].toString();
      } else {
        // Create new user
        final newUser = await _supabase.createWebUser(name: name, mobile: phone);
        _webUserId = newUser['id'].toString();
      }

      // Persist session
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('web_user_name', name);
        await prefs.setString('web_user_phone', phone);
        await prefs.setString('web_user_id', _webUserId);
      }

      webUserName.value = name;
      webUserPhone.value = phone;
      patientName.value = name;
      patientPhone.value = phone;
      isRegistered.value = true;
    } catch (e) {
      regError.value = 'Registration failed. Please try again.';
    } finally {
      isRegistering.value = false;
    }
  }

  /// Logs out the web user (clears session).
  void logoutWebUser() {
    isRegistered.value = false;
    webUserName.value = '';
    webUserPhone.value = '';
    webUserSymptoms.value = '';
    _webUserId = '';
    patientName.value = '';
    patientPhone.value = '';
    symptoms.value = '';
    if (kIsWeb) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('web_user_name');
        prefs.remove('web_user_phone');
        prefs.remove('web_user_id');
      });
    }
  }

  // ── Init ─────────────────────────────────────────────────────────

  Future<void> loadDoctor(String placeId) async {
    isLoadingDoctor.value = true;
    doctorError.value = '';
    try {
      final doc = await _supabase.getDoctorFromDb(placeId);
      if (doc != null) {
        doctor.value = doc;
        await loadSlots(placeId);
      } else {
        doctorError.value = 'Doctor not found.';
      }
    } catch (_) {
      doctorError.value = 'Failed to load doctor details. Please try again.';
    } finally {
      isLoadingDoctor.value = false;
    }
  }

  Future<void> loadSlots(String placeId) async {
    isLoadingSlots.value = true;
    try {
      final results = await Future.wait([
        _supabase.getDoctorSlots(placeId),
        _supabase.getBookedSlotKeys(placeId),
      ]);
      doctorSlots.value = results[0] as List<DoctorSlot>;
      final keys = results[1] as List<String>;
      bookedSlotKeys.assignAll(
        keys.where((key) => !key.startsWith('|') && !key.endsWith('|')),
      );
      _autoSelectToday();
    } catch (_) {
      doctorSlots.clear();
      bookedSlotKeys.clear();
    } finally {
      isLoadingSlots.value = false;
    }
  }

  void _autoSelectToday() {
    final today = dateOptions.first;
    if (isDateUnavailable(today)) return;
    for (final s in daySchedules(today.dayOfWeek)) {
      for (final slot in s.slots) {
        if (isSlotBooked(today.isoDate, slot)) continue;
        if (isSlotInPast(today.isoDate, slot)) continue;
        selectedDateIndex.value = 0;
        selectedDate.value = today.isoDate;
        selectedTimeSlot.value = slot;
        selectedType.value = s.scheduleType;
        selectedDayOfWeek.value = today.dayOfWeek;
        return;
      }
    }
  }

  void selectDate(int index) {
    final opt = dateOptions[index];
    selectedDateIndex.value = index;
    selectedDate.value = opt.isoDate;
    selectedTimeSlot.value = '';
    selectedType.value = '';
    selectedDayOfWeek.value = opt.dayOfWeek;
  }

  void selectSlot(String timeSlot, String type) {
    selectedTimeSlot.value = timeSlot;
    selectedType.value = type;
  }

  /// Toggle expanded state of a history card.
  void toggleExpand(String appointmentId) {
    if (expandedAppointmentId.value == appointmentId) {
      expandedAppointmentId.value = '';
    } else {
      expandedAppointmentId.value = appointmentId;
    }
  }

  // ── Booking ──────────────────────────────────────────────────────

  Future<void> bookAppointment() async {
    if (!canBook) return;
    final doc = doctor.value!;
    isBooking.value = true;
    bookingError.value = '';
    bookingSuccess.value = false;

    try {
      final aptId = 'APT${DateTime.now().millisecondsSinceEpoch}';
      final userId = _resolveUserId();

      final data = <String, dynamic>{
        'appointment_id': aptId,
        'user_id': userId,
        'patient_name': patientName.value.trim(),
        'doctor_name': doc.name,
        'doctor_place_id': doc.placeId,
        'doctor_details': doc.toJson(),
        'appointment_date': selectedDate.value,
        'appointment_time': selectedTimeSlot.value,
        'symptoms': symptoms.value.trim(),
        'status': 'Upcoming',
        'consultation_type': selectedType.value,
        'meet_link': kStaticMeetLink,
        'patient_phone': patientPhone.value.trim(),
      };
      if (doc.phoneNumber != null && doc.phoneNumber!.isNotEmpty) {
        data['call_number'] = doc.phoneNumber;
      }
      if (doc.latitude != null && doc.longitude != null) {
        data['map_location'] = {
          'latitude': doc.latitude,
          'longitude': doc.longitude,
        };
      }

      await _supabase.createAppointment(data);

      // Record payment.
      final fee = selectedFee;
      if (fee > 0) {
        final payment = PaymentModel(
          appointmentId: aptId,
          patientId: userId,
          doctorPlaceId: doc.placeId,
          doctorName: doc.name,
          consultationType: selectedType.value,
          paymentStatus: paymentMethod.value == 'online' ? 'Paid' : 'Pending',
          paymentMethod:
              paymentMethod.value.isEmpty ? 'offline' : paymentMethod.value,
          amount: fee.toDouble(),
        );
        try {
          await _supabase.createPayment(userId, payment.toJson());
        } catch (_) {}
      }

      bookedAppointmentId.value = aptId;
      bookingSuccess.value = true;
      await loadHistory();
    } catch (e) {
      bookingError.value = 'Failed to book appointment. Please try again.';
    } finally {
      isBooking.value = false;
    }
  }

  Future<void> cancelAppointment(String appointmentId) async {
    final userId = _resolveUserId();
    if (userId.isEmpty) return;
    try {
      await _supabase.updateAppointmentStatus(
        appointmentId,
        'Cancelled',
        userId: userId,
      );
      await loadHistory();
    } catch (_) {}
  }

  void resetForm() {
    patientName.value = '';
    patientPhone.value = '';
    symptoms.value = '';
    selectedDate.value = '';
    selectedTimeSlot.value = '';
    selectedType.value = '';
    selectedDateIndex.value = -1;
    paymentMethod.value = '';
    bookingSuccess.value = false;
    bookingError.value = '';
    bookedAppointmentId.value = null;
    expandedAppointmentId.value = '';
    _autoSelectToday();
  }

  // ── History ──────────────────────────────────────────────────────

  Future<void> loadHistory() async {
    isLoadingHistory.value = true;
    try {
      final userId = _resolveUserId();
      if (userId.isEmpty) return;

      final rows = await _supabase.getUserAppointments(userId);
      historyAppointments.value =
          rows.map((j) => AppointmentModel.fromJson(j)).toList()
            ..sort((a, b) {
              final da = a.appointmentDate ?? '';
              final db = b.appointmentDate ?? '';
              final cmp = db.compareTo(da);
              if (cmp != 0) return cmp;
              return (b.appointmentTime ?? '').compareTo(a.appointmentTime ?? '');
            });

      final payments = await _supabase.getPaymentsForUser(userId);
      historyPayments.clear();
      for (final p in payments) {
        final pm = PaymentModel.fromJson(p);
        historyPayments[pm.appointmentId] = pm;
      }
    } catch (_) {} finally {
      isLoadingHistory.value = false;
    }
  }

  String effectiveStatus(AppointmentModel a) {
    if (a.status == 'Cancelled') return 'Cancelled';
    if (a.status == 'Pending') return 'Pending';
    final dt = _parseAppointmentDateTime(a);
    if (dt != null && dt.isBefore(DateTime.now())) return 'Completed';
    return a.status;
  }

  // ── Private helpers ──────────────────────────────────────────────

  String _resolveUserId() {
    try {
      return Get.find<AuthController>().currentUser.value?.id ?? '';
    } catch (_) {
      return '';
    }
  }

  DateTime? _parseSlotDateTime(String isoDate, String timeSlot) {
    try {
      final parts = isoDate.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final cleaned = timeSlot.trim().toUpperCase();
      final isPm = cleaned.endsWith('PM');
      final timeOnly =
          cleaned.replaceAll('AM', '').replaceAll('PM', '').trim();
      final tp = timeOnly.split(':');
      var hour = int.parse(tp[0]);
      final minute = tp.length > 1 ? int.parse(tp[1]) : 0;
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseAppointmentDateTime(AppointmentModel a) {
    final dateStr = a.appointmentDate;
    final timeStr = a.appointmentTime;
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      final parts = dateStr.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      var hour = 0;
      var minute = 0;
      if (timeStr != null && timeStr.isNotEmpty) {
        final cleaned = timeStr.trim().toUpperCase();
        final isPm = cleaned.endsWith('PM');
        final timeOnly =
            cleaned.replaceAll('AM', '').replaceAll('PM', '').trim();
        final tp = timeOnly.split(':');
        hour = int.parse(tp[0]);
        minute = tp.length > 1 ? int.parse(tp[1]) : 0;
        if (isPm && hour != 12) hour += 12;
        if (!isPm && hour == 12) hour = 0;
      }
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }
}

/// A date option for the 14-day picker.
class DateOption {
  final DateTime date;
  final String dayOfWeek;

  const DateOption({required this.date, required this.dayOfWeek});

  String get isoDate =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String get displayDate =>
      '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';

  String get dayLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return '$dayOfWeek, ${date.day}';
  }
}
