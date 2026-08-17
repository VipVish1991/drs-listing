import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../controllers/appointment_controller.dart';
import '../../controllers/doctor_controller.dart';
import '../../models/appointment_model.dart';
import '../../routes/app_routes.dart';
import '../../services/launch_service.dart';
import '../../services/share_service.dart';
import '../../utils/doctor_appointment_actions.dart';
import '../../utils/patient_history_csv.dart';
import '../../widgets/appointment_details_sheet.dart';
import '../../widgets/appointment_info_card.dart';
import '../../widgets/pending_reschedule_confirm.dart';
import '../../widgets/zoomable_image.dart';

/// Doctor-side patient history: every appointment this mobile number has
/// booked at the clinic, rendered as a timeline (newest → oldest) so the
/// doctor can quickly understand the patient's recurring problems,
/// prescriptions and visit pattern before the consultation.
///
/// Opened from the Appointments-tab card when the patient has prior
/// visits; first-time patients keep the quick details sheet instead.
class PatientHistoryScreen extends StatelessWidget {
  /// The patient's appointments at this clinic (includes the tapped one).
  final List<AppointmentModel> appointments;

  /// Appointment id of the booking the doctor tapped — highlighted as the
  /// "current visit" on the timeline.
  final String? highlightId;

  const PatientHistoryScreen({
    super.key,
    required this.appointments,
    this.highlightId,
  });

  /// Newest-first order (by appointment date, then time-of-day, then
  /// creation) so the most recent visit sits at the top of the timeline.
  ///
  /// Time strings are "12-hour clock with AM/PM" (e.g. "2:30 PM"), so a
  /// plain string compare would put "10:00 PM" before "2:00 PM"; the
  /// minute conversion keeps same-day visits in true chronological order.
  List<AppointmentModel> get _recentFirst {
    final list = List<AppointmentModel>.from(appointments);
    list.sort((a, b) {
      final c = (b.appointmentDate ?? '').compareTo(a.appointmentDate ?? '');
      if (c != 0) return c;
      final t = _timeToMinutes(
        b.appointmentTime ?? '',
      ).compareTo(_timeToMinutes(a.appointmentTime ?? ''));
      if (t != 0) return t;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });
    return list;
  }

  /// "h:mm AM/PM" → minutes since midnight, for same-day time sorting.
  /// Unparseable strings score 0 (kept stable via the createdAt tiebreak).
  static int _timeToMinutes(String time12h) {
    final parts = time12h.split(' ');
    if (parts.length != 2) return 0;
    final hm = parts[0].split(':');
    final h = int.tryParse(hm[0]) ?? 0;
    final m = int.tryParse(hm.length > 1 ? hm[1] : '0') ?? 0;
    final isPM = parts[1].toUpperCase() == 'PM';
    final h24 = h == 12 ? (isPM ? 12 : 0) : (isPM ? h + 12 : h);
    return h24 * 60 + m;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _recentFirst;
    // The header still renders above the empty state, so the patient
    // identity lookup must tolerate a zero-visit timeline (no `.first`
    // to fall back to).
    final name = _patientName(entries);
    final phone = entries.isEmpty
        ? null
        : entries
              .firstWhere(
                (a) => (a.patientPhone ?? '').isNotEmpty,
                orElse: () => entries.first,
              )
              .patientPhone;

    final completed = entries.where((a) => a.status == 'Completed').length;
    final cancelled = entries.where((a) => a.status == 'Cancelled').length;
    final active = entries.length - completed - cancelled;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(
              name,
              phone,
              entries.length,
              completed,
              cancelled,
              active,
              // Share/export is only useful once there's a visit to export.
              onExport: entries.isEmpty ? null : _exportCsv,
            ),
            Expanded(
              child: entries.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 16, 8, 16),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _buildTimelineEntry(context, entries, index),
                    ),
            ),
            // ── All Prescriptions — bottom action on the page (not in the
            //    card's details sheet). Opens the fullscreen swipeable
            //    photo gallery of every prescription, newest visit first.
            //    Always present (when there are visits); a patient with no
            //    prescriptions yet gets a friendly empty state inside. ──
            if (entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    key: const ValueKey('all_prescriptions_button'),
                    onPressed: () => _showAllPrescriptions(context),
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: const Text(
                      'All Prescriptions',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Exports the patient's full visit timeline (newest → oldest, matching
  /// the on-screen order) as a CSV and opens the system share sheet.
  /// Non-fatal: failures surface as a snackbar; an empty timeline shows a
  /// "Nothing to export" notice (the button is hidden in that case anyway).
  Future<void> _exportCsv() async {
    final entries = _recentFirst;
    if (entries.isEmpty) {
      Get.snackbar(
        'Nothing to export',
        'No visits to export',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    try {
      final csv = buildPatientHistoryCsv(entries);
      final name = _patientName(entries);
      final now = DateTime.now();
      final dateTag =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      await ShareService.shareCsvFile(
        csv: csv,
        filename: 'patient_history_$dateTag.csv',
        subject: 'Patient history — $name',
      );
    } catch (_) {
      Get.snackbar(
        'Export failed',
        'Could not share the CSV. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// The patient's name across the timeline — the first row that carries
  /// one (they all belong to the same mobile number). Empty timelines
  /// fall back to 'Patient' so the header renders above the empty state.
  String _patientName(List<AppointmentModel> entries) {
    if (entries.isEmpty) return 'Patient';
    return entries
            .firstWhere(
              (a) => (a.patientName ?? '').isNotEmpty,
              orElse: () => entries.first,
            )
            .patientName ??
        'Patient';
  }

  Widget _buildHeader(
    String name,
    String? phone,
    int visits,
    int completed,
    int cancelled,
    int active, {
    VoidCallback? onExport,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
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
            children: [
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
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Patient History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              // Share/export the visit timeline as CSV (hidden until there
              // is at least one visit to export).
              if (onExport != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Export CSV',
                  child: GestureDetector(
                    key: const Key('patient_history_export'),
                    onTap: onExport,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(25),
                        border: Border.all(color: Colors.white.withAlpha(40)),
                      ),
                      child: const Icon(
                        Icons.ios_share_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(30),
                  border: Border.all(
                    color: Colors.white.withAlpha(60),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    AppointmentDetailsSheet.initials(name),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (phone != null && phone.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      GestureDetector(
                        onTap: () => LaunchService.phone(phone),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.phone_rounded,
                              size: 13,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              phone,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '$visits visit${visits == 1 ? '' : 's'} at your clinic',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Visit summary chips
          Row(
            children: [
              _HeaderChip(
                icon: Icons.check_circle_rounded,
                label: '',
                value: '$completed',
                color: const Color(0xFF6EE7B7),
              ),
              const SizedBox(width: 8),
              _HeaderChip(
                icon: Icons.cancel_rounded,
                label: '',
                value: '$cancelled',
                color: const Color(0xFFFCA5A5),
              ),
              const SizedBox(width: 8),
              _HeaderChip(
                icon: Icons.schedule_rounded,
                label: '',
                value: '$active',
                color: Colors.white,
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildTimelineEntry(
    BuildContext context,
    List<AppointmentModel> entries,
    int index,
  ) {
    final a = entries[index];
    final isLast = index == entries.length - 1;
    final isCurrent = a.appointmentId == highlightId;
    final statusColor = AppointmentDetailsSheet.statusColor(a.status);
    final statusIcon = AppointmentDetailsSheet.statusIcon(a.status);

    // Global position of this visit's first image inside the shared
    // newest-first gallery (all prescriptions across every visit).
    final globalStartIndex = _galleryOffsetForVisit(index);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timeline rail: node + connector ──
          SizedBox(
            width: 10,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    border: Border.all(
                      color: statusColor.withAlpha(60),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withAlpha(45),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: statusColor.withAlpha(25),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // ── Visit card — shared layout with the doctor's Appointments
          //    tab (AppointmentInfoCard), so the full-width row treatment
          //    stays in one place. Only the timeline-specific chrome
          //    (Visit # / Current chips, status pill, symptoms) differs. ──
          Expanded(
            child: AppointmentInfoCard(
              appointment: a,
              // Tapping a visit card opens the full details sheet (same as
              // tapping an appointment on the doctor's Appointments tab).
              onTap: () => _showAppointmentDetails(a),
              borderColor: isCurrent
                  ? AppColors.primary.withAlpha(90)
                  : AppColors.textDisabled.withAlpha(22),
              borderWidth: isCurrent ? 1.6 : 1,
              shadowBlur: isCurrent ? 16 : 10,
              shadowAlpha: isCurrent ? 12 : 6,
              header: _buildVisitChips(index, isCurrent),
              showStatusPill: true,
              displayStatus: a.status,
              statusColor: statusColor,
              statusIcon: statusIcon,
              // Consultation type in the same full-width row the patient's
              // card uses — the doctor reads what the patient booked at a
              // glance. Hidden for legacy rows without a stored type.
              infoBlocks: [?AppointmentInfoBlock.consultationOf(a)],
              showSymptoms: true,
              // Tapping a prescription thumbnail opens the SAME shared
              // swipeable gallery as the bottom button, positioned at that
              // exact image (global index across all visits).
              onPrescriptionThumbnailTap: a.prescriptionUrls.isEmpty
                  ? null
                  : (thumbIndex) => _showAllPrescriptions(
                      context,
                      initialIndex: globalStartIndex + thumbIndex,
                    ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms, delay: (200 + index * 80).ms);
  }

  /// Number of prescription images belonging to all visits BEFORE [index]
  /// in the newest-first timeline — the gallery offset where visit
  /// [index]'s images begin.
  int _galleryOffsetForVisit(int index) {
    final visits = _recentFirst;
    var offset = 0;
    for (var i = 0; i < index && i < visits.length; i++) {
      offset += visits[i].prescriptionUrls.length;
    }
    return offset;
  }

  /// Opens the full appointment-details sheet for a tapped visit — the
  /// same sheet shown when tapping an appointment on the doctor's
  /// Appointments tab. The "All Prescriptions" action lives on the page
  /// itself (bottom button), not inside this modal.
  ///
  /// A Pending/Upcoming visit additionally gets a **Reschedule** action
  /// (doctor-initiated — the clinic picks the patient's new slot and the
  /// patient is notified via the `appointment_rescheduled_by_doctor`
  /// event). Completed/Cancelled visits can't be moved.
  void _showAppointmentDetails(AppointmentModel a) {
    final displayStatus = a.status.isEmpty ? 'Upcoming' : a.status;
    final canReschedule = _canReschedule(
      Get.find<AppointmentController>().effectiveStatus(a),
    );
    final controller = Get.find<DoctorController>();
    final payment = controller.paymentsByAppointment[a.appointmentId];
    // "Mark Completed" is gated on the consultation fee being settled —
    // while the payment is still Pending (unpaid), the action renders
    // disabled, exactly like the Appointments-tab cards and sheet.
    final paymentPending =
        payment != null && payment.paymentStatus == 'Pending';
    AppointmentDetailsSheet.show(
      appointment: a,
      // Same empty→'Upcoming' fallback as the doctor's Appointments tab.
      displayStatus: displayStatus,
      headerName: a.patientName ?? 'Patient',
      closeKey: const ValueKey('history_details_close'),
      phoneNumber: a.patientPhone ?? '',
      // Fee/payment recorded for this visit (the same map the Appointments
      // tab cards use) — the clinic sees what the patient owes and how it
      // stands right inside the sheet.
      payment: payment,
      // Doctor actions right inside the sheet (same compact pills as the
      // Appointments tab): mark the consultation complete or cancel it.
      showDoctorActions: true,
      onCancel: () => showCancelAppointmentDialog(controller, a),
      onComplete: paymentPending
          ? null
          : () => showCompleteAppointmentDialog(controller, a),
      footerActions: [
        if (canReschedule)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              key: const ValueKey('doctor_patient_history_reschedule'),
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
      ],
    );
  }

  /// Whether a [displayStatus] appointment can be moved to another slot by
  /// the clinic. Uses the same single shared rule as the patient side
  /// ([AppointmentStatus.isReschedulable]) so the two entry points can
  /// never drift apart. The status is the EFFECTIVE one (an Upcoming
  /// appointment whose time has passed renders as Completed) so a lapsed
  /// slot is never reschedulable.
  bool _canReschedule(String effectiveStatus) =>
      AppointmentStatus.isReschedulable(effectiveStatus);

  /// Opens the shared reschedule screen in doctor-initiated mode (the
  /// clinic picks the new slot; the patient gets notified of the move).
  ///
  /// A **Pending** booking (awaiting clinic confirmation) first shows a
  /// confirmation dialog ([confirmIfPendingReschedule] — the single shared
  /// gate with the patient's history screen) so the clinic acknowledges
  /// moving a not-yet-confirmed request to a new slot.
  void _openReschedule(AppointmentModel appointment) {
    confirmIfPendingReschedule(
      appointment,
      initiatedByDoctor: true,
      onProceed: () => _goToReschedule(appointment),
    );
  }

  void _goToReschedule(AppointmentModel appointment) {
    Get.toNamed(
      AppRoutes.rescheduleAppointment,
      arguments: {'appointment': appointment, 'initiatedByDoctor': true},
    );
  }

  /// Visit # chip (display order — Visit 1 is the most recent) + optional
  /// Current badge — the history card's header. A Wrap (not a Row) so the
  /// Current badge drops to a second line instead of overflowing at
  /// extreme text scales.
  Widget _buildVisitChips(int index, bool isCurrent) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      runSpacing: 6,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.primary.withAlpha(16)
                : AppColors.bgSecondarySurface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isCurrent
                  ? AppColors.primary.withAlpha(45)
                  : AppColors.textCaption.withAlpha(30),
            ),
          ),
          child: Text(
            'Visit ${index + 1}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isCurrent ? AppColors.primary : AppColors.textCaption,
            ),
          ),
        ),
        if (isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withAlpha(50)),
            ),
            child: const Text(
              'Current',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }

  /// Opens the fullscreen photo-gallery of every prescription the patient
  /// has received — newest visit first (matching the descending timeline).
  /// Like a photo gallery: swipe left/right to browse, pinch or double-tap
  /// to zoom, with the visit date/time caption under each image. [initialIndex] opens the
  /// gallery at a specific image (used when the doctor taps a thumbnail on
  /// a timeline card). A patient with no prescriptions yet sees a friendly
  /// empty state inside.
  void _showAllPrescriptions(BuildContext context, {int initialIndex = 0}) {
    final entries = _allPrescriptionEntries();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PrescriptionSwipeGallery(
          entries: entries,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  /// Every prescription image across all visits in the shared newest-first
  /// gallery order, each tagged with its visit number + date/time caption.
  List<_GalleryEntry> _allPrescriptionEntries() {
    final visits = _recentFirst;
    final entries = <_GalleryEntry>[];
    for (int i = 0; i < visits.length; i++) {
      final v = visits[i];
      for (final url in v.prescriptionUrls) {
        entries.add(
          _GalleryEntry(
            url: url,
            visitNo: i + 1,
            date: v.displayDate ?? 'N/A',
            time: v.appointmentTime ?? '',
          ),
        );
      }
    }
    return entries;
  }

  Widget _buildEmptyState() {
    // The "No appointments found" notice enters with the same fade + slide
    // family as the rest of the app's empty states.
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy_rounded,
            size: 44,
            color: AppColors.textDisabled,
          ),
          SizedBox(height: 12),
          Text(
            'No appointments found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textHeading,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.08, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }
}

/// Small stat chip inside the history header.
class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _HeaderChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withAlpha(180),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One image in the swipeable gallery: its URL + which visit it belongs to
/// (display order) + that visit's date/time for the caption.
class _GalleryEntry {
  final String url;
  final int visitNo;
  final String date;
  final String time;

  const _GalleryEntry({
    required this.url,
    required this.visitNo,
    required this.date,
    required this.time,
  });
}

/// Fullscreen black photo gallery: PageView of prescription images with
/// pinch + double-tap zoom, a N/M counter and a "Visit N • dd-MM-yyyy •
/// time" caption. Swipe left/right to browse — newest visit first.
class _PrescriptionSwipeGallery extends StatefulWidget {
  final List<_GalleryEntry> entries;

  /// Image to open the gallery on (defaults to the first/newest).
  final int initialIndex;

  const _PrescriptionSwipeGallery({
    required this.entries,
    this.initialIndex = 0,
  });

  @override
  State<_PrescriptionSwipeGallery> createState() =>
      _PrescriptionSwipeGalleryState();
}

class _PrescriptionSwipeGalleryState extends State<_PrescriptionSwipeGallery> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final total = widget.entries.length;
    _currentIndex = total == 0 ? 0 : widget.initialIndex.clamp(0, total - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.entries.length;
    // No prescriptions yet — friendly empty state (button is always
    // present on the page when there are visits).
    if (total == 0) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.medication_rounded, size: 44, color: Colors.white38),
              SizedBox(height: 12),
              Text(
                'No prescriptions yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Prescriptions the doctor shares will appear here.',
                style: TextStyle(fontSize: 12.5, color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }
    final entry = widget.entries[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_currentIndex + 1} / $total',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                AppConstants.zoomHintText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // ── Swipeable pages of prescription images ──
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return Center(
                child: ZoomableImage(
                  child: Image.network(
                    widget.entries[index].url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white54),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          // ── Caption: visit number + dd-MM-yyyy date + time ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(150),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Visit ${entry.visitNo} • ${entry.date}'
                '${entry.time.isNotEmpty ? ' • ${entry.time}' : ''}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
