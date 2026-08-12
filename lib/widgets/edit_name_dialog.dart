import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';

/// Shows the shared "Edit Name" popup used by the patient profile header
/// and the doctor dashboard header.
///
/// [currentName] pre-fills the field. [onSave] persists the new name (e.g.
/// to Supabase) and must refresh whatever reactive state renders the
/// caller's header so it updates in place. The dialog stays open with an
/// error snackbar if [onSave] throws.
///
/// Returns `true` when the name was actually saved (dialog closed via Save),
/// `false` when dismissed without saving.
Future<bool> showEditNameDialog({
  required String currentName,
  required Future<void> Function(String name) onSave,
}) async {
  final nameController = TextEditingController(text: currentName);
  final formKey = GlobalKey<FormState>();
  var isSaving = false;
  var saved = false;

  await Get.dialog(
    StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> save() async {
          if (isSaving) return;
          if (!(formKey.currentState?.validate() ?? false)) return;
          setDialogState(() => isSaving = true);
          try {
            await onSave(nameController.text);
            saved = true;
            if (context.mounted) Get.back();
            Get.snackbar(
              'Name updated',
              'Your name has been saved successfully.',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: AppColors.primary,
              colorText: Colors.white,
              margin: const EdgeInsets.all(16),
              borderRadius: 12,
              duration: const Duration(seconds: 2),
            );
          } catch (_) {
            setDialogState(() => isSaving = false);
            Get.snackbar(
              'Could not update name',
              'Please check your connection and try again.',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: AppColors.error,
              colorText: Colors.white,
              margin: const EdgeInsets.all(16),
              borderRadius: 12,
              duration: const Duration(seconds: 3),
            );
          }
        }

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: AppColors.bgSurface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.badge_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Edit Name',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textHeading,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 60,
                    decoration: InputDecoration(
                      labelText: 'Full name',
                      hintText: 'Enter your name',
                      prefixIcon: const Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: AppColors.bgMain,
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: AppColors.primary.withAlpha(40),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return 'Please enter your name';
                      }
                      if (text.length < 2) {
                        return 'Name must be at least 2 characters';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => save(),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSaving ? null : () => Get.back(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textBody,
                            side: BorderSide(
                              color: AppColors.textDisabled.withAlpha(120),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSaving ? null : save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
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
        );
      },
    ),
  );
  // Note: the TextEditingController is intentionally NOT disposed here —
  // Get.dialog's future resolves as soon as the route pop starts, but the
  // dialog's exit transition still animates the TextFormField, which would
  // then read a disposed controller. It is a short-lived, per-open
  // controller, so it is simply garbage-collected.
  return saved;
}
