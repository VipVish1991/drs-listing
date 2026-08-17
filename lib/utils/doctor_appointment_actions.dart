import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../config/theme.dart';
import '../controllers/doctor_controller.dart';
import '../models/appointment_model.dart';
import '../services/supabase_service.dart';
import '../utils/image_optimizer.dart';
import '../utils/snackbar_helpers.dart';
import '../widgets/image_processing_dialog.dart';

/// Marker result from [PrescriptionUploadDialog]: the doctor chose to
/// complete the appointment WITHOUT uploading a prescription photo.
const String kCompleteWithoutPrescription = '__complete_without_prescription__';

/// Shows the "Cancel Appointment" confirm dialog for a doctor-side cancel
/// ([DoctorController.updateAppointmentStatus] with 'Cancelled'). Shared by
/// the Appointments tab cards, the appointment-details sheet and the
/// patient-history sheet so every entry point asks the same question.
///
/// Returns `true` when the doctor confirmed the cancel — the details sheet
/// uses that to close itself right after the action lands.
Future<bool?> showCancelAppointmentDialog(
  DoctorController controller,
  AppointmentModel a,
) {
  return Get.dialog<bool>(
    AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Cancel Appointment'),
      content: Text('Cancel appointment with ${a.patientName ?? 'patient'}?'),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: Text('Keep', style: TextStyle(color: AppColors.textCaption)),
        ),
        ElevatedButton(
          onPressed: () {
            controller.updateAppointmentStatus(a.appointmentId, 'Cancelled');
            Get.back(result: true);
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

/// Shows the "Complete Appointment" dialog: camera / gallery prescription
/// upload, or "Complete without Prescription" as a fallback. Shared by the
/// Appointments tab cards, the appointment-details sheet and the
/// patient-history sheet.
///
/// Returns `true` as soon as the doctor proceeds with ANY option (the
/// upload flow, when chosen, keeps running asynchronously afterwards) —
/// the details sheet uses that to close itself right away.
Future<bool?> showCompleteAppointmentDialog(
  DoctorController controller,
  AppointmentModel a,
) {
  // Every consultation type (In-Clinic included) offers the camera
  // prescription upload when the doctor marks the appointment complete;
  // "Choose from Gallery" picks an existing photo instead, and
  // "Complete without Prescription" stays available as a fallback.
  return Get.dialog<bool>(
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
              height: 48,                child: ElevatedButton.icon(
                  onPressed: () {
                    Get.back(result: true);
                    startPrescriptionUpload(controller, a, source: ImageSource.camera);
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
              height: 48,                child: OutlinedButton.icon(
                  onPressed: () {
                    Get.back(result: true);
                    startPrescriptionUpload(controller, a, source: ImageSource.gallery);
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
              height: 48,                child: OutlinedButton(
                  onPressed: () {
                    Get.back(result: true);
                    controller.updateAppointmentStatus(
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
///
/// All overlays are Get-based (dialogs / bottom sheets live on the
/// navigator, not on any screen's State), so this can be called from any
/// doctor surface — the Appointments tab cards, the details sheet or the
/// patient-history sheet.
Future<void> startPrescriptionUpload(
  DoctorController controller,
  AppointmentModel a, {
  ImageSource source = ImageSource.camera,
}) async {
  final doctorPlaceId =
      controller.currentDoctor.value?.placeId ??
      (a.doctorDetails?['place_id']?.toString() ?? '');
  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 3000,
      imageQuality: 85,
    );
    if (picked == null) return;

    // Feedback between the photo capture/pick and the preview sheet: the
    // decode + 9:16 portrait padding + downscale (compute isolate) can
    // take a moment on large photos, so show the processing dialog
    // before it instead of leaving a dead pause.
    ImageProcessingDialog.show();

    final bytes = await picked.readAsBytes();

    final uploadBytes =
        (await compute(PrescriptionImageOptimizer.optimizePortrait, bytes)) ??
        bytes;

    // Processing done — dismiss the loading dialog (it lives on the
    // navigator, not on any widget) before opening the preview sheet.
    if (Get.isDialogOpen ?? false) Get.back();

    final shouldUpload = await showPrescriptionPreview(a, uploadBytes);
    if (shouldUpload != true) return;

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

    if (result == kCompleteWithoutPrescription) {
      await controller.updateAppointmentStatus(a.appointmentId, 'Completed');
      showErrorSnackbar(
        'Appointment completed, but the prescription upload failed',
      );
    } else if (result != null && result.isNotEmpty) {
      await controller.completeAppointmentWithPrescription(a.appointmentId, [
        result,
      ]);
      showSuccessSnackbar('Appointment completed & prescription uploaded');
    }
  } catch (_) {
    // Close any open overlay (processing dialog / preview sheet) even if
    // the calling screen unmounted meanwhile — dialogs live on the
    // navigator, not on a widget, so they must not leak.
    Get.back();
    showErrorSnackbar(
      source == ImageSource.gallery
          ? 'Could not open the gallery. Please try again.'
          : 'Could not open the camera. Please try again.',
    );
  }
}

/// Full-height 9:16 preview sheet showing the COMPLETE prescription page
/// (the upload bytes are padded to a 9:16 white canvas by
/// [PrescriptionImageOptimizer]). Returns `true` when the doctor confirms
/// the upload, `false` on retake / dismiss.
Future<bool?> showPrescriptionPreview(AppointmentModel a, Uint8List bytes) {
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

/// Upload-progress dialog with retry / cancel, plus the
/// "Complete without Prescription" escape hatch when the upload keeps
/// failing. Returns the uploaded URL, [kCompleteWithoutPrescription], or
/// null when cancelled.
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
