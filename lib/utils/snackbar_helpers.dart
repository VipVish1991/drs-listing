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
