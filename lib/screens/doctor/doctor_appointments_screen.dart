import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../controllers/doctor_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/payment_model.dart';
import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';
import '../../utils/appointment_dialogs.dart';
import '../../utils/image_optimizer.dart';
import '../../utils/snackbar_helpers.dart';
import '../../widgets/appointment_date_filter.dart';
import '../../widgets/appointment_details_sheet.dart';
import '../../widgets/appointment_info_card.dart';
import '../../widgets/appointment_search.dart';
import '../../widgets/image_processing_dialog.dart';

class DoctorAppointmentsScreen extends StatefulWidget {
  const DoctorAppointmentsScreen({super.key});

  @override
  State<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen> {
  final _controller = Get.find<DoctorController>();

  /// Selected date string (yyyy-MM-dd). Defaults to today.
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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _statusLabel(String status) {
    return status.isEmpty ? 'Upcoming' : status;
  }

  Color _avatarBg(int index) {
    const colors = [
      Color(0xFFE8EAF5),
      Color(0xFFF0E6F8),
      Color(0xFFE6F2F5),
      Color(0xFFF5ECE6),
      Color(0xFFE6F0F0),
      Color(0xFFF0F0E6),
    ];
    return colors[index % colors.length];
  }

  /// Single-letter avatar initial (matches the patient-side card and the
  /// reference design's one-letter avatars).
  String _avatarInitial(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : 'P';
  }

  void _handleCancel(AppointmentModel a) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Appointment'),
        content: Text('Cancel appointment with ${a.patientName ?? 'patient'}?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Keep', style: TextStyle(color: AppColors.textCaption)),
          ),
          ElevatedButton(
            onPressed: () {
              _controller.updateAppointmentStatus(a.appointmentId, 'Cancelled');
              Get.back();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _handleComplete(AppointmentModel a) {
    // Every consultation type (In-Clinic included) offers the camera
    // prescription upload when the doctor marks the appointment complete;
    // "Choose from Gallery" picks an existing photo instead, and
    // "Complete without Prescription" stays available as a fallback.
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppColors.bgCard,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
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
                  Icons.medication_rounded,
                  size: 32,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Complete Appointment',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textHeading,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                a.consultationTypeLabel != null
                    ? '${a.consultationTypeLabel} with ${a.patientName ?? 'patient'}.'
                          ' Upload the prescription photo to share it with the patient.'
                    : 'Complete the appointment with ${a.patientName ?? 'patient'}.'
                          ' Upload the prescription photo to share it with the patient.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.textBody,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Get.back();
                    _startPrescriptionUpload(a, source: ImageSource.camera);
                  },
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Text(
                    'Upload Prescription & Complete',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Get.back();
                    _startPrescriptionUpload(a, source: ImageSource.gallery);
                  },
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text(
                    'Choose from Gallery',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: AppColors.success,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: BorderSide(color: AppColors.success.withAlpha(60)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () {
                    Get.back();
                    _controller.updateAppointmentStatus(
                      a.appointmentId,
                      'Completed',
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textCaption,
                    side: BorderSide(
                      color: AppColors.textCaption.withAlpha(60),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Complete without Prescription',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Camera/gallery → preview → upload → complete flow for Tele/Video
  /// consultations. [source] selects where the prescription photo comes
  /// from: the camera ([ImageSource.camera]) or an existing image in the
  /// device gallery ([ImageSource.gallery]). Both paths run the SAME
  /// processing dialog + 9:16 preview + upload pipeline.
  Future<void> _startPrescriptionUpload(
    AppointmentModel a, {
    ImageSource source = ImageSource.camera,
  }) async {
    final doctorPlaceId =
        _controller.currentDoctor.value?.placeId ??
        (a.doctorDetails?['place_id']?.toString() ?? '');
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 3000,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      // Feedback between the photo capture/pick and the preview sheet: the
      // decode + 9:16 portrait padding + downscale (compute isolate) can
      // take a moment on large photos, so show the processing dialog
      // before it instead of leaving a dead pause.
      ImageProcessingDialog.show();

      final bytes = await picked.readAsBytes();

      final uploadBytes =
          (await compute(PrescriptionImageOptimizer.optimizePortrait, bytes)) ??
          bytes;

      // Processing done — dismiss the loading dialog (regardless of
      // mounted: it lives on the navigator, not this widget) before
      // opening the preview sheet.
      if (Get.isDialogOpen ?? false) Get.back();
      if (!mounted) return;

      final shouldUpload = await _showPrescriptionPreview(a, uploadBytes);
      if (shouldUpload != true || !mounted) return;

      final result = await Get.dialog<String?>(
        PrescriptionUploadDialog(
          upload: () => SupabaseService().uploadPrescriptionImage(
            a.appointmentId,
            doctorPlaceId: doctorPlaceId,
            bytes: uploadBytes,
          ),
        ),
        barrierDismissible: false,
      );
      if (!mounted) return;

      if (result == kCompleteWithoutPrescription) {
        await _controller.updateAppointmentStatus(a.appointmentId, 'Completed');
        if (mounted) {
          showErrorSnackbar(
            'Appointment completed, but the prescription upload failed',
          );
        }
      } else if (result != null && result.isNotEmpty) {
        await _controller.completeAppointmentWithPrescription(a.appointmentId, [
          result,
        ]);
        if (mounted) {
          showSuccessSnackbar('Appointment completed & prescription uploaded');
        }
      }
    } catch (_) {
      // Close any open overlay (processing dialog / preview sheet) even if
      // this screen unmounted meanwhile — dialogs live on the navigator,
      // not on this widget, so they must not leak.
      Get.back();
      if (mounted) {
        showErrorSnackbar(
          source == ImageSource.gallery
              ? 'Could not open the gallery. Please try again.'
              : 'Could not open the camera. Please try again.',
        );
      }
    }
  }

  Future<bool?> _showPrescriptionPreview(AppointmentModel a, Uint8List bytes) {
    return Get.bottomSheet<bool>(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.bgMain,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textCaption.withAlpha(90),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.success.withAlpha(18),
                    ),
                    child: const Icon(
                      Icons.medication_rounded,
                      size: 20,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Prescription Preview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textHeading,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Get.back(result: false),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.textCaption.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.textCaption,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Full-height 9:16 portrait frame showing the COMPLETE page —
              // the upload bytes are padded to a 9:16 white canvas by
              // PrescriptionImageOptimizer (letterboxed, never cropped), so
              // BoxFit.contain fills the frame edge-to-edge: the white bars
              // read as page margins and the whole prescription is visible.
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'For ${a.patientName ?? 'patient'} — ${a.displayDate ?? ''} '
                '${a.appointmentTime ?? ''}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textCaption,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => Get.back(result: false),
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text(
                          'Retake',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textCaption,
                          side: BorderSide(
                            color: AppColors.textCaption.withAlpha(60),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => Get.back(result: true),
                        icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                        label: const Text(
                          'Upload & Complete',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
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
            ],
          ),
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  void _handleConfirm(AppointmentModel a) {
    showConfirmAppointmentDialog(_controller, a);
  }

  /// "Mark Paid" confirm — only offered for OFFLINE payments still
  /// Pending (the clinic has actually received the cash). Online payments
  /// are settled at booking time and need no clinic action.
  void _handleMarkPaid(AppointmentModel a, PaymentModel p) {
    _confirmPaymentAction(a, p, status: 'Paid');
  }

  /// "Refund" confirm — flips an offline Pending payment to Refunded.
  void _handleRefund(AppointmentModel a, PaymentModel p) {
    _confirmPaymentAction(a, p, status: 'Refunded');
  }

  void _confirmPaymentAction(
    AppointmentModel a,
    PaymentModel p, {
    required String status,
  }) {
    final isPaid = status == 'Paid';
    // Tracks the in-flight server update so the confirm button shows a
    // spinner and can't be double-tapped while the status flip runs.
    var busy = false;
    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(isPaid ? 'Mark Payment Paid' : 'Refund Payment'),
            content: Text(
              isPaid
                  ? 'Confirm ${p.amountLabel} received from '
                        '${a.patientName ?? 'patient'} for this appointment?'
                  : 'Mark ${p.amountLabel} as refunded to '
                        '${a.patientName ?? 'patient'}?',
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Get.back(),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textCaption),
                ),
              ),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        // Show the in-button loading spinner and lock the
                        // dialog until the server answers.
                        setState(() => busy = true);
                        // Only claim success when the status flip actually
                        // landed server-side — a silent RLS denial or
                        // offline write must never show a false
                        // "Payment marked as Paid".
                        final ok = await _controller.markPaymentStatus(
                          p,
                          status,
                        );
                        if (!context.mounted) return;
                        Get.back();
                        if (ok) {
                          showSuccessSnackbar(
                            isPaid
                                ? 'Payment marked as Paid'
                                : 'Payment marked as Refunded',
                          );
                        } else {
                          showErrorSnackbar(
                            'Could not update the payment. Please try again.',
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPaid ? AppColors.success : AppColors.info,
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isPaid ? 'Mark Paid' : 'Refund'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
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
            Expanded(child: _buildAppointmentsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(60),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Obx(() {
        final doctor = _controller.currentDoctor.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
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
                      doctor != null && doctor.name.isNotEmpty
                          ? doctor.name[0]
                          : 'D',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Appointments',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Manage your patient appointments',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                AppointmentSearchToggle(
                  toggleKey: const ValueKey('appointments_search_toggle'),
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
            if (_isSearching) ...[
              const SizedBox(height: 14),
              AppointmentSearchField(
                controller: _searchController,
                hintText: 'Search by patient, phone, status, date…',
                onQueryChanged: (value) {
                  setState(() => _searchQuery = value.trim());
                },
              ),
            ],
          ],
        );
      }),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  List<AppointmentModel> _visibleAppointments() {
    if (!_isSearching) {
      return _controller.getAppointmentsForDate(_selectedDate);
    }
    return filterAppointmentsForSearch(_controller.appointments, _searchQuery);
  }

  void _showAppointmentDetails(AppointmentModel a) {
    // The controller holds the doctor's FULL appointment list (no date
    // filter), so the "has this mobile number visited before?" check is
    // instant — no extra query. Patients with prior visits open the
    // timeline history page; first-time patients keep the quick sheet.
    final phone = a.patientPhone?.trim() ?? '';
    final history = phone.isEmpty
        ? <AppointmentModel>[]
        : _controller.appointments
              .where((x) => (x.patientPhone?.trim() ?? '') == phone)
              .toList();
    if (history.length > 1) {
      Get.toNamed(
        AppRoutes.patientHistory,
        arguments: {'appointments': history, 'highlightId': a.appointmentId},
      );
      return;
    }
    AppointmentDetailsSheet.show(
      appointment: a,
      displayStatus: _statusLabel(a.status),
      headerName: a.patientName ?? 'Patient',
      closeKey: const ValueKey('appointment_details_close'),
      phoneNumber: a.patientPhone ?? '',
      // Fee/payment recorded for this appointment (same map the cards use),
      // so the sheet shows what the consultation costs and how it stands.
      payment: _controller.paymentsByAppointment[a.appointmentId],
    );
  }

  Widget _buildAppointmentsList() {
    return Obx(() {
      if (_controller.isLoadingAppointments.value) {
        return _buildShimmer();
      }

      final dayAppts = _visibleAppointments();

      if (dayAppts.isEmpty) {
        final isSearchEmpty = _isSearching && _searchQuery.isNotEmpty;
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
                child: Icon(
                  isSearchEmpty
                      ? Icons.search_off_rounded
                      : Icons.event_busy_rounded,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isSearchEmpty ? 'No results found' : 'No appointments',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textHeading,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isSearchEmpty
                    ? 'No appointments match “$_searchQuery”'
                    : 'No appointments for $_selectedDate',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textCaption,
                ),
              ),
            ],
          ),
        )
            // The "No appointments" / "No results" notice enters with the
            // same fade + slide family as the rest of the screen.
            .animate()
            .fadeIn(duration: 300.ms, curve: Curves.easeOut)
            .slideY(begin: 0.08, end: 0, duration: 300.ms, curve: Curves.easeOut);
      }

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: dayAppts.length,
        itemBuilder: (context, index) {
          final a = dayAppts[index];
          final status = _statusLabel(a.status);
          final isFinalized = status == 'Cancelled' || status == 'Completed';
          final isPending = status == AppointmentStatus.pending;

          // Per-card Obx for the payment line: ListView's itemBuilder runs
          // lazily, AFTER the outer Obx builder — outside GetX's reactive
          // tracking — so a payment lookup there alone never subscribes
          // anything and a Mark Paid / Refund reload
          // (loadPayments → paymentsByAppointment.value = …) leaves the
          // card stale. Reading the map synchronously inside its own Obx
          // makes each visible card rebuild in place when the payment
          // status flips (Pending → Paid / Refunded: chip updates, settle
          // actions disappear).
          return Obx(() {
            final payment =
                _controller.paymentsByAppointment[a.appointmentId];
            final paymentActionable =
                payment != null &&
                payment.paymentMethod == 'offline' &&
                payment.paymentStatus == 'Pending';

            return _ModernAppointmentCard(
              appointment: a,
              displayStatus: status,
              isFinalized: isFinalized,
              statusColor: AppointmentDetailsSheet.statusColor(status),
              statusIcon: AppointmentDetailsSheet.statusIcon(status),
              avatarInitials: _avatarInitial(a.patientName ?? 'Patient'),
              avatarColor: _avatarBg(index),
              index: index,
              payment: payment,
              onMarkPaid: payment != null && paymentActionable
                  ? () => _handleMarkPaid(a, payment)
                  : null,
              onRefund: payment != null && paymentActionable
                  ? () => _handleRefund(a, payment)
                  : null,
              onTap: () => _showAppointmentDetails(a),
              onCancel: () => _handleCancel(a),
              onConfirm: isPending ? () => _handleConfirm(a) : null,
              onComplete: () => _handleComplete(a),
            );
          });
        },
      );
    });
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: 3,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: const Color(0xFFE8E4DA),
        highlightColor: const Color(0xFFF4EFE4),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Modern appointment card with name, date, time, and description
// ════════════════════════════════════════════════════════════════════
class _ModernAppointmentCard extends StatelessWidget {
  final AppointmentModel appointment;
  final String displayStatus;
  final bool isFinalized;
  final Color statusColor;
  final IconData statusIcon;
  final String avatarInitials;
  final Color avatarColor;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;
  final VoidCallback onComplete;

  /// The payment recorded against this appointment (if any). Offline
  /// Pending rows render Mark Paid / Refund actions; every other status
  /// renders as an informational chip.
  final PaymentModel? payment;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onRefund;

  const _ModernAppointmentCard({
    required this.appointment,
    required this.displayStatus,
    required this.isFinalized,
    required this.statusColor,
    required this.statusIcon,
    required this.avatarInitials,
    required this.avatarColor,
    required this.index,
    required this.onTap,
    required this.onCancel,
    this.onConfirm,
    required this.onComplete,
    this.payment,
    this.onMarkPaid,
    this.onRefund,
  });

  @override
  Widget build(BuildContext context) {
    final a = appointment;

    return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: AppointmentInfoCard(
            appointment: a,
            onTap: onTap,
            accentColor: statusColor,
            borderRadius: 20,
            // Left pad 14 (not 16) so the 5px accent bar + content spacing
            // stays pixel-identical to the pre-extraction card.
            padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
            shadowBlur: 16,
            shadowAlpha: 8,
            header: AppointmentCardHeader(
              name: a.patientName ?? 'Patient',
              statusLabel: displayStatus,
              statusIcon: statusIcon,
              statusColor: statusColor,
              avatarInitials: avatarInitials,
              avatarColor: avatarColor,
            ),
            // Full-width info row below the grid: the consultation type
            // (what the patient booked — hidden for legacy rows) sits in
            // the phone's former spot. The patient's phone now lives only
            // in the details sheet (Call Now / dial row).
            infoBlocks: [?AppointmentInfoBlock.consultationOf(a)],
            displayStatus: displayStatus,
            statusColor: statusColor,
            statusIcon: statusIcon,
            // Payment line (amount + status chip, Mark Paid/Refund actions
            // for offline Pending rows) — renders between the info grid
            // and the appointment action buttons.
            extraRow: payment != null ? _buildPaymentRow(payment!) : null,
            // Shared appointment-list look: label + first thumbnail + a
            // light-green "Click" pill opening the fullscreen viewer.
            prescriptionClickRow: true,
            // Wrap (not Row) so the action buttons flow to a second line on
            // narrow screens / large text scales instead of overflowing the
            // card edge.
            actions: isFinalized
                ? null
                : Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _ModernActionBtn(
                        label: 'Cancel',
                        icon: Icons.close_rounded,
                        color: AppColors.error,
                        onTap: onCancel,
                      ),
                      if (displayStatus == AppointmentStatus.pending &&
                          onConfirm != null)
                        _ModernActionBtn(
                          label: 'Confirm',
                          icon: Icons.check_circle_rounded,
                          color: AppColors.primary,
                          onTap: onConfirm!,
                          isPrimary: true,
                        )
                      else
                        _ModernActionBtn(
                          label: 'Mark Completed',
                          icon: Icons.check_circle_rounded,
                          color: AppColors.success,
                          onTap: onComplete,
                          isPrimary: true,
                        ),
                    ],
                  ),
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms, delay: (index * 80).ms)
        .slideY(begin: 0.05, end: 0);
  }

  /// Payment line between the info grid and the action buttons: amount +
  /// status chip, plus Mark Paid / Refund actions when the row is an
  /// OFFLINE Pending payment the clinic can settle.
  Widget _buildPaymentRow(PaymentModel p) {
    final color = p.paymentStatus == 'Paid'
        ? AppColors.success
        : p.paymentStatus == 'Refunded'
        ? AppColors.info
        : p.paymentStatus == 'Failed'
        ? AppColors.error
        : AppColors.warning;
    final actionable = onMarkPaid != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 15,
                color: AppColors.textHeading,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Payment \u00b7 ${p.amountLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHeading,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withAlpha(16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withAlpha(60), width: 0.8),
                ),
                child: Text(
                  p.paymentStatus,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (actionable) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _ModernActionBtn(
                  label: 'Mark Paid',
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  onTap: onMarkPaid!,
                  isPrimary: true,
                ),
                _ModernActionBtn(
                  label: 'Refund',
                  icon: Icons.currency_rupee_rounded,
                  color: AppColors.info,
                  onTap: onRefund!,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

const String kCompleteWithoutPrescription = '__complete_without_prescription__';

class PrescriptionUploadDialog extends StatefulWidget {
  final Future<String?> Function() upload;

  const PrescriptionUploadDialog({super.key, required this.upload});

  @override
  State<PrescriptionUploadDialog> createState() =>
      _PrescriptionUploadDialogState();
}

class _PrescriptionUploadDialogState extends State<PrescriptionUploadDialog> {
  bool _uploading = true;

  @override
  void initState() {
    super.initState();
    _runUpload();
  }

  Future<void> _runUpload() async {
    String? url;
    try {
      url = await widget.upload();
    } catch (_) {
      url = null;
    }
    if (!mounted) return;
    if (url != null && url.isNotEmpty) {
      Get.back(result: url);
      return;
    }
    setState(() => _uploading = false);
  }

  void _retry() {
    setState(() => _uploading = true);
    _runUpload();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.bgCard,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _uploading ? _buildProgress() : _buildError(),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Column(
      key: const ValueKey('upload_progress'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Uploading prescription…',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textHeading,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Please wait a moment',
          style: TextStyle(fontSize: 12.5, color: AppColors.textCaption),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _popCancel,
          child: Text('Cancel', style: TextStyle(color: AppColors.textCaption)),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      key: const ValueKey('upload_error'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.error.withAlpha(16),
          ),
          child: const Icon(
            Icons.cloud_off_rounded,
            size: 28,
            color: AppColors.error,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Upload failed',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textHeading,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Could not upload the prescription.\nPlease check your connection and try again.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: AppColors.textCaption,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Get.back(result: kCompleteWithoutPrescription),
          child: const Text(
            'Complete without Prescription',
            style: TextStyle(fontSize: 13, color: AppColors.textCaption),
          ),
        ),
      ],
    );
  }

  void _popCancel() {
    Get.back();
  }
}

class _ModernActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ModernActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPrimary ? color : color.withAlpha(15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isPrimary ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isPrimary ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
