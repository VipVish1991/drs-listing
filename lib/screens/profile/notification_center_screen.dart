import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/notification_center_controller.dart';
import '../../models/notification_item.dart';
import '../../routes/app_routes.dart';

/// In-app notification center: the full history of push notifications the
/// user has received (stored server-side by the notifications Edge
/// Function). Tapping a row marks it read and deep-links to the relevant
/// screen (doctor dashboard for bookings/cancellations, appointment history
/// for status updates).
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  late final NotificationCenterController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NotificationCenterController.instance;
    _controller.load();
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }

  (IconData, Color) _visualsFor(NotificationItem n) {
    switch (n.type) {
      case 'appointment_booked':
        return (Icons.event_available_rounded, AppColors.success);
      case 'appointment_cancelled':
        return (Icons.event_busy_rounded, AppColors.error);
      case 'appointment_rescheduled':
        return (Icons.event_repeat_rounded, AppColors.accent);
      case 'appointment_rescheduled_by_doctor':
        return (Icons.event_repeat_rounded, AppColors.accent);
      case 'appointment_status_changed':
        return (Icons.update_rounded, AppColors.info);
      default:
        return (Icons.notifications_rounded, AppColors.primary);
    }
  }

  void _onTap(NotificationItem item) {
    _controller.markRead(item);
    // Bookings/cancellations go to the doctor's dashboard; status updates
    // belong to the patient's appointment history. Guard by role so a
    // patient can never be pushed into the doctor dashboard, and only send
    // doctors there when a clinic is already loaded (the route falls back
    // to the current doctor, which is null on a fresh open).
    final isDoctor = Get.find<AuthController>().currentUser.value?.isDoctor ??
        false;
    if (isDoctor && item.isDoctorEvent) {
      Get.toNamed(AppRoutes.doctorDashboard);
    } else {
      Get.toNamed(AppRoutes.appointmentHistory);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            _buildGradientHeader(),

            Expanded(
              child: Obx(() {
                if (_controller.isLoading.value && _controller.items.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  );
                }
                if (_controller.items.isEmpty) {
                  return _buildEmptyState();
                }
                return RefreshIndicator(
                  onRefresh: _controller.load,
                  color: AppColors.primary,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    itemCount: _controller.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _controller.items[index];
                      return _buildNotificationCard(item);
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
            color: AppColors.primary.withAlpha(80),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your alerts & updates',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
          // Mark all as read — only when there is something unread.
          Obx(() {
            if (_controller.unreadCount.value == 0) {
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(20),
                ),
                child: const Icon(
                  Icons.done_all_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
              );
            }
            return GestureDetector(
              onTap: _controller.markAllRead,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withAlpha(40)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.done_all_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Mark all read',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildNotificationCard(NotificationItem item) {
    final (icon, color) = _visualsFor(item);
    return Material(
      color: item.read ? AppColors.bgCard : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onTap(item),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.read
                  ? Colors.transparent
                  : color.withAlpha(70),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(item.read ? 4 : 10),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: color.withAlpha(22),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              // Title + body
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: item.read
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: AppColors.textHeading,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeTime(item.createdAt),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textCaption,
                          ),
                        ),
                      ],
                    ),
                    if (item.body != null && item.body!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.body!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textBody,
                          height: 1.4,
                        ),
                      ),
                    ],
                    // ── Doctor + destination hint ──
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (item.doctorName != null)
                          _buildHintChip(
                            icon: Icons.local_hospital_rounded,
                            label: item.doctorName!,
                            color: AppColors.primary,
                          ),
                        _buildHintChip(
                          icon: Icons.north_east_rounded,
                          label: item.destinationLabel,
                          color: item.isDoctorEvent
                              ? AppColors.success
                              : AppColors.info,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Unread dot
              if (!item.read)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHintChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
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
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withAlpha(14),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textHeading,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Appointment alerts will show up here — bookings, '
              'cancellations and status updates.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textCaption,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
