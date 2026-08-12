import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';

/// Non-dismissible "Processing Image…" loading shown between the camera
/// capture and the prescription preview sheet on the doctor side.
///
/// After the doctor takes the photo, the bytes must be decoded, padded to
/// the 9:16 portrait white canvas and downscaled (a `compute` isolate call)
/// before the preview can render — on large photos that takes a moment, so
/// this dialog gives instant feedback instead of a dead pause.
class ImageProcessingDialog extends StatelessWidget {
  const ImageProcessingDialog({super.key});

  /// Opens the dialog on the current navigator. Non-dismissible (the
  /// doctor can't tap away mid-processing); callers close it with
  /// `Get.back()` once the image is ready.
  static void show() {
    Get.dialog(
      const ImageProcessingDialog(),
      barrierDismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppColors.bgCard,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withAlpha(14),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Processing Image…',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textHeading,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enhancing quality & preparing the prescription',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textCaption),
            ),
          ],
        ),
      ),
    );
  }
}
