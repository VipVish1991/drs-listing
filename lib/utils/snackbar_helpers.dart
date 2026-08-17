import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../config/theme.dart';

/// Shows a consistent error snackbar with [message].
/// Safe to call in test environments — silently returns if no overlay
/// context is available.
void showErrorSnackbar(String message) {
  if (Get.context == null) return;
  Get.snackbar(
    'Error',
    message,
    backgroundColor: AppColors.error,
    colorText: AppColors.textWhite,
  );
}

/// Shows a top snackbar with the server-minted OTP code for DEMO/testing
/// — the code would normally arrive by SMS, but in demo mode the server
/// returns it so the app can display it. Safe in tests (no-op without an
/// overlay context).
void showDemoOtpToast(String code) {
  if (Get.context == null) return;
  Get.snackbar(
    'Verification code',
    'Your 4-digit OTP: $code',
    backgroundColor: AppColors.success,
    colorText: AppColors.textWhite,
    duration: const Duration(seconds: 6),
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    borderRadius: 14,
  );
}

/// Shows a neutral info snackbar with [message].
/// Safe to call in test environments — silently returns if no overlay
/// context is available.
void showInfoSnackbar(String message) {
  if (Get.context == null) return;
  Get.snackbar(
    'Info',
    message,
    backgroundColor: AppColors.info,
    colorText: AppColors.textWhite,
    duration: const Duration(seconds: 4),
  );
}

/// Shows a consistent success snackbar with [message].
/// Safe to call in test environments — silently returns if no overlay
/// context is available.
void showSuccessSnackbar(String message) {
  if (Get.context == null) return;
  Get.snackbar(
    'Success',
    message,
    backgroundColor: AppColors.success,
    colorText: AppColors.textWhite,
  );
}
