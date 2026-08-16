import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../controllers/appointment_controller.dart';
import '../../controllers/payment_history_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/doctor_model.dart';
import '../../models/payment_model.dart';
import '../../services/launch_service.dart';
import '../../widgets/appointment_card.dart';
import '../../widgets/appointment_date_filter.dart';
import '../../widgets/booking_block_banner.dart';
import '../../widgets/appointment_details_sheet.dart';
import '../../widgets/appointment_search.dart';
import '../../widgets/pending_reschedule_confirm.dart';
import '../../routes/app_routes.dart';

class AppointmentHistoryScreen extends StatefulWidget {
  final bool isTab;

  const AppointmentHistoryScreen({super.key, this.isTab = false});

  @override
  State<AppointmentHistoryScreen> createState() =>
      _AppointmentHistoryScreenState();
}

class _AppointmentHistoryScreenState extends State<AppointmentHistoryScreen> {
  final _controller = Get.find<AppointmentController>();

  /// Selected date string (yyyy-MM-dd). Defaults to today, matching the
  /// doctor's appointments screen date filter.
  late String _selectedDate;

  /// Whether the header search field is visible. While searching, the
  /// date filter is hidden and results span every date.
  bool _isSearching = false;

  /// Current search query (raw text as typed).
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Appointments and the patient's payment rows load in PARALLEL so
      // the details sheet's fee/payment card is ready by the time a row is
      // tapped (a slow payment fetch must not delay the list).
      await Future.wait([
        _controller.loadAppointments(),
        PaymentHistoryController.instance.load(),
      ]);
      if (!mounted) return;
      // If the patient has appointments but none today, jump to the most
      // recent one so the history view isn't empty on first open.
      final hasToday = _controller.appointments.any(
        (a) => a.appointmentDate == _selectedDate,
      );
      if (!hasToday && _controller.uniqueAppointmentDates.isNotEmpty) {
        setState(() {
          _selectedDate = _controller.uniqueAppointmentDates.last;
        });
      }
    });
  }

  /// Shows a modern bottom sheet with the complete appointment details.
  ///
  /// Uses the shared [AppointmentDetailsSheet]; the phone number (when
  /// present) opens the dialer on tap and via the "Call Now" button, and
  /// the doctor's profile stays reachable from inside the sheet.
  ///
  /// When the patient's payments haven't loaded yet (fast tap on a slow
  /// network — the initState load is still in flight), waits for a fresh
  /// load so the fee/payment card is never silently missing. A loaded list
  /// that simply has no row for this appointment is authoritative and
  /// skips the refetch.
  Future<void> _showAppointmentDetails(AppointmentModel a) async {
    if (PaymentHistoryController.instance.payments.isEmpty) {
      await PaymentHistoryController.instance.load();
      if (!mounted) return;
    }
    final displayStatus = _controller.effectiveStatus(a);
    final canReschedule = _canReschedule(displayStatus);
    AppointmentDetailsSheet.show(
      appointment: a,
      displayStatus: displayStatus,
      headerName: a.doctorName ?? 'Doctor',
      closeKey: const ValueKey('patient_appointment_details_close'),
      extraRows: [
        if ((a.patientName ?? '').isNotEmpty)
          AppointmentDetailRow(
            icon: Icons.person_rounded,
            iconColor: AppColors.secondary,
            label: 'Patient',
            value: a.patientName!,
          ),
      ],
      // Fee/payment recorded for this appointment — the patient sees the
      // consultation fee, how they paid and what's still outstanding.
      payment: _paymentFor(a),
      // Persist a newly created Meet link so the doctor joins the same
      // room on their side.
      onSaveMeetLink: (link) =>
          _controller.saveMeetLink(a.appointmentId, link),
      footerActions: [
        // Reschedule — same entry point as the card chip, reachable from
        // inside the details sheet too.
        if (canReschedule)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              key: const ValueKey('patient_appointment_details_reschedule'),
              onPressed: () {
                Get.back();
                _openReschedule(a);
              },
              icon: const Icon(Icons.event_repeat_rounded, size: 18),
              label: const Text(
                'Reschedule',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent.withAlpha(80)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () {
              Get.back();
              _openDoctorProfile(a);
            },
            icon: const Icon(Icons.person_search_rounded, size: 18),
            label: const Text(
              'View Doctor Profile',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withAlpha(80)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The payment recorded against [a] (if any) — looked up by appointment
  /// id from the patient's own payment rows loaded by
  /// [PaymentHistoryController]. Null when the row has no payment (e.g.
  /// legacy bookings from before the payments table) or it's still loading.
  PaymentModel? _paymentFor(AppointmentModel a) {
    for (final p in PaymentHistoryController.instance.payments) {
      if (p.appointmentId == a.appointmentId) return p;
    }
    return null;
  }

  /// Opens the reschedule screen for a Pending/Upcoming appointment,
  /// passing the appointment so the screen can resolve its doctor and
  /// slot availability (same doctorDetails resolution as
  /// [_openDoctorProfile]).
  ///
  /// A **Pending** booking (awaiting clinic confirmation) first shows a
  /// confirmation dialog ([confirmIfPendingReschedule] — the single shared
  /// gate with the doctor's patient-history sheet) so moving a
  /// not-yet-confirmed appointment to a new slot needs an explicit
  /// acknowledgement. Confirmed rows navigate straight to the reschedule
  /// screen.
  void _openReschedule(AppointmentModel appointment) {
    confirmIfPendingReschedule(
      appointment,
      initiatedByDoctor: false,
      onProceed: () {
        if (mounted) _goToReschedule(appointment);
      },
    );
  }

  void _goToReschedule(AppointmentModel appointment) {
    Get.toNamed(
      AppRoutes.rescheduleAppointment,
      arguments: {'appointment': appointment},
    );
  }

  /// Whether a [displayStatus] appointment can be moved to another slot.
  ///
  /// Single shared rule ([AppointmentStatus.isReschedulable]) used by the
  /// card chip, the details-sheet action and the doctor's patient-history
  /// sheet, so every entry point can never drift apart: only
  /// Pending/Upcoming rows can be rescheduled (Completed / Cancelled
  /// cannot).
  bool _canReschedule(String displayStatus) =>
      AppointmentStatus.isReschedulable(displayStatus);

  void _openDoctorProfile(AppointmentModel appointment) {
    // Prefer a full DoctorModel reconstructed from the stored doctor
    // snapshot (in-app bookings store doctor.toJson()); fall back to the
    // minimal placeId+doctorName shape, which DoctorDetailScreen resolves
    // (it fetches full details by placeId on load).
    final details = appointment.doctorDetails;
    DoctorModel? doctor;
    if (details != null) {
      try {
        doctor = DoctorModel.fromJson(details);
      } catch (_) {
        doctor = null; // malformed snapshot — fall through to minimal
      }
    }
    // Guard on both placeId AND name: a parseable-but-malformed snapshot
    // (place_id present, name missing) would otherwise render a blank
    // detail title — fall through to the minimal path, where an empty
    // doctorName maps to a 'Doctor' fallback placeholder instead.
    if (doctor != null && doctor.placeId.isNotEmpty && doctor.name.isNotEmpty) {
      Get.toNamed(AppRoutes.doctorDetail, arguments: {'doctor': doctor});
      return;
    }
    final placeId =
        details?['place_id']?.toString() ?? details?['placeId']?.toString();
    Get.toNamed(
      AppRoutes.doctorDetail,
      arguments: {'placeId': placeId, 'doctorName': appointment.doctorName},
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            // ── Gradient Header ──
            _buildHeader(),

            // ── Date filter (shared with the doctor's appointments
            //    screen) — compact date card + expandable calendar.
            //    Hidden while searching so results span every date. ──
            if (!_isSearching)
              AppointmentDateFilter(
                    appointments: _controller.appointments,
                    selectedDate: _selectedDate,
                    onDateSelected: (dateKey) {
                      setState(() => _selectedDate = dateKey);
                    },
                  )
                  // Same entrance animation family as the header, with a slight
                  // stagger so the filter glides in right after it.
                  .animate()
                  .fadeIn(duration: 350.ms, delay: 120.ms)
                  .slideY(begin: -0.08, end: 0, duration: 350.ms),

            // ── Active-booking notice ──
            // While the patient holds ANY active (Pending/Upcoming)
            // booking, the same amber notice family explains that the
            // same doctor can't be re-booked until it's completed or
            // cancelled (booking with OTHER doctors stays allowed) — so
            // the history screen never surprises the patient about why
            // their next attempt at that doctor fails. Reactive:
            // appears/disappears as the appointment list changes (e.g.
            // right after a cancellation). No doctor context here, so
            // the call omits doctorPlaceId — the neutral notice path.
            Obx(() {
              final blockMessage = AppointmentController.bookingBlockMessage(
                _controller.appointments,
              );
              if (blockMessage == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: BookingBlockBanner(message: blockMessage),
              );
            }),

            // ── Content ──
            Expanded(
              child: Obx(() {
                if (_controller.isLoading.value) {
                  return _buildShimmerList();
                }

                final appointments = _controller.appointments;

                if (appointments.isEmpty) {
                  return _buildEmptyState();
                }

                final visible = _visibleAppointments();

                if (visible.isEmpty) {
                  return _isSearching && _searchQuery.isNotEmpty
                      ? _buildNoSearchResults()
                      : _buildNoAppointmentsForDate();
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 12, bottom: 24),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final appointment = visible[index];
                    final displayStatus = _controller.effectiveStatus(
                      appointment,
                    );
                    return AppointmentCard(
                          appointment: appointment,
                          displayStatus: displayStatus,
                          onTap: () => _showAppointmentDetails(appointment),
                          onMap: appointment.mapLocation != null
                              ? () => LaunchService.mapFromLocation(
                                  appointment.mapLocation,
                                )
                              : null,
                          onCancel: displayStatus == 'Upcoming'
                              ? () => _cancelAppointment(appointment)
                              : null,
                        )
                        .animate()
                        .fadeIn(duration: 300.ms, delay: (index * 80).ms)
                        .slideY(begin: 0.1, end: 0, duration: 300.ms);
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.6, 1.0],
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
            const Color(0xFF086B55),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(70),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top row: back button + title area
          Row(
            children: [
              if (!widget.isTab)
                GestureDetector(
                  onTap: Get.back,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(25),
                      border: Border.all(color: Colors.white.withAlpha(40)),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              if (!widget.isTab) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Appointments',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Search or browse by date',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withAlpha(170),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              // Search toggle (replaces the old appointment-count badge):
              // opens a search field that filters every appointment.
              AppointmentSearchToggle(
                toggleKey: const ValueKey('patient_history_search_toggle'),
                isSearching: _isSearching,
                onToggle: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchController.clear();
                      _searchQuery = '';
                    }
                  });
                },
              ),
            ],
          ),
          // Search field — shown while searching.
          if (_isSearching) ...[
            const SizedBox(height: 14),
            AppointmentSearchField(
              controller: _searchController,
              hintText: 'Search by doctor, phone, status, date…',
              onQueryChanged: (value) {
                setState(() => _searchQuery = value.trim());
              },
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  /// Appointments to render right now.
  ///
  /// While searching (even with an empty query) the whole list is shown,
  /// since the date filter is hidden and results span every date; the
  /// shared [filterAppointmentsForSearch] matches across all fields.
  /// Otherwise the normal date-filtered view is used.
  List<AppointmentModel> _visibleAppointments() {
    if (!_isSearching) {
      return _controller.getAppointmentsForDate(_selectedDate);
    }
    return filterAppointmentsForSearch(_controller.appointments, _searchQuery);
  }

  Widget _buildShimmerList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2A2A3E)
        : const Color(0xFFE8E4DA);
    final highlightColor = isDark
        ? const Color(0xFF3A3A4E)
        : const Color(0xFFF4EFE4);

    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerBox(48, 48, borderRadius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShimmerBox(160, 16),
                          const SizedBox(height: 6),
                          _ShimmerBox(100, 12),
                        ],
                      ),
                    ),
                    _ShimmerBox(70, 24, borderRadius: 8),
                  ],
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: Colors.white.withAlpha(50)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ShimmerBox(14, 14),
                    const SizedBox(width: 6),
                    _ShimmerBox(80, 13),
                    const SizedBox(width: 16),
                    _ShimmerBox(14, 14),
                    const SizedBox(width: 6),
                    _ShimmerBox(60, 13),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ShimmerBox(14, 14),
                    const SizedBox(width: 6),
                    _ShimmerBox(120, 13),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerBox(14, 14),
                    const SizedBox(width: 6),
                    Expanded(child: _ShimmerBox(double.infinity, 13)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ShimmerBox(double.infinity, 36, borderRadius: 10),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ShimmerBox(double.infinity, 36, borderRadius: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Empty state shown when the selected date has no appointments but
  /// the patient does have appointments on other days.
  Widget _buildNoAppointmentsForDate() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withAlpha(20),
            ),
            child: const Icon(
              Icons.event_busy_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No appointments on this date',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textHeading,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick another date from the calendar above.',
            style: const TextStyle(fontSize: 13, color: AppColors.textCaption),
          ),
        ],
      ),
    );
  }

  /// Empty state shown when a search query matches no appointments.
  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withAlpha(20),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No results found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textHeading,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No appointments match “$_searchQuery”',
            style: const TextStyle(fontSize: 13, color: AppColors.textCaption),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withAlpha(30),
                  AppColors.secondary.withAlpha(20),
                ],
              ),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              size: 44,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No appointments yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textHeading,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your appointments will appear here',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textCaption.withAlpha(180),
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
                onTap: () => Get.toNamed(AppRoutes.doctorSearch),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withAlpha(50)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(20),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Find a doctor',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppColors.primary.withAlpha(150),
                      ),
                    ],
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 600.ms, delay: 200.ms)
              .slideY(begin: 0.1, end: 0, duration: 400.ms),
        ],
      ),
    );
  }

  void _cancelAppointment(AppointmentModel appointment) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Appointment'),
        content: const Text(
          'Are you sure you want to cancel this appointment?',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Keep', style: TextStyle(color: AppColors.textCaption)),
          ),
          ElevatedButton(
            onPressed: () {
              _controller.cancelAppointment(appointment.appointmentId);
              Get.back();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel Appointment'),
          ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerBox(this.width, this.height, {this.borderRadius = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
