import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../controllers/doctor_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/payment_model.dart';
import '../../models/unavailable_range.dart';
import '../../routes/app_routes.dart';
import '../../utils/appointment_dialogs.dart';
import '../../utils/number_formatter.dart';
import '../../utils/time_slot_generator.dart';
import '../../widgets/appointment_info_row.dart';
import '../../widgets/connectivity_status_card.dart';
import '../../widgets/notification_bell.dart';

class DoctorDashboardScreen extends StatelessWidget {
  const DoctorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<DoctorController>();
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoadingProfile.value) {
            return const _DashboardShimmerSkeleton();
          }
          return CustomScrollView(
            slivers: [
              // ── Modern Header ──
              SliverToBoxAdapter(child: _buildHeader(controller)),
              // ── Connectivity status card — appears while offline and
              //    shows the connected Wi-Fi network + signal strength.
              //    Hidden (zero-height) when online.
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: ConnectivityStatusCard(),
                ),
              ),
              // ── Scrollable Content ──
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 10),
                    _buildStatsGrid(controller),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Quick Actions'),
                    const SizedBox(height: 14),
                    _buildQuickActions(controller),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Availability'),
                    const SizedBox(height: 14),
                    _buildAvailabilityCard(controller),
                    const SizedBox(height: 28),
                    _buildSectionTitle("Today's Overview"),
                    const SizedBox(height: 14),
                    _buildTodayCard(controller),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Patient Analytics'),
                    const SizedBox(height: 14),
                    _buildAnalyticsRow(controller),
                    const SizedBox(height: 28),
                    _buildSectionTitle('Recent Activity'),
                    const SizedBox(height: 14),
                    _buildRecentActivity(controller),
                    const SizedBox(height: 20),
                  ]),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  HEADER — Modern glassmorphic with floating notification
  // ══════════════════════════════════════════════════════════════
  Widget _buildHeader(DoctorController controller) {
    return Obx(() {
      final doctor = controller.currentDoctor.value;

      // Fallback when doctor data is null
      if (doctor == null) {
        return _HeaderShell(
          child: const Row(
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person, color: Colors.white, size: 28),
                ),
              ),
              SizedBox(width: 16),
              Text(
                'Doctor Profile',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      }

      return _HeaderShell(
        child: Column(
          children: [
            // ─────────────────────────────────────────────
            // TOP ROW
            // ─────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withAlpha(60),
                        Colors.white.withAlpha(20),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: Colors.white.withAlpha(50),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      doctor.name.isNotEmpty
                          ? doctor.name[0].toUpperCase()
                          : 'D',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // ─────────────────────────────────────────
                // DOCTOR INFO
                // ─────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good ${_greetingSuffix()},',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withAlpha(170),
                          letterSpacing: 0.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 2),

                      // Doctor name (read-only on the dashboard — the name
                      // is edited on the doctor profile screen instead).
                      Text(
                        doctor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),

                      const SizedBox(height: 5),

                      // ⭐ IMPORTANT:
                      // Use Wrap instead of Row here
                      if ((doctor.specialization ?? '').isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: [
                            // Specialization
                            Container(
                              constraints: const BoxConstraints(maxWidth: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white.withAlpha(25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.medical_services_rounded,
                                    size: 12,
                                    color: Colors.white.withAlpha(200),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      doctor.specialization!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white.withAlpha(210),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Rating
                            if (doctor.rating != null)
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 120,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFB800).withAlpha(30),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFFFB800,
                                    ).withAlpha(40),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 12,
                                      color: Color(0xFFFFB800),
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        '${doctor.rating!.toStringAsFixed(1)}'
                                        '${doctor.userRatingsTotal != null ? ' (${doctor.userRatingsTotal})' : ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFFFB800),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // ─────────────────────────────────────────
                // NOTIFICATION
                // ─────────────────────────────────────────
                const NotificationBell(
                  backgroundColor: Color(0x14FFFFFF),
                  borderColor: Color(0x28FFFFFF),
                  iconColor: Colors.white,
                  badgeBorderColor: Colors.white,
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ─────────────────────────────────────────────
            // QUICK STATS
            // ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withAlpha(15)),
              ),
              child: Row(
                children: [
                  // Today
                  Expanded(
                    child: _QuickStatChip(
                      icon: Icons.calendar_today_rounded,
                      label: 'Today',
                      value: compactCount(controller.todayAppointments.value),
                    ),
                  ),

                  const SizedBox(
                    height: 30,
                    child: VerticalDivider(
                      color: Colors.white24,
                      thickness: 1,
                      width: 10,
                    ),
                  ),

                  // Patients
                  Expanded(
                    child: _QuickStatChip(
                      icon: Icons.people_alt_rounded,
                      label: 'Patients',
                      value: compactCount(controller.totalPatients.value),
                    ),
                  ),

                  const SizedBox(
                    height: 30,
                    child: VerticalDivider(
                      color: Colors.white24,
                      thickness: 1,
                      width: 10,
                    ),
                  ),

                  // Done
                  Expanded(
                    child: _QuickStatChip(
                      icon: Icons.task_alt_rounded,
                      label: 'Done',
                      value: compactCount(
                        controller.completedAppointments.value,
                      ),
                      accent: const Color(0xFF6EE7B7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Formats a [DateTime] as the 'yyyy-MM-dd' appointment date key.
  static String _dateKey(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _greetingSuffix() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    return 'Evening';
  }

  // ══════════════════════════════════════════════════════════════
  //  STATS GRID
  // ══════════════════════════════════════════════════════════════
  Widget _buildStatsGrid(DoctorController controller) {
    return Obx(() {
      if (controller.isLoadingStats.value) return _buildShimmerGrid();

      final cards = [
        _StatCardData(
          icon: Icons.calendar_today_rounded,
          label: 'Today',
          value: compactCount(controller.todayAppointments.value),
          gradient: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
          softColor: const Color(0xFFCCFBF1),
        ),
        _StatCardData(
          icon: Icons.event_available_rounded,
          label: 'Total',
          value: compactCount(controller.totalAppointments.value),
          gradient: const [Color(0xFF2563EB), Color(0xFF3B82F6)],
          softColor: const Color(0xFFDBEAFE),
        ),
        _StatCardData(
          icon: Icons.check_circle_rounded,
          label: 'Completed',
          value: compactCount(controller.completedAppointments.value),
          gradient: const [Color(0xFF16A34A), Color(0xFF22C55E)],
          softColor: const Color(0xFFDCFCE7),
        ),
        _StatCardData(
          icon: Icons.cancel_rounded,
          label: 'Cancelled',
          value: compactCount(controller.cancelledAppointments.value),
          gradient: const [Color(0xFFDC2626), Color(0xFFEF4444)],
          softColor: const Color(0xFFFEE2E2),
        ),
        _StatCardData(
          icon: Icons.payments_rounded,
          label: 'Payments',
          value: compactCount(controller.paymentCount.value),
          gradient: const [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
          softColor: const Color(0xFFEDE9FE),
          // Tap to open the full clinic payment history (doctor side).
          onTap: () => Get.toNamed(AppRoutes.doctorPaymentHistory),
          fullWidth: true,
        ),
        _StatCardData(
          icon: Icons.currency_rupee_rounded,
          label: 'Income',
          // Only settled (Paid) payments count as income — Pending /
          // Refunded / Failed money is not collected yet / returned. The
          // breakdown under the label shows Paid vs the still-owed Pending
          // amount so the clinic knows what's left to collect.
          value: '₹${PaymentModel.formatAmount(controller.paidIncome.value)}',
          gradient: const [Color(0xFFD97706), Color(0xFFF59E0B)],
          softColor: const Color(0xFFFEF3C7),
          // Payments and Income are the money cards — each spans the full
          // grid width so the amounts and breakdowns get room, shown one
          // after the other instead of squeezed side-by-side.
          fullWidth: true,
          breakdown: [
            _BreakdownLine(
              label: 'Paid',
              amount:
                  '₹${PaymentModel.formatAmount(controller.paidIncome.value)}',
              color: AppColors.success,
            ),
            _BreakdownLine(
              label: 'Pending',
              amount:
                  '₹${PaymentModel.formatAmount(controller.pendingIncome.value)}',
              color: AppColors.warning,
            ),
          ],
        ),
      ];

      // Content-driven 2-column grid (Wrap, not GridView): each card sizes
      // to its own content on EVERY screen width, so cards never scale on
      // wide screens (the old fixed mainAxisExtent capped the height and
      // made the FittedBox shrink at raised font scales) and never
      // overflow on narrow ones — the row simply grows taller instead.
      return LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - 14) / 2;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: cards
                .asMap()
                .entries
                .map(
                  (e) => SizedBox(
                    // The money cards (Payments / Income) span the full
                    // grid width; the four count cards share 2-column rows.
                    // NOTE: full-width cards MUST stay at the END of the
                    // list — a full-width card inside a shared Wrap run
                    // (with the 14px spacing) would overflow its row.
                    width: e.value.fullWidth
                        ? constraints.maxWidth
                        : cardWidth,
                    child: _ModernStatCard(data: e.value)
                        .animate()
                        .fadeIn(duration: 400.ms, delay: (80 * e.key).ms)
                        .slideY(
                          begin: 0.12,
                          end: 0,
                          duration: 400.ms,
                          delay: (80 * e.key).ms,
                        ),
                  ),
                )
                .toList(),
          );
        },
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  QUICK ACTIONS
  // ══════════════════════════════════════════════════════════════
  Widget _buildQuickActions(DoctorController controller) {
    return Obx(() {
      final doctor = controller.currentDoctor.value;
      return _GlassCard(
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(50),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GestureDetector(
                onTap: doctor != null
                    ? () => Get.toNamed(
                        AppRoutes.doctorAvailability,
                        arguments: {'doctor': doctor},
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manage Weekly Schedule',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textHeading,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Set availability, consultation types & fees',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textCaption,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Material(
              color: AppColors.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: doctor != null
                    ? () => Get.toNamed(
                        AppRoutes.doctorAvailability,
                        arguments: {'doctor': doctor},
                      )
                    : null,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms, delay: 150.ms);
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  AVAILABILITY — weekly schedule (available slots) + unavailable
  //  date ranges (the doctor-set leave/holiday periods)
  // ══════════════════════════════════════════════════════════════
  Widget _buildAvailabilityCard(DoctorController controller) {
    return Obx(() {
      final doctor = controller.currentDoctor.value;
      final ranges = doctor?.unavailableRanges ?? const <UnavailableRange>[];
      final slots = controller.doctorSlots;

      const dayOrder = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];

      // ── Available time slots: enabled weekly schedule per day ──
      final dayChips = <Widget>[];
      for (final day in dayOrder) {
        final daySlots = slots
            .where(
              (s) => s.dayOfWeek == day && s.isEnabled && s.slots.isNotEmpty,
            )
            .toList();
        if (daySlots.isEmpty) continue;
        String? earliest24, latest24;
        for (final s in daySlots) {
          if (earliest24 == null || s.startTime.compareTo(earliest24) < 0) {
            earliest24 = s.startTime;
          }
          if (latest24 == null || s.endTime.compareTo(latest24) > 0) {
            latest24 = s.endTime;
          }
        }
        if (earliest24 == null || latest24 == null) continue;
        dayChips.add(
          _AvailabilityChip(
            color: AppColors.success,
            icon: Icons.schedule_rounded,
            label:
                '${day.substring(0, 3)}  ${to12h(earliest24)} – ${to12h(latest24)}',
          ),
        );
      }

      return _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  size: 16,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Available time slots',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHeading,
                    ),
                  ),
                ),
                if (controller.isLoadingSlots.value) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (dayChips.isEmpty)
              Text(
                'No active schedule yet — tap Manage Weekly Schedule to set one.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textCaption,
                ),
              )
            else
              Wrap(spacing: 8, runSpacing: 8, children: dayChips),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.event_busy_rounded,
                  size: 16,
                  color: AppColors.error,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Unavailable dates',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHeading,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (ranges.isEmpty)
              const Text(
                'No unavailable dates — patients can book any scheduled day.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textCaption),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ranges
                    .map(
                      (r) => _AvailabilityChip(
                        color: AppColors.error,
                        icon: Icons.event_busy_rounded,
                        label: r.label,
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms, delay: 160.ms);
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  TODAY'S OVERVIEW
  // ══════════════════════════════════════════════════════════════
  Widget _buildTodayCard(DoctorController controller) {
    return Obx(() {
      final now = DateTime.now();
      final todayKey = _dateKey(now);
      final todayAppts = controller.getAppointmentsForDate(todayKey);
      // Slot-occupancy rule (shared with the booking screen, see
      // AppointmentStatus.occupiesSlot): a slot stays booked until the
      // appointment is Cancelled — so the "Booked" pill counts every of
      // today's appointments that isn't Cancelled (Pending / Upcoming /
      // Completed / …), keeping it consistent with the header "Today" stat.
      final booked = todayAppts
          .where((a) => AppointmentStatus.occupiesSlot(a.status))
          .length;
      final completed = todayAppts.where((a) => a.status == 'Completed').length;
      final pct = todayAppts.isEmpty ? 0.0 : completed / todayAppts.length;

      return _GlassCard(
        child: Column(
          children: [
            Row(
              children: [
                // Expanded (not intrinsic width) so the three pills share
                // the row evenly on narrow screens instead of overflowing.
                Expanded(
                  child: _OverviewPill(
                    icon: Icons.schedule_rounded,
                    label: 'Booked',
                    value: compactCount(booked),
                    color: AppColors.primary,
                    bg: AppColors.primary.withAlpha(12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OverviewPill(
                    icon: Icons.check_circle_rounded,
                    label: 'Completed',
                    value: compactCount(completed),
                    color: AppColors.success,
                    bg: AppColors.success.withAlpha(12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OverviewPill(
                    icon: Icons.people_rounded,
                    label: 'Total',
                    value: compactCount(todayAppts.length),
                    color: AppColors.info,
                    bg: AppColors.info.withAlpha(12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Progress bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: AppColors.textDisabled.withAlpha(40),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.success,
                      ),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(pct * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'completion rate today',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textCaption,
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  PATIENT ANALYTICS
  // ══════════════════════════════════════════════════════════════
  Widget _buildAnalyticsRow(DoctorController controller) {
    return Obx(() {
      final total = controller.totalAppointments.value.toDouble();
      final completed = controller.completedAppointments.value.toDouble();
      const upcoming = 0.0; // not in controller, skip
      final cancelled = controller.cancelledAppointments.value.toDouble();

      final bars = [
        _BarData(
          label: 'Completed',
          value: completed,
          color: AppColors.success,
        ),
        _BarData(label: 'Upcoming', value: upcoming, color: AppColors.primary),
        _BarData(label: 'Cancelled', value: cancelled, color: AppColors.error),
      ];

      return _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Appointment Distribution',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textHeading,
              ),
            ),
            const SizedBox(height: 18),
            ...bars.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ModernBar(data: b, total: total),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms, delay: 300.ms);
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  RECENT ACTIVITY — Timeline
  // ══════════════════════════════════════════════════════════════
  Widget _buildRecentActivity(DoctorController controller) {
    return Obx(() {
      final appts = controller.appointments;

      // Recent Activity shows ONLY today's and yesterday's appointments
      // (most recent first — the controller's list is already ordered by
      // created_at desc). Each day is capped separately (10 per group) so
      // both the Today and Yesterday sections stay populated and scannable
      // — a busy day can never starve the other day's section.
      final now = DateTime.now();
      final todayKey = _dateKey(now);
      final yesterdayKey = _dateKey(now.subtract(const Duration(days: 1)));
      final todayAppts = appts
          .where((a) => a.appointmentDate == todayKey)
          .take(10)
          .toList();
      final yesterdayAppts = appts
          .where((a) => a.appointmentDate == yesterdayKey)
          .take(10)
          .toList();

      if (todayAppts.isEmpty && yesterdayAppts.isEmpty) {
        return _GlassCard(
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.inbox_rounded,
                  size: 36,
                  color: AppColors.textDisabled.withAlpha(80),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No recent appointments',
                  style: TextStyle(color: AppColors.textCaption),
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (todayAppts.isNotEmpty) ...[
            _buildActivityGroupHeader(
              label: 'Today',
              count: todayAppts.length,
              groupKey: const ValueKey('activity_group_today'),
            ),
            const SizedBox(height: 12),
            ..._buildActivityRows(controller, todayAppts),
          ],
          if (yesterdayAppts.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildActivityGroupHeader(
              label: 'Yesterday',
              count: yesterdayAppts.length,
              groupKey: const ValueKey('activity_group_yesterday'),
            ),
            const SizedBox(height: 12),
            ..._buildActivityRows(
              controller,
              yesterdayAppts,
              startIndex: todayAppts.length,
            ),
          ],
        ],
      );
    });
  }

  /// Builds the timeline rows for one Recent Activity group ([rows]).
  ///
  /// [startIndex] staggers the entrance animation so the whole timeline
  /// cascades as one sequence even though it is split across groups.
  List<Widget> _buildActivityRows(
    DoctorController controller,
    List<AppointmentModel> rows, {
    int startIndex = 0,
  }) {
    return rows.asMap().entries.map((entry) {
      final i = entry.key;
      final a = entry.value;
      final isLast = i == rows.length - 1;
      final statusColor = a.status == 'Completed'
          ? AppColors.success
          : a.status == 'Cancelled'
          ? AppColors.error
          : a.status == AppointmentStatus.pending
          ? AppColors.warning
          : AppColors.primary;

      // 5px bottom margin on every card so the Recent Activity list has a
      // consistent gap between each timeline row.
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Timeline rail: node + connector (Expanded so it spans
              //    the card's full height, like the history timeline) ──
              SizedBox(
                width: 12,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        border: Border.all(
                          color: statusColor.withAlpha(50),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withAlpha(40),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                statusColor.withAlpha(40),
                                statusColor.withAlpha(5),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // ── Card — same full-width row treatment as the history /
              //    appointments cards: header (avatar + name + status) and
              //    then each datum on its own full-width row, so nothing
              //    is ever squeezed or truncated on narrow screens. ──
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.textDisabled.withAlpha(25),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(6),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header: mini avatar + patient name + status chip ──
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              size: 18,
                              color: statusColor.withAlpha(180),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              a.patientName ?? 'Patient',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: AppColors.textHeading,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              a.status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // ── Time — its own full-width row ──
                      const SizedBox(height: 10),
                      AppointmentInfoRow(
                        icon: Icons.access_time_rounded,
                        iconColor: AppColors.accent,
                        label: 'Time',
                        value: a.appointmentTime ?? 'N/A',
                      ),
                      // ── Date — its own full-width row ──
                      const SizedBox(height: 10),
                      AppointmentInfoRow(
                        icon: Icons.calendar_month_rounded,
                        iconColor: AppColors.primary,
                        label: 'Date',
                        value: a.displayDate ?? 'N/A',
                      ),
                      // ── Pending: full-width Confirm action so the
                      //    clinic can accept a booking right from the
                      //    timeline (never squeezed next to the chip) ──
                      if (a.status == AppointmentStatus.pending) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: Material(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () =>
                                  showConfirmAppointmentDialog(controller, a),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 11),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Confirm',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(
        duration: 300.ms,
        delay: (300 + (startIndex + i) * 70).ms,
      );
    }).toList();
  }

  /// Small header above each Recent Activity group (Today / Yesterday),
  /// with a count badge and a trailing hairline so the timeline reads as
  /// clearly sectioned.
  Widget _buildActivityGroupHeader({
    required String label,
    required int count,
    required Key groupKey,
  }) {
    return Row(
      key: groupKey,
      children: [
        Icon(
          label == 'Today' ? Icons.today_rounded : Icons.history_rounded,
          size: 15,
          color: AppColors.primary,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textHeading,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.textDisabled.withAlpha(25),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SECTION TITLE
  // ══════════════════════════════════════════════════════════════
  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.textHeading,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SHIMMER GRID
  // ══════════════════════════════════════════════════════════════
  Widget _buildShimmerGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.25,
      children: List.generate(
        6,
        (_) => Shimmer.fromColors(
          baseColor: const Color(0xFFE8E4DA),
          highlightColor: const Color(0xFFF4EFE4),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  REUSABLE WIDGETS
// ══════════════════════════════════════════════════════════════════

/// Full-bleed header shell with gradient + decorative circles
class _HeaderShell extends StatelessWidget {
  final Widget child;
  const _HeaderShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F766E), Color(0xFF064E3B)],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F766E).withAlpha(80),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                right: -30,
                top: -40,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(6),
                  ),
                ),
              ),
              Positioned(
                left: -20,
                bottom: -30,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(4),
                  ),
                ),
              ),
              child,
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 450.ms)
        .slideY(begin: -0.08, end: 0, duration: 450.ms);
  }
}

/// Small pill chip used inside the dashboard Availability card.
class _AvailabilityChip extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  const _AvailabilityChip({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick stat chip inside the header strip
class _QuickStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;
  const _QuickStatChip({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final c = accent ?? Colors.white;
    // NOTE: no Expanded here — the callers (the header stats strip) already
    // wrap each chip in Expanded, and a nested Expanded inside this Row
    // would make two ParentDataWidgets compete for the same RenderObject
    // ("Incorrect use of ParentDataWidget" crash).
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: c.withAlpha(200)),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withAlpha(120),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Glass-style card used for content sections
class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.textDisabled.withAlpha(18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Modern stat card with gradient icon container
class _ModernStatCard extends StatelessWidget {
  final _StatCardData data;
  const _ModernStatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    // Material > InkWell > Ink so a tap shows a proper ripple above the
    // card's decoration (the Payments card opens the clinic payment
    // history). Cards without [onTap] are inert but keep the same look.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: data.onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.textDisabled.withAlpha(18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(6),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          // The stats grid is content-driven (Wrap), so the card simply sizes
          // to its content on any screen width — there is no fixed-height cell
          // left to overflow into or scale down from.
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: data.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: data.gradient.first.withAlpha(40),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(data.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textHeading,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textCaption,
              fontWeight: FontWeight.w500,
            ),
          ),
          // Breakdown lines (e.g. the Income card's Paid vs Pending split) —
          // each on its own row with a colored dot so the whole figure stays
          // scannable and the rows wrap instead of overflowing on narrow
          // cards. Each row renders as ONE Text ('Paid ₹12500') so the
          // amounts never collide with the big card value in tests.
          if (data.breakdown.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: AppColors.textDisabled.withAlpha(25),
            ),
            const SizedBox(height: 2),
            ...data.breakdown.map(_buildBreakdownLine),
          ],
        ],
          ),
        ),
      ),
    );
  }

  /// One breakdown row: a colored dot + "Label ₹amount" as a single Text
  /// (so the amount never collides with the big card value in tests),
  /// colored by the line's status (green Paid / amber Pending).
  Widget _buildBreakdownLine(_BreakdownLine line) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: line.color,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${line.label} ${line.amount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: line.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of a stat-card breakdown: a colored dot + "Label ₹amount".

/// One line of a stat-card breakdown: a colored dot + "Label ₹amount".
class _BreakdownLine {
  final String label;
  final String amount;
  final Color color;
  const _BreakdownLine({
    required this.label,
    required this.amount,
    required this.color,
  });
}

class _StatCardData {
  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradient;
  final Color softColor;
  final List<_BreakdownLine> breakdown;

  /// When true the card spans the whole stats grid width instead of
  /// sharing a 2-column row (the Payments / Income money cards).
  final bool fullWidth;
  final VoidCallback? onTap;
  const _StatCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    required this.softColor,
    this.breakdown = const [],
    this.fullWidth = false,
    this.onTap,
  });
}

/// Pill inside the Today's Overview card
class _OverviewPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bg;
  const _OverviewPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              color: color.withAlpha(160),
              fontWeight: w500,
            ),
          ),
        ],
      ),
    );
  }

  static const FontWeight w500 = FontWeight.w500;
}

/// Modern bar for analytics
class _ModernBar extends StatelessWidget {
  final _BarData data;
  final double total;
  const _ModernBar({required this.data, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (data.value / total * 100) : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            data.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textBody,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              // Track
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled.withAlpha(30),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              // Fill
              FractionallySizedBox(
                widthFactor: total > 0 ? data.value / total : 0,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [data.color, data.color.withAlpha(180)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: data.color.withAlpha(30),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 42,
          child: Text(
            '${pct.round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: data.color,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarData {
  final String label;
  final double value;
  final Color color;
  const _BarData({
    required this.label,
    required this.value,
    required this.color,
  });
}

// ══════════════════════════════════════════════════════════════════
//  SHIMMER SKELETON
// ══════════════════════════════════════════════════════════════════
class _DashboardShimmerSkeleton extends StatelessWidget {
  const _DashboardShimmerSkeleton();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Header skeleton
        SliverToBoxAdapter(
          child: Shimmer.fromColors(
            baseColor: const Color(0xFFE8E4DA),
            highlightColor: const Color(0xFFF4EFE4),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(150),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(60),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _shimBox(120, 14, Colors.white.withAlpha(70)),
                            const SizedBox(height: 10),
                            _shimBox(180, 11, Colors.white.withAlpha(45)),
                            const SizedBox(height: 8),
                            _shimBox(90, 10, Colors.white.withAlpha(35)),
                          ],
                        ),
                      ),
                      // Notification bell placeholder — matches the real
                      // 42px circle the header shows once loaded.
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(25),
                          border: Border.all(color: Colors.white.withAlpha(40)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Content skeleton
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.25,
                children: List.generate(
                  6,
                  (_) => Shimmer.fromColors(
                    baseColor: const Color(0xFFE8E4DA),
                    highlightColor: const Color(0xFFF4EFE4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.textDisabled.withAlpha(50),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _shimTitle(),
              const SizedBox(height: 14),
              _shimBox(
                double.infinity,
                80,
                AppColors.textDisabled.withAlpha(50),
                r: 20,
              ),
              const SizedBox(height: 28),
              _shimTitle(),
              const SizedBox(height: 14),
              _shimBox(
                double.infinity,
                140,
                AppColors.textDisabled.withAlpha(50),
                r: 20,
              ),
              const SizedBox(height: 28),
              _shimTitle(),
              const SizedBox(height: 14),
              _shimBox(
                double.infinity,
                140,
                AppColors.textDisabled.withAlpha(50),
                r: 20,
              ),
              const SizedBox(height: 28),
              _shimTitle(),
              const SizedBox(height: 14),
              ...List.generate(
                3,
                (i) => Padding(
                  // Matches the 5px gap between real Recent Activity rows.
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.textDisabled.withAlpha(60),
                            ),
                          ),
                          if (i < 2)
                            Container(
                              width: 2,
                              height: 170,
                              color: AppColors.textDisabled.withAlpha(30),
                            ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _shimBox(
                          double.infinity,
                          170,
                          AppColors.textDisabled.withAlpha(40),
                          r: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _shimBox(double w, double h, Color color, {double r = 8}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }

  Widget _shimTitle() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8E4DA),
      highlightColor: const Color(0xFFF4EFE4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.textDisabled.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 130,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.textDisabled.withAlpha(80),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
