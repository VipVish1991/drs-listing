import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/doctor_controller.dart';
import '../models/doctor_model.dart';
import '../models/doctor_slot_model.dart';
import '../routes/app_routes.dart';
import '../services/supabase_service.dart';
import '../utils/snackbar_helpers.dart';
import '../utils/time_slot_generator.dart';

// ── Schedule type descriptors ─────────────────────────────────────────

class ScheduleTypeDescriptor {
  final String type;
  final String emoji;
  final String label;
  final String sub;
  final int defaultFee;

  const ScheduleTypeDescriptor({
    required this.type,
    required this.emoji,
    required this.label,
    required this.sub,
    required this.defaultFee,
  });
}

const List<ScheduleTypeDescriptor> kScheduleTypes = [
  ScheduleTypeDescriptor(
    type: 'tele',
    emoji: '📞',
    label: 'Tele Consultation',
    sub: 'Phone Consultation',
    defaultFee: 500,
  ),
  ScheduleTypeDescriptor(
    type: 'video',
    emoji: '🎥',
    label: 'Video Consultation',
    sub: 'Online Video Call',
    defaultFee: 800,
  ),
  ScheduleTypeDescriptor(
    type: 'clinic',
    emoji: '🏥',
    label: 'In-Clinic Consultation',
    sub: 'Physical Appointments',
    defaultFee: 1000,
  ),
];

const List<String> kDaysOfWeek = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

// ── Per-day / per-schedule state (plain, non-Rx — controller bumps
//    `version` to signal the View to rebuild after any mutation) ──────

class ScheduleState {
  final String type;
  bool enabled;
  String startTime; // 24h "HH:MM"
  String endTime; // 24h "HH:MM"
  int durationMinutes;
  int fee;
  List<String> slots;

  ScheduleState({
    required this.type,
    this.enabled = true,
    this.startTime = '09:00',
    this.endTime = '12:00',
    this.durationMinutes = 30,
    this.fee = 500,
    List<String>? slots,
  }) : slots = slots ?? [];

  void regenerateSlots() {
    slots = generateTimeSlots(startTime, endTime, durationMinutes);
  }
}

class DayScheduleState {
  bool active;
  final List<ScheduleState> schedules;

  DayScheduleState({this.active = true, required this.schedules});
}

/// Owns all weekly-availability state for [DoctorAvailabilityScreen],
/// loads any existing schedule from Supabase, and persists the whole
/// week in a single save action.
///
/// Registered per-doctor with `Get.put(..., tag: doctor.placeId)` by the
/// screen's State, and removed with `Get.delete` on dispose — so
/// navigating to a different doctor's availability page never reuses
/// stale state.
class DoctorAvailabilityController extends GetxController {
  DoctorAvailabilityController({required this.doctor});

  final DoctorModel doctor;
  final SupabaseService _supabase = SupabaseService();

  final RxBool isLoading = true.obs;
  final RxBool isSaving = false.obs;
  final RxString loadError = ''.obs;

  /// Bumped on every state mutation below so `Obx` widgets that read it
  /// rebuild. The nested day/schedule state itself is plain Dart for
  /// simplicity — this is the single reactive "clock" for the screen.
  final RxInt version = 0.obs;
  void _touch() => version.value++;

  late final Map<String, DayScheduleState> dayData = {
    for (final day in kDaysOfWeek) day: _buildDefaultDay(day),
  };

  bool _disposed = false;

  @override
  void onInit() {
    super.onInit();
    _guardAccess();
    _loadExistingSlots();
  }

  @override
  void onClose() {
    _disposed = true;
    super.onClose();
  }

  // ── Access guard (moved from the old State.initState) ─────────────

  void _guardAccess() {
    final auth = Get.find<AuthController>();
    if (auth.currentUser.value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.toNamed(AppRoutes.login, arguments: {'pendingDoctor': doctor});
      });
      return;
    }
    if (!auth.isDoctor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAllNamed(AppRoutes.home);
        showErrorSnackbar('Only doctors can manage availability slots.');
      });
    }
  }

  // ── Defaults ────────────────────────────────────────────────────

  DayScheduleState _buildDefaultDay(String day) {
    final schedules = kScheduleTypes.map((t) {
      final s = ScheduleState(type: t.type, fee: t.defaultFee);
      if (day == 'Saturday') {
        switch (t.type) {
          case 'tele':
            s.startTime = '09:00';
            s.endTime = '12:00';
            break;
          case 'video':
            s.startTime = '10:00';
            s.endTime = '13:00';
            break;
          case 'clinic':
            s.startTime = '13:00';
            s.endTime = '17:00';
            break;
        }
      } else if (day == 'Sunday') {
        s.startTime = '10:00';
        s.endTime = '13:00';
        s.enabled = false;
      }
      s.regenerateSlots();
      return s;
    }).toList();

    return DayScheduleState(active: day != 'Sunday', schedules: schedules);
  }

  // ── Load ────────────────────────────────────────────────────────

  Future<void> _loadExistingSlots() async {
    isLoading.value = true;
    loadError.value = '';
    try {
      final existing = await _supabase.getDoctorSlots(doctor.placeId);
      for (final slot in existing) {
        final dayState = dayData[slot.dayOfWeek];
        if (dayState == null) continue;
        ScheduleState? sched;
        for (final s in dayState.schedules) {
          if (s.type == slot.scheduleType) {
            sched = s;
            break;
          }
        }
        if (sched == null) continue;

        sched.enabled = slot.isEnabled;
        sched.startTime = slot.startTime;
        sched.endTime = slot.endTime;
        sched.durationMinutes = slot.durationMinutes;
        sched.fee = slot.fee;
        sched.slots = List<String>.from(slot.slots);
        dayState.active = dayState.schedules.any((s) => s.enabled);
      }
    } catch (_) {
      // Defaults stay in place; surface a soft, dismissible banner
      // instead of failing silently.
      loadError.value = 'Could not load your saved availability — showing defaults.';
    } finally {
      isLoading.value = false;
      _touch();
    }
  }

  Future<void> retryLoad() => _loadExistingSlots();

  // ── Mutations ───────────────────────────────────────────────────

  void toggleDay(String day, bool active) {
    final d = dayData[day];
    if (d == null) return;
    d.active = active;
    if (!active) {
      for (final s in d.schedules) {
        s.enabled = false;
      }
    } else if (!d.schedules.any((s) => s.enabled)) {
      for (final s in d.schedules) {
        s.enabled = true;
        s.regenerateSlots();
      }
    }
    _touch();
    _toast(active ? '✅ $day activated' : '⛔ $day deactivated');
  }

  void toggleSchedule(String day, int idx, bool enabled) {
    final sched = dayData[day]?.schedules[idx];
    if (sched == null) return;
    sched.enabled = enabled;
    _touch();
    _toast(enabled
        ? '✅ ${kScheduleTypes[idx].label} enabled for $day'
        : '⛔ ${kScheduleTypes[idx].label} disabled for $day');
  }

  void updateStartTime(String day, int idx, String value24) {
    final sched = dayData[day]?.schedules[idx];
    if (sched == null) return;
    sched.startTime = value24;
    sched.regenerateSlots();
    _touch();
  }

  void updateEndTime(String day, int idx, String value24) {
    final sched = dayData[day]?.schedules[idx];
    if (sched == null) return;
    sched.endTime = value24;
    sched.regenerateSlots();
    _touch();
  }

  void updateDuration(String day, int idx, int minutes) {
    final sched = dayData[day]?.schedules[idx];
    if (sched == null) return;
    sched.durationMinutes = minutes;
    sched.regenerateSlots();
    _touch();
  }

  void updateFee(String day, int idx, int fee) {
    final sched = dayData[day]?.schedules[idx];
    if (sched == null) return;
    sched.fee = fee;
    // No _touch() here — the fee field owns its own TextEditingController
    // (see _FeeInput in the screen) so it doesn't need a full rebuild
    // on every keystroke. Summary tiles read the value on next rebuild.
  }

  void removeSlot(String day, int idx, String slotTime) {
    final sched = dayData[day]?.schedules[idx];
    if (sched == null) return;
    sched.slots.remove(slotTime);
    _touch();
    _toast('🗑️ Removed "$slotTime" from $day');
  }

  // ── Derived values ──────────────────────────────────────────────

  int get workingDaysCount => dayData.values.where((d) => d.active).length;

  int get totalSlots {
    var count = 0;
    for (final day in dayData.values) {
      if (!day.active) continue;
      for (final s in day.schedules) {
        if (s.enabled) count += s.slots.length;
      }
    }
    return count;
  }

  int get videoFee => _firstActiveFee('video', 800);
  int get clinicFee => _firstActiveFee('clinic', 1000);

  int _firstActiveFee(String type, int fallback) {
    for (final day in dayData.values) {
      if (!day.active) continue;
      for (final s in day.schedules) {
        if (s.type == type && s.enabled) return s.fee;
      }
    }
    return fallback;
  }

  String workingHoursText(String day) {
    final scheds = dayData[day]?.schedules ?? [];
    String? earliest24, latest24;
    for (final s in scheds) {
      if (!s.enabled) continue;
      if (earliest24 == null || s.startTime.compareTo(earliest24) < 0) {
        earliest24 = s.startTime;
      }
      if (latest24 == null || s.endTime.compareTo(latest24) > 0) {
        latest24 = s.endTime;
      }
    }
    if (earliest24 == null || latest24 == null) return 'No active schedules';
    return '${to12h(earliest24)} – ${to12h(latest24)}';
  }

  // ── Save ────────────────────────────────────────────────────────

  /// Validates the current week, then persists it. Returns true on
  /// success so the View can decide what to do next (e.g. navigate).
  Future<bool> saveAll() async {
    final error = _validate();
    if (error != null) {
      _toast('⚠️ $error');
      return false;
    }

    // Guard: doctor must have a valid placeId before we try to persist.
    if (doctor.placeId.isEmpty) {
      showErrorSnackbar('Doctor place ID is missing. Cannot save schedule.');
      return false;
    }

    isSaving.value = true;
    _touch();
    try {
      // Grab the current user ID before the DB calls so we can associate
      // both the doctor profile row AND every slot row with the user.
      final userId = Get.find<AuthController>().currentUser.value?.id;

      // Build the updated doctor once and reuse everywhere — DB save,
      // dashboard sync, etc.
      final updatedDoctor = doctor.copyWith(userId: userId);

      // ── Step 1: Save doctor profile ──────────────────────────────
      debugPrint('ℹ️ [saveAll] Saving doctor profile...');
      await _supabase.saveDoctorToDb(updatedDoctor);
      debugPrint('✅ [saveAll] Doctor profile saved');

      // ── Step 2: Delete old slots ─────────────────────────────────
      debugPrint('ℹ️ [saveAll] Deleting old slots...');
      await _supabase.deleteAllDoctorSlots(doctor.placeId);
      debugPrint('✅ [saveAll] Old slots deleted');

      // ── Step 3: Build new slots ──────────────────────────────────
      final slotsToSave = <DoctorSlot>[];
      for (final day in kDaysOfWeek) {
        final dayState = dayData[day];
        if (dayState == null || !dayState.active) continue;
        for (final s in dayState.schedules) {
          if (!s.enabled) continue;
          slotsToSave.add(DoctorSlot(
            doctorPlaceId: doctor.placeId,
            userId: userId,
            dayOfWeek: day,
            scheduleType: s.type,
            startTime: s.startTime,
            endTime: s.endTime,
            durationMinutes: s.durationMinutes,
            fee: s.fee,
            slots: s.slots,
            isEnabled: true,
          ));
        }
      }

      // ── Step 4: Save slots one at a time with individual error
      //     handling so a single bad slot doesn't lose the whole batch ─
      if (slotsToSave.isNotEmpty) {
        debugPrint('ℹ️ [saveAll] Saving ${slotsToSave.length} slot rows...');
        int savedCount = 0;
        int failCount = 0;
        for (final slot in slotsToSave) {
          try {
            await _supabase.saveDoctorSlot(slot);
            savedCount++;
          } catch (e) {
            failCount++;
            debugPrint(
                '⚠️ [saveAll] Failed to save slot (${slot.dayOfWeek}, '
                '${slot.scheduleType}): $e');
          }
        }
        debugPrint(
            '✅ [saveAll] Slots saved: $savedCount, failed: $failCount');

        if (failCount > 0 && savedCount == 0) {
          showErrorSnackbar(
              'Failed to save schedule. Please try again.');
          return false;
        }

        if (failCount > 0) {
          // Partial failure — warn the user
          showErrorSnackbar(
            '$failCount slot(s) failed to save. Please review and re-save.');
        } else {
          _showSuccessSnackbar('Schedule saved for ${doctor.name}');
        }
      } else {
        debugPrint('ℹ️ [saveAll] No slots to save (all days inactive)');
      }

      // Update the in-memory doctor so the dashboard has the latest
      // data if the user navigates there later.
      final dashboardController = Get.find<DoctorController>();
      dashboardController.setDoctor(updatedDoctor);
      return true;
    } catch (e, stack) {
      debugPrint('❌ saveAll failed: $e\n$stack');
      showErrorSnackbar('Failed to save schedule. Please try again.');
      return false;
    } finally {
      if (!_disposed) {
        isSaving.value = false;
        _touch();
      }
    }
  }

  String? _validate() {
    final anyActive =
        dayData.values.any((d) => d.active && d.schedules.any((s) => s.enabled));
    if (!anyActive) {
      return 'Enable at least one day before saving.';
    }
    for (final entry in dayData.entries) {
      if (!entry.value.active) continue;
      for (final s in entry.value.schedules) {
        if (!s.enabled) continue;
        if (s.startTime.compareTo(s.endTime) >= 0) {
          return '${entry.key}: end time must be after start time.';
        }
        if (s.fee < 0) {
          return '${entry.key}: fee cannot be negative.';
        }
      }
    }
    return null;
  }

  void navigateToDashboard() {
    final dashboardController = Get.find<DoctorController>();
    dashboardController.setDoctor(doctor);
    Get.offAllNamed(AppRoutes.doctorDashboard, arguments: {'doctor': doctor});
  }

  // ── Toast (context-free, safe to call from the controller) ────────

  void _toast(String msg) {
    if (Get.context == null) return;
    Get.rawSnackbar(
      messageText: Text(
        msg,
        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
      ),
      backgroundColor: const Color(0xFF1F2937),
      borderRadius: 16,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  /// Animated success snackbar that fades & slides in from the top.
  void _showSuccessSnackbar(String msg) {
    Get.rawSnackbar(
      messageText: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white24,
            ),
            child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0B8A6F),
      borderRadius: 16,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 3),
      forwardAnimationCurve: Curves.easeOutCubic,
      reverseAnimationCurve: Curves.easeInCubic,
      animationDuration: const Duration(milliseconds: 500),
      isDismissible: true,
      dismissDirection: DismissDirection.horizontal,
    );
  }
}