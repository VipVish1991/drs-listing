import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../controllers/doctor_availability_controller.dart';
import '../../models/doctor_model.dart';
import '../../utils/time_slot_generator.dart';

/// Full weekly availability manager for a doctor/clinic.
///
/// Header + quick day-jump strip up top, icon summary cards, then a
/// collapsible card per day (tap to expand/collapse) holding the
/// Tele/Video/Clinic consultation blocks — time range, duration, fee,
/// and auto-generated slots. All data state lives in
/// [DoctorAvailabilityController]; this widget only renders it plus a
/// little view-only UI state (which day cards are expanded).
class DoctorAvailabilityScreen extends StatefulWidget {
  final DoctorModel doctor;

  const DoctorAvailabilityScreen({super.key, required this.doctor});

  @override
  State<DoctorAvailabilityScreen> createState() =>
      _DoctorAvailabilityScreenState();
}

class _DoctorAvailabilityScreenState extends State<DoctorAvailabilityScreen> {
  late final DoctorAvailabilityController controller;

  // View-only UI state — which day cards are expanded, and anchors so
  // the day-nav strip can scroll a tapped day into view.
  final Set<String> _expandedDays = {...kDaysOfWeek};
  final Map<String, GlobalKey> _dayKeys = {
    for (final d in kDaysOfWeek) d: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    // Tagged per-doctor so switching doctors never reuses stale state,
    // and torn down in dispose() below rather than left registered.
    controller = Get.put(
      DoctorAvailabilityController(doctor: widget.doctor),
      tag: widget.doctor.placeId,
    );
  }

  @override
  void dispose() {
    Get.delete<DoctorAvailabilityController>(tag: widget.doctor.placeId);
    super.dispose();
  }

  void _toggleExpanded(String day) {
    setState(() {
      if (_expandedDays.contains(day)) {
        _expandedDays.remove(day);
      } else {
        _expandedDays.add(day);
      }
    });
  }

  void _scrollToDay(String day) {
    setState(() => _expandedDays.add(day));
    final ctx = _dayKeys[day]?.currentContext;
    if (ctx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.05,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Obx(() {
          // Establishes the Obx dependency that every mutation bumps.
          controller.version.value;

          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              _buildHeader(),
              _buildDayNavStrip(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: controller.retryLoad,
                  child: CustomScrollView(
                    slivers: [
                      if (controller.loadError.value.isNotEmpty)
                        SliverToBoxAdapter(child: _buildErrorBanner()),
                      SliverToBoxAdapter(child: _buildSummary()),
                      ...kDaysOfWeek.map(
                        (day) => SliverToBoxAdapter(child: _buildDayCard(day)),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: MediaQuery.of(context).padding.bottom + 100,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────

  Widget _buildHeader() {
    final doctorName = widget.doctor.name;
    final initial = doctorName.isNotEmpty ? doctorName[0].toUpperCase() : 'D';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
            const Color(0xFF095E4C),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(70),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(35),
                  border: Border.all(
                    color: Colors.white.withAlpha(70),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Manage Slots",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      doctorName.isNotEmpty
                          ? doctorName
                          : "Weekly consultation schedule",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withAlpha(190),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Save Button
              Obx(() {
                final isSaving = controller.isSaving.value;

                return Material(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: isSaving
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            controller.saveAll();
                          },
                    child: Container(
                      width: 110, // Fixed width prevents shrinking
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withAlpha(70),
                          width: 1,
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: isSaving
                            ? const SizedBox(
                                key: ValueKey('loading'),
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                key: ValueKey('save'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.save_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Save',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
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
        ],
      ),
    );
  }

  // ── Day quick-jump strip ───────────────────────────────────────

  Widget _buildDayNavStrip() {
    return Container(
      color: Colors.white,
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: kDaysOfWeek.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = kDaysOfWeek[i];
          final isActive = controller.dayData[day]!.active;
          return GestureDetector(
            onTap: () => _scrollToDay(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 50,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withAlpha(20)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? AppColors.primary.withAlpha(90)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    day.substring(0, 3).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.textCaption,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? AppColors.success
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Error banner (soft-fail load, with retry) ──────────────────

  Widget _buildErrorBanner() {
    // Keyed by the error text so the entrance animation REPLAYS when a
    // retry lands a different message (or the same one re-appears after
    // clearing) — the notice always animates in, matching the app-wide
    // animated-notice language.
    return Container(
      key: ValueKey(controller.loadError.value),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF92400E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              controller.loadError.value,
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
          TextButton(
            onPressed: controller.retryLoad,
            child: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    )
        // The soft-fail load notice drops in the same fade + slide family
        // as the patient-side gate banner — read as a notice arriving,
        // never a jarring pop.
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: -0.2, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }

  // ── Summary ─────────────────────────────────────────────────────

  Widget _buildSummary() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _summaryTile(
            'Working Days',
            '${controller.workingDaysCount}',
            const Color(0xFFFCE4EC),
            Icons.event_available_rounded,
            const Color(0xFFC2185B),
          ),
          _summaryTile(
            'Total Slots',
            '${controller.totalSlots}',
            const Color(0xFFE3F2FD),
            Icons.grid_view_rounded,
            const Color(0xFF1565C0),
          ),
          _summaryTile(
            'Video Fee',
            '₹${controller.videoFee}',
            const Color(0xFFF3E5F5),
            Icons.videocam_rounded,
            const Color(0xFF6B21A8),
          ),
          _summaryTile(
            'Clinic Fee',
            '₹${controller.clinicFee}',
            const Color(0xFFFFF8E1),
            Icons.local_hospital_rounded,
            const Color(0xFF92400E),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(
    String label,
    String value,
    Color bgColor,
    IconData icon,
    Color iconColor,
  ) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textHeading,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: AppColors.textCaption),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Day Card (collapsible) ─────────────────────────────────────

  Widget _buildDayCard(String day) {
    final dayState = controller.dayData[day]!;
    final isActive = dayState.active;
    final isExpanded = _expandedDays.contains(day);
    final enabledCount = dayState.schedules.where((s) => s.enabled).length;
    final slotCount = dayState.schedules
        .where((s) => s.enabled)
        .fold<int>(0, (sum, s) => sum + s.slots.length);

    return Container(
      key: _dayKeys[day],
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _toggleExpanded(day),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              day,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isActive
                                    ? AppColors.textHeading
                                    : AppColors.textDisabled,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.success.withAlpha(25)
                                    : const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isActive
                                      ? AppColors.success
                                      : AppColors.textCaption,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isActive
                              ? '${controller.workingHoursText(day)} · $enabledCount type${enabledCount == 1 ? '' : 's'} · $slotCount slots'
                              : 'Not taking appointments',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ToggleSwitch(
                    value: isActive,
                    onChanged: (v) {
                      controller.toggleDay(day, v);
                      if (v) setState(() => _expandedDays.add(day));
                    },
                  ),
                  const SizedBox(width: 10),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textCaption,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: List.generate(
                  kScheduleTypes.length,
                  (idx) => _buildScheduleBlock(day, idx, isActive),
                ),
              ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  // ── Schedule Block ──────────────────────────────────────────────

  Widget _buildScheduleBlock(String day, int idx, bool dayActive) {
    final desc = kScheduleTypes[idx];
    final sched = controller.dayData[day]!.schedules[idx];
    final bgColor = _scheduleBgColor(desc.type);
    final fgColor = _scheduleFgColor(desc.type);
    final isEnabled = sched.enabled && dayActive;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isEnabled ? 1.0 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon + label + on/off ──
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(160),
                    shape: BoxShape.circle,
                  ),
                  child: Text(desc.emoji, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        desc.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: fgColor,
                        ),
                      ),
                      Text(
                        desc.sub,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: fgColor.withAlpha(180),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  isEnabled ? 'On' : 'Off',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                  ),
                ),
                const SizedBox(width: 6),
                _ToggleSwitch(
                  value: sched.enabled,
                  onChanged: dayActive
                      ? (v) => controller.toggleSchedule(day, idx, v)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Time range pill ──
            Text(
              'Consultation Window',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fgColor.withAlpha(200),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(12),
                      ),
                      onTap: isEnabled
                          ? () => _pickTime(
                              sched.startTime,
                              (v) => controller.updateStartTime(day, idx, v),
                            )
                          : null,
                      child: Center(
                        child: Text(
                          to12h(sched.startTime),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: AppColors.textCaption,
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(12),
                      ),
                      onTap: isEnabled
                          ? () => _pickTime(
                              sched.endTime,
                              (v) => controller.updateEndTime(day, idx, v),
                            )
                          : null,
                      child: Center(
                        child: Text(
                          to12h(sched.endTime),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Duration chips ──
            Text(
              'Slot Duration',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fgColor.withAlpha(200),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [10, 15, 30].map((d) {
                final selected = sched.durationMinutes == d;
                return GestureDetector(
                  onTap: isEnabled
                      ? () => controller.updateDuration(day, idx, d)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? fgColor : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? fgColor : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Text(
                      '${d}m',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.textBody,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // ── Fee ──
            Text(
              'Consultation Fee',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fgColor.withAlpha(200),
              ),
            ),
            const SizedBox(height: 6),
            _FeeInput(
              key: ValueKey('fee_${day}_$idx'),
              value: sched.fee,
              enabled: isEnabled,
              onChanged: (v) => controller.updateFee(day, idx, v),
            ),
            const SizedBox(height: 12),

            // ── Generated slots ──
            Text(
              'Generated Slots (${sched.slots.length})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fgColor.withAlpha(200),
              ),
            ),
            const SizedBox(height: 6),
            sched.slots.isEmpty
                ? Text(
                    'No slots for this range/duration',
                    style: TextStyle(
                      fontSize: 11,
                      color: fgColor.withAlpha(160),
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: sched.slots
                        .map(
                          (slotTime) =>
                              _buildSlotPill(slotTime, day, idx, isEnabled),
                        )
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime(
    String current24,
    ValueChanged<String> onChanged,
  ) async {
    final parts = current24.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      onChanged('$hh:$mm');
    }
  }

  Widget _buildSlotPill(String slotTime, String day, int idx, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            slotTime,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textHeading,
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => controller.removeSlot(day, idx, slotTime),
              child: const Icon(Icons.close, size: 14, color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Colors per schedule type ─────────────────────────────────────────

Color _scheduleBgColor(String type) {
  switch (type) {
    case 'tele':
      return const Color(0xFFEAF2FF);
    case 'video':
      return const Color(0xFFF4E8FF);
    case 'clinic':
      return const Color(0xFFFFF4D6);
    default:
      return const Color(0xFFF0F2F5);
  }
}

Color _scheduleFgColor(String type) {
  switch (type) {
    case 'tele':
      return const Color(0xFF1E3A8A);
    case 'video':
      return const Color(0xFF6B21A8);
    case 'clinic':
      return const Color(0xFF92400E);
    default:
      return AppColors.textBody;
  }
}

// ── Fee input — owns its own TextEditingController so typing doesn't
//    get its cursor reset by parent rebuilds (a real bug in the old
//    TextField.fromValue(...)-on-every-build approach). ───────────────

class _FeeInput extends StatefulWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _FeeInput({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_FeeInput> createState() => _FeeInputState();
}

class _FeeInputState extends State<_FeeInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value.toString(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IgnorePointer(
        ignoring: !widget.enabled,
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: widget.enabled
                ? AppColors.textHeading
                : AppColors.textDisabled,
          ),
          decoration: InputDecoration(
            prefixIcon: Container(
              width: 40,
              alignment: Alignment.center,
              child: Text(
                '₹',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: widget.enabled
                      ? AppColors.primary
                      : AppColors.textDisabled,
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 0,
            ),
            hintText: 'Enter fee',
            hintStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textDisabled,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 0,
            ),
            isDense: true,
          ),
          onChanged: (v) {
            final clean = v.replaceAll(RegExp(r'[^0-9]'), '');
            final parsed = int.tryParse(clean);
            if (parsed != null) widget.onChanged(parsed);
          },
        ),
      ),
    );
  }
}

// ── Toggle Switch ───────────────────────────────────────────────────

class _ToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleSwitch({required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: value ? AppColors.primary : const Color(0xFFCCCCCC),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
