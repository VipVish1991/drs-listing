import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../models/appointment_model.dart';

/// Confirmation dialog shown before opening the reschedule screen when the
/// appointment is still **Pending** (awaiting clinic confirmation).
///
/// A Pending booking hasn't been confirmed by the clinic yet, so moving it
/// to a new slot deserves an explicit acknowledgement — the clinic may have
/// already seen the request and planned around it. Callers only invoke this
/// for Pending rows; every other status navigates to the reschedule screen
/// directly.
///
/// [initiatedByDoctor] switches the copy for the doctor's patient-history
/// sheet (the clinic moving an unconfirmed request). Returns `true` only
/// when the user confirms they still want to reschedule (the dialog's
/// Reschedule button); `false`/`null` for the cancel button or barrier
/// dismiss.
Future<bool> showPendingRescheduleConfirm({
  bool initiatedByDoctor = false,
}) async {
  final proceed = await Get.dialog<bool>(
    Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppColors.bgCard,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withAlpha(18),
                  ),
                  child: const Icon(
                    Icons.pending_actions_rounded,
                    color: AppColors.accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Reschedule pending appointment?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHeading,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              initiatedByDoctor
                  ? 'This appointment is still pending confirmation. '
                        'Move it to a new slot anyway?'
                  : 'This appointment hasn\'t been confirmed by the clinic '
                        'yet. Would you still like to reschedule it?',
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textBody,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('pending_reschedule_confirm_cancel'),
                  onPressed: () => Get.back(result: false),
                  child: const Text('Keep appointment'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const ValueKey('pending_reschedule_confirm_proceed'),
                  onPressed: () => Get.back(result: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Reschedule'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    barrierDismissible: true,
  );
  return proceed ?? false;
}

/// The single gate every reschedule entry point uses before navigating:
/// Pending (unconfirmed) appointments require the confirmation dialog, every
/// other status calls [onProceed] immediately.
///
/// Used by the patient card chip, the patient details-sheet action and the
/// doctor's patient-history sheet action, so the rule can never drift
/// between entry points. [onProceed] performs the actual navigation
/// (Get.toNamed to the reschedule screen).
Future<void> confirmIfPendingReschedule(
  AppointmentModel appointment, {
  required bool initiatedByDoctor,
  required VoidCallback onProceed,
}) async {
  if (appointment.status != AppointmentStatus.pending) {
    onProceed();
    return;
  }
  final proceed = await showPendingRescheduleConfirm(
    initiatedByDoctor: initiatedByDoctor,
  );
  if (proceed) onProceed();
}
