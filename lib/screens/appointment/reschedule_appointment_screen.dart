import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../controllers/appointment_controller.dart';
import '../../controllers/doctor_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/doctor_model.dart';
import '../../models/doctor_slot_model.dart';
import '../../models/unavailable_range.dart';
import '../../services/supabase_service.dart';
import '../../utils/extensions.dart';
import '../../utils/snackbar_helpers.dart';
import '../../widgets/appointment_details_sheet.dart';
import '../../widgets/appointment_info_card.dart';
import '../../widgets/doctor_avatar.dart';

/// Reschedule an existing Pending/Upcoming appointment to a different
/// available slot.
///
/// Mirrors the Book Appointment screen's slot picker (14-day date strip +
/// time chips grouped by consultation type) so the patient picks a new
/// slot exactly the same way they picked the original one. The
/// appointment's OWN slot stays selectable (via
/// [AppointmentController.isSlotBookedExcluding]) so the patient can keep
/// the same time or move away from it. Confirming calls
/// [AppointmentController.rescheduleAppointment], which the DB trigger
/// `enforce_slot_booking_rule` guards server-side: if another patient just
/// took the new slot, the move is rejected and the screen shows the same
/// "slot was just booked" message as the booking flow.
///
/// Pass `{'appointment': …}` to reschedule as the PATIENT, or add
/// `'initiatedByDoctor': true` to reschedule as the CLINIC: the current-
/// appointment card then shows the PATIENT as the subject, and the
/// confirmation runs the doctor-scoped update and notifies the patient via
/// the `appointment_rescheduled_by_doctor` event.
class RescheduleAppointmentScreen extends StatefulWidget {
  const RescheduleAppointmentScreen({super.key});

  @override
  State<RescheduleAppointmentScreen> createState() =>
      _RescheduleAppointmentScreenState();
}

class _RescheduleAppointmentScreenState
    extends State<RescheduleAppointmentScreen> {
  final _controller = Get.find<AppointmentController>();

  /// The appointment being moved — arrives via Get.arguments.
  late AppointmentModel _appointment;

  /// True when the CLINIC (doctor) is initiating the move — the screen
  /// shows the patient as the subject and confirms via the doctor-scoped
  /// update ([AppointmentController.rescheduleAppointment] with
  /// `initiatedByDoctor: true`), which notifies the patient.
  late bool _initiatedByDoctor;

  /// Doctor reconstructed from the appointment's stored snapshot (the
  /// history screen resolves it the same way before opening this screen).
  DoctorModel? _doctor;

  /// Whether the doctor details could be resolved. When false the screen
  /// shows an error state instead of a broken picker.
  bool _doctorResolved = false;

  /// Index into [dateOptions] — the selected new date.
  int _selectedDateIndex = -1;

  /// The new time slot string the patient tapped (e.g. "09:00 AM").
  String _selectedTimeSlot = '';

  /// The consultation type ('tele' | 'video' | 'clinic') of the selected
  /// slot — tracked alongside [_selectedTimeSlot] because the same clock
  /// time can exist in several schedule types, so the type must come from
  /// the group the patient tapped, never from the time alone.
  String _selectedType = '';

  /// Whether slots are still loading.
  bool _slotsLoading = true;

  /// ISO date keys (yyyy-MM-dd) the doctor marked unavailable — the weekly
  /// schedule may still have slots, but these dates are blocked.
  final Set<String> _unavailableIsoDates = {};

  /// The next 14 days as displayable items.
  late final List<_DateOption> dateOptions;

  /// Quick-check whether a new slot has been picked (and it differs from
  /// the current one — keeping the same slot is a harmless no-op, but the
  /// confirm button stays meaningful only when something changed).
  bool get _canConfirm =>
      _selectedDateIndex >= 0 && _selectedTimeSlot.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    _appointment = args is Map
        ? (args['appointment'] as AppointmentModel)
        : (args as AppointmentModel);
    _initiatedByDoctor = args is Map && args['initiatedByDoctor'] == true;

    // Build the 14-day date list starting today (same window as booking).
    dateOptions = List.generate(14, (i) {
      final d = DateTime.now().add(Duration(days: i));
      const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const fullDayNames = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      const monthNames = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return _DateOption(
        date: d,
        dayLabel: dayLabels[d.weekday - 1],
        dateLabel: '${d.day}',
        monthLabel: monthNames[d.month],
        isoDate:
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        dayOfWeek: fullDayNames[d.weekday - 1],
      );
    });

    _resolveDoctor();
  }

  /// Reconstruct a [DoctorModel] from the appointment's stored doctor
  /// snapshot (same resolution the history screen uses for the profile
  /// deep link), falling back to a minimal placeId+name shape.
  void _resolveDoctor() {
    final details = _appointment.doctorDetails;
    DoctorModel? doctor;
    if (details != null) {
      try {
        doctor = DoctorModel.fromJson(details);
      } catch (_) {
        doctor = null;
      }
    }
    final placeId = doctor?.placeId.isNotEmpty == true
        ? doctor!.placeId
        : (details?['place_id']?.toString() ??
              details?['placeId']?.toString() ??
              '');
    final name = doctor?.name.isNotEmpty == true
        ? doctor!.name
        : (_appointment.doctorName ?? 'Doctor');
    _doctor = doctor ?? DoctorModel(placeId: placeId, name: name);

    if (placeId.isEmpty) {
      // No doctor identity — nothing to pick slots from.
      _doctorResolved = false;
      return;
    }
    _doctorResolved = true;
    _loadSlots(placeId);
  }

  Future<void> _loadSlots(String placeId) async {
    setState(() => _slotsLoading = true);
    // Unavailable dates come from the fresh DB fetch (the doctor may have
    // added/removed ranges since booking), falling back to the snapshot.
    try {
      final dbDoctor = await SupabaseService().getDoctorFromDb(placeId);
      final ranges =
          (dbDoctor?.unavailableRanges ?? _doctor?.unavailableRanges) ??
          const <UnavailableRange>[];
      _unavailableIsoDates.addAll(
        UnavailableRange.matchingIsoDates(
          dateOptions.map((o) => o.isoDate),
          ranges,
        ),
      );
      if (dbDoctor != null && mounted) {
        setState(() {
          _doctor = DoctorController.mergeDoctorSetFields(
            _doctor!,
            dbDoctor,
            null,
          );
        });
      }
    } catch (_) {
      // Non-fatal — fall back to the snapshot's ranges.
      _unavailableIsoDates.addAll(
        UnavailableRange.matchingIsoDates(
          dateOptions.map((o) => o.isoDate),
          _doctor?.unavailableRanges ?? const <UnavailableRange>[],
        ),
      );
    }
    await Future.wait([
      _controller.loadDoctorSlots(placeId),
      _controller.loadBookedSlots(placeId),
    ]);
    if (!mounted) return;
    setState(() => _slotsLoading = false);
  }

  /// True when [opt] falls inside one of the doctor's unavailable ranges.
  bool _isDateUnavailable(_DateOption opt) {
    return _unavailableIsoDates.contains(opt.isoDate);
  }

  Future<void> _confirmReschedule() async {
    FocusScope.of(context).unfocus();

    if (_selectedDateIndex < 0 || _selectedTimeSlot.isEmpty) {
      showErrorSnackbar('Please select a new date and time slot');
      return;
    }
    final selected = dateOptions[_selectedDateIndex];
    if (_isDateUnavailable(selected)) {
      showErrorSnackbar(
        'The doctor is unavailable on this date. Please pick another.',
      );
      return;
    }
    if (_controller.isSlotBookedExcluding(
      selected.isoDate,
      _selectedTimeSlot,
      excludeDate: _appointment.appointmentDate,
      excludeTime: _appointment.appointmentTime,
    )) {
      showErrorSnackbar('This slot was just booked. Please pick another.');
      return;
    }
    if (_controller.isSlotInPast(selected.isoDate, _selectedTimeSlot)) {
      showErrorSnackbar('This slot has already passed. Please pick another.');
      return;
    }

    final consultationType = _selectedType.isNotEmpty
        ? _selectedType
        : _controller.getSlotTypeLabel(_selectedTimeSlot);
    final success = await _controller.rescheduleAppointment(
      _appointment,
      date: selected.isoDate,
      time: _selectedTimeSlot,
      consultationType: consultationType,
      initiatedByDoctor: _initiatedByDoctor,
    );
    if (!mounted) return;
    if (success) {
      await _showSuccessDialog(selected);
      if (!mounted) return;
      Get.back();
    } else {
      showErrorSnackbar(
        'Could not reschedule — the new slot was just taken. Please pick another.',
      );
      // Refresh the booked-slot set so the conflict re-renders as disabled.
      final placeId = _doctor?.placeId ?? '';
      if (placeId.isNotEmpty) {
        await _controller.loadBookedSlots(placeId);
      }
    }
  }

  Future<void> _showSuccessDialog(_DateOption selected) {
    final displayDate =
        '${selected.date.day.toString().padLeft(2, '0')}-${selected.date.month.toString().padLeft(2, '0')}-${selected.date.year}';
    return Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: AppColors.bgCard,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.success.withAlpha(30),
                      AppColors.success.withAlpha(10),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.event_repeat_rounded,
                  size: 44,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Appointment Rescheduled!',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textHeading,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _initiatedByDoctor
                    ? (_appointment.patientName ?? 'Patient')
                    : (_appointment.doctorName ?? 'Doctor'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgSecondarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$displayDate  •  $_selectedTimeSlot',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textBody,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _initiatedByDoctor
                    ? 'The patient has been notified of the new time.'
                    : 'The clinic has been notified of the new time.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textCaption,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.done_rounded, size: 20),
                  label: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final surfaceColor = isDark
        ? const Color(0xFF1C1C30)
        : const Color(0xFFF7F8FA);

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(textColor),

              const SizedBox(height: 22),

              if (!_doctorResolved)
                _buildNoDoctorState()
              else ...[
                _buildCurrentCard(isDark, surfaceColor),

                const SizedBox(height: 24),

                // ── Select New Date ──
                _buildDateSection(textColor, isDark),

                const SizedBox(height: 24),

                // ── Available Slots ──
                if (_selectedDateIndex >= 0 && !_slotsLoading)
                  _buildSlotsSection(textColor, isDark, surfaceColor),

                if (_slotsLoading) _buildSlotsShimmer(isDark),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: _doctorResolved ? _buildBottomBar(isDark) : null,
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _buildHeader(Color textColor) {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            color: textColor.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            onPressed: Get.back,
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 17,
              color: textColor,
            ),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(width: 14),
        // Title + consultation-type chip — the same info-tinted pill the
        // details sheet shows, so the type is recognizable at every step
        // of the flow. Hidden for legacy rows without a stored type.
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reschedule',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: -0.3,
              ),
            ),
            if (_appointment.consultationTypeLabel != null) ...[
              const SizedBox(height: 4),
              Container(
                key: const ValueKey('reschedule_screen_consultation_chip'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.info.withAlpha(14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.info.withAlpha(40)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppointmentInfoBlock.consultationIconOf(_appointment),
                      size: 12,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _appointment.consultationTypeLabel!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.info,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── Current appointment card ─────────────────────────────────

  Widget _buildCurrentCard(bool isDark, Color surfaceColor) {
    final doctor = _doctor!;
    final currentDate =
        _appointment.displayDate ?? _appointment.appointmentDate;
    // The SUBJECT of the reschedule: the patient in doctor-initiated mode
    // (the clinic is moving the patient's booking), the doctor otherwise
    // (the patient is moving away from this clinic).
    final subjectName = _initiatedByDoctor
        ? (_appointment.patientName ?? 'Patient')
        : doctor.name;
    final subjectSubtitle = _initiatedByDoctor
        ? ((_appointment.patientPhone?.isNotEmpty == true)
              ? _appointment.patientPhone!
              : (_appointment.consultationTypeLabel ?? 'Patient'))
        : (_appointment.consultationTypeLabel ??
              (doctor.specialization ?? 'Doctor'));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primary.withAlpha(160)],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(left: 2.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C30) : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_initiatedByDoctor)
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withAlpha(80),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        AppointmentDetailsSheet.initials(subjectName),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withAlpha(80),
                        ],
                      ),
                    ),
                    child: DoctorAvatar.circle(doctor: doctor, size: 46),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subjectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textHeading,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subjectSubtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textCaption,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_initiatedByDoctor && doctor.rating != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4D85A).withAlpha(22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Color(0xFFF4D85A),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          doctor.rating!.ratingString,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF4D85A),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.info.withAlpha(10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.info.withAlpha(30)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current appointment: $currentDate at '
                      '${_appointment.appointmentTime}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textBody,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Date Section ─────────────────────────────────────────────

  Widget _buildDateSection(Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Select New Date',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 8),
            if (_slotsLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (!_slotsLoading)
          SizedBox(
            height: 88,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: dateOptions.length,
              itemBuilder: (context, index) {
                final opt = dateOptions[index];
                final hasSlots = _controller.hasSlotsForDay(opt.dayOfWeek);
                final isUnavailable = _isDateUnavailable(opt);
                final isSelected = _selectedDateIndex == index;
                return _DateChip(
                  dateOption: opt,
                  hasSlots: hasSlots && !isUnavailable,
                  isUnavailable: isUnavailable,
                  isSelected: isSelected,
                  isDark: isDark,
                  onTap: hasSlots && !isUnavailable
                      ? () {
                          setState(() {
                            _selectedDateIndex = index;
                            _selectedTimeSlot = '';
                            _selectedType = '';
                            _controller.selectedDayOfWeek.value = opt.dayOfWeek;
                          });
                        }
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }

  // ── Slots Section ─────────────────────────────────────────────

  Widget _buildSlotsSection(Color textColor, bool isDark, Color surfaceColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Slots',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Obx(() {
          final dayOfWeek = _controller.selectedDayOfWeek.value;
          final schedules = _daySchedules(dayOfWeek);
          final selectedIsoDate = _selectedDateIndex >= 0
              ? dateOptions[_selectedDateIndex].isoDate
              : '';

          if (_selectedDateIndex >= 0 &&
              _isDateUnavailable(dateOptions[_selectedDateIndex])) {
            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The doctor is unavailable on this date. Please pick another day.',
                      style: TextStyle(color: AppColors.error, fontSize: 14),
                    ),
                  ),
                ],
              ),
            );
          }

          if (schedules.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    color: AppColors.textCaption,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No slots available for this day. Try another date.',
                      style: TextStyle(
                        color: AppColors.textCaption,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // One group PER schedule row — each type's own slots render
          // under its own heading even when several types share the same
          // clock times (the old deduped-first-match grouping collapsed
          // overlapping types into a single group).
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: schedules.map((schedule) {
              final type = schedule.scheduleType;
              final typeEmoji = _typeEmoji(type);
              final typeLabel = _typeLabel(type);
              final typeColor = _typeColor(type);
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$typeEmoji $typeLabel',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: typeColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withAlpha(10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '₹${schedule.fee}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: typeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: schedule.slots.map((timeSlot) {
                        final isTimeSelected = _selectedTimeSlot == timeSlot &&
                            _selectedType == type;
                        // The appointment's own slot is NOT treated as
                        // booked (the patient can keep it or move away).
                        final isBooked = _controller.isSlotBookedExcluding(
                          selectedIsoDate,
                          timeSlot,
                          excludeDate: _appointment.appointmentDate,
                          excludeTime: _appointment.appointmentTime,
                        );
                        final isPast = _controller.isSlotInPast(
                          selectedIsoDate,
                          timeSlot,
                        );
                        final isDisabled = isBooked || isPast;
                        return GestureDetector(
                          onTap: isDisabled
                              ? null
                              : () => setState(() {
                                    _selectedTimeSlot = timeSlot;
                                    _selectedType = type;
                                  }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isTimeSelected
                                  ? typeColor
                                  : isDisabled
                                  ? surfaceColor
                                  : (isDark
                                        ? const Color(0xFF1C1C30)
                                        : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isTimeSelected
                                    ? typeColor
                                    : isDisabled
                                    ? AppColors.textDisabled.withAlpha(35)
                                    : (isDark
                                          ? Colors.white.withAlpha(8)
                                          : const Color(0xFFE5E7EB)),
                                width: isTimeSelected ? 0 : 1,
                              ),
                              boxShadow: isTimeSelected
                                  ? [
                                      BoxShadow(
                                        color: typeColor.withAlpha(40),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isTimeSelected
                                      ? Icons.check_circle_rounded
                                      : isBooked
                                      ? Icons.lock_rounded
                                      : isPast
                                      ? Icons.history_rounded
                                      : Icons.schedule_rounded,
                                  size: 14,
                                  color: isTimeSelected
                                      ? Colors.white
                                      : isDisabled
                                      ? AppColors.textDisabled
                                      : AppColors.textCaption,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isBooked ? 'Booked' : timeSlot,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isTimeSelected
                                        ? Colors.white
                                        : isDisabled
                                        ? AppColors.textDisabled
                                        : textColor,
                                    decoration: isPast
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  // ── Bottom Bar ────────────────────────────────────────────────

  Widget _buildBottomBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF14142A).withAlpha(248)
            : Colors.white.withAlpha(248),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withAlpha(8)
                : Colors.black.withAlpha(6),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 35 : 10),
            blurRadius: 28,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Selected summary
              if (_selectedDateIndex >= 0 && _selectedTimeSlot.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 13,
                        color: AppColors.textCaption,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${dateOptions[_selectedDateIndex].dayLabel}, ${dateOptions[_selectedDateIndex].dateLabel} ${dateOptions[_selectedDateIndex].monthLabel}  •  $_selectedTimeSlot',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textCaption,
                        ),
                      ),
                    ],
                  ),
                ),
              // Confirm button
              Obx(() {
                final isLoading = _controller.isLoading.value;
                final ready = _canConfirm && !isLoading;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: ready
                        ? LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withAlpha(210),
                            ],
                          )
                        : null,
                    color: ready
                        ? null
                        : (isDark
                              ? const Color(0xFF2A2A40)
                              : const Color(0xFFD1D5DB)),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: ready
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(45),
                              blurRadius: 18,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : [],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isLoading ? null : _confirmReschedule,
                      borderRadius: BorderRadius.circular(16),
                      child: Center(
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.event_repeat_rounded,
                                    size: 20,
                                    color: ready
                                        ? Colors.white
                                        : (isDark
                                              ? Colors.white38
                                              : Colors.white70),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Confirm Reschedule',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: ready
                                          ? Colors.white
                                          : (isDark
                                                ? Colors.white38
                                                : Colors.white70),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Error state (unresolvable doctor) ────────────────────────

  Widget _buildNoDoctorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withAlpha(15),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load the doctor',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textHeading,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Please try again from your appointment history.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textCaption,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shimmer skeleton ──────────────────────────────────────────

  Widget _buildSlotsShimmer(bool isDark) {
    final base = isDark ? const Color(0xFF1C1C30) : const Color(0xFFECEAE4);
    final highlight = isDark
        ? const Color(0xFF2C2C42)
        : const Color(0xFFF6F2EA);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 130,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 7,
              itemBuilder: (context, index) => Container(
                width: 64,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 28,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 110,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 100,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 50,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              4,
              (i) => Container(
                width: i == 2 ? 100 : 80,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _typeEmoji(String type) {
    switch (type) {
      case 'tele':
        return '📞';
      case 'video':
        return '🎥';
      case 'clinic':
        return '🏥';
      default:
        return '🩺';
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'tele':
        return 'Tele Consultation';
      case 'video':
        return 'Video Consultation';
      case 'clinic':
        return 'In-Clinic';
      default:
        return 'Consultation';
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'tele':
        return const Color(0xFF1E3A8A);
      case 'video':
        return const Color(0xFF6B21A8);
      case 'clinic':
        return const Color(0xFF92400E);
      default:
        return AppColors.primary;
    }
  }

  /// The doctor's enabled, non-empty schedule rows for [dayOfWeek] in the
  /// canonical display order (Tele → Video → In-Clinic). Each row keeps
  /// its OWN slot list — rows are never merged, so a clock time present in
  /// several consultation types appears in every group.
  List<DoctorSlot> _daySchedules(String dayOfWeek) {
    const order = ['tele', 'video', 'clinic'];
    return _controller.doctorSlots
        .where(
          (s) =>
              s.dayOfWeek == dayOfWeek &&
              s.isEnabled &&
              s.slots.isNotEmpty,
        )
        .toList()
      ..sort(
        (a, b) => order
            .indexOf(a.scheduleType)
            .compareTo(order.indexOf(b.scheduleType)),
      );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Data classes
// ════════════════════════════════════════════════════════════════════

class _DateOption {
  final DateTime date;
  final String dayLabel;
  final String dateLabel;
  final String monthLabel;
  final String isoDate;
  final String dayOfWeek;

  const _DateOption({
    required this.date,
    required this.dayLabel,
    required this.dateLabel,
    required this.monthLabel,
    required this.isoDate,
    required this.dayOfWeek,
  });
}

// ════════════════════════════════════════════════════════════════════
//  Date chip widget
// ════════════════════════════════════════════════════════════════════

class _DateChip extends StatelessWidget {
  final _DateOption dateOption;
  final bool hasSlots;
  final bool isUnavailable;
  final bool isSelected;
  final bool isDark;
  final VoidCallback? onTap;

  const _DateChip({
    required this.dateOption,
    required this.hasSlots,
    required this.isUnavailable,
    required this.isSelected,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = !hasSlots && !isSelected;
    final disabledColor = isDark
        ? const Color(0xFF1C1C30)
        : const Color(0xFFF3F4F6);
    final unavailColor = isDark
        ? const Color(0xFF3A1F1F)
        : const Color(0xFFFCEBEB);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : isUnavailable
              ? unavailColor
              : isDisabled
              ? disabledColor
              : (isDark ? const Color(0xFF1C1C30) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : isUnavailable
                ? AppColors.error.withAlpha(45)
                : hasSlots
                ? AppColors.primary.withAlpha(35)
                : (isDark
                      ? Colors.white.withAlpha(6)
                      : const Color(0xFFE5E7EB)),
            width: isSelected ? 0 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(45),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dateOption.dayLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white.withAlpha(200)
                      : isUnavailable
                      ? AppColors.error
                      : isDisabled
                      ? AppColors.textDisabled
                      : AppColors.textCaption,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateOption.dateLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Colors.white
                      : isUnavailable
                      ? AppColors.error
                      : isDisabled
                      ? AppColors.textDisabled
                      : (isDark ? Colors.white : AppColors.textHeading),
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                dateOption.monthLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.white.withAlpha(180)
                      : isUnavailable
                      ? AppColors.error
                      : isDisabled
                      ? AppColors.textDisabled
                      : AppColors.textCaption,
                ),
              ),
              if (isUnavailable)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    '✕',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.error,
                    ),
                  ),
                )
              else if (hasSlots && !isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(60),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
