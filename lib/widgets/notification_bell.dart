import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/notification_center_controller.dart';
import '../routes/app_routes.dart';

/// Bell icon with a live unread badge (the count of unread rows in the
/// in-app notification center). Tapping it opens the notification center.
///
/// Used on the patient home screen (theme-aware colors) and the doctor
/// dashboard header (white-on-gradient colors) — the colors are passed in
/// so each surface keeps its own look while the badge + navigation logic
/// stays in one place.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    this.badgeBorderColor,
    this.onTap,
  });

  /// Circle background behind the bell icon.
  final Color backgroundColor;

  /// Ring around the circle.
  final Color borderColor;

  /// Bell icon color.
  final Color iconColor;

  /// Border around the red unread badge (defaults to white — matches the
  /// light theme; pass e.g. `Color(0xFF15151F)` on dark surfaces).
  final Color? badgeBorderColor;

  /// Replaces the default "open notification center" behavior.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final notifications = NotificationCenterController.instance;
    return GestureDetector(
      key: const ValueKey('notification_bell'),
      onTap: onTap ?? () => Get.toNamed(AppRoutes.notificationCenter),
      child: Obx(() {
        final unread = notifications.unreadCount.value;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: backgroundColor,
                border: Border.all(color: borderColor),
              ),
              child: Icon(
                Icons.notifications_rounded,
                size: 22,
                color: iconColor,
              ),
            ),
            if (unread > 0)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: badgeBorderColor ?? Colors.white,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}
