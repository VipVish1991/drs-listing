import 'dart:async';

import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../models/notification_item.dart';
import '../services/supabase_service.dart';

/// Powers the in-app notification center: loads the user's push-notification
/// history (the `notifications` table, written by the Edge Function whenever
/// it sends a push), tracks the unread count for badges, and marks rows read.
///
/// Loaded lazily by the screens that show a badge; [NotificationService]
/// calls [refresh] after a foreground push so the badge updates live.
class NotificationCenterController extends GetxController {
  static NotificationCenterController get instance =>
      Get.isRegistered<NotificationCenterController>()
          ? Get.find<NotificationCenterController>()
          : Get.put(NotificationCenterController());

  final SupabaseService _supabase = SupabaseService();

  final RxList<NotificationItem> items = <NotificationItem>[].obs;
  final RxBool isLoading = false.obs;

  /// Number of unread notifications — shown as a badge on the bell / menu.
  /// Reactive so any widget listening to it rebuilds when it changes.
  final RxInt unreadCount = 0.obs;

  late final StreamSubscription<List<NotificationItem>> _itemsSub;

  NotificationCenterController() {
    // Keep the badge in sync with the list no matter how it changes
    // (load, markRead, markAllRead, or a test pre-seeding the list).
    _itemsSub = items.listen((_) => _recomputeUnread());
  }

  @override
  void onClose() {
    _itemsSub.cancel();
    super.onClose();
  }

  /// Load the current user's notifications (newest first) and refresh the
  /// unread count. Non-fatal: offline / not logged in keeps the current list.
  Future<void> load() async {
    final user = Get.find<AuthController>().currentUser.value;
    if (user?.id == null) {
      unreadCount.value = 0;
      return;
    }
    isLoading.value = true;
    try {
      final rows = await _supabase.getNotifications(user!.id!);
      items.value = rows
          .map((r) => NotificationItem.fromJson(r))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _recomputeUnread();
    } catch (_) {
      // Non-fatal — keep whatever we already have.
    } finally {
      isLoading.value = false;
    }
  }

  /// Mark one notification as read (optimistic — the badge updates instantly,
  /// the server write is fire-and-forget).
  Future<void> markRead(NotificationItem item) async {
    final user = Get.find<AuthController>().currentUser.value;
    final userId = user?.id;
    if (userId == null || item.read) return;

    final index = items.indexWhere((n) => n.id == item.id);
    if (index == -1) return;
    items[index] = NotificationItem(
      id: item.id,
      type: item.type,
      title: item.title,
      body: item.body,
      data: item.data,
      read: true,
      createdAt: item.createdAt,
    );
    _recomputeUnread();
    try {
      await _supabase.markNotificationRead(userId, item.id);
    } catch (_) {
      // Non-fatal — the badge is cosmetic; a later refresh re-syncs.
    }
  }

  /// Mark the doctor's booking/cancellation notifications as read — the
  /// alerts tied to appointments the doctor sees when they open the app or
  /// view the appointments tab. Patient-scoped notifications (status
  /// changes) stay untouched, and already-read rows are skipped, so the
  /// server write only touches what actually changed.
  Future<void> markDoctorEventsRead() async {
    final user = Get.find<AuthController>().currentUser.value;
    final userId = user?.id;
    if (userId == null) return;

    var changed = false;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (!it.read && it.isDoctorEvent) {
        items[i] = NotificationItem(
          id: it.id,
          type: it.type,
          title: it.title,
          body: it.body,
          data: it.data,
          read: true,
          createdAt: it.createdAt,
        );
        changed = true;
      }
    }
    if (!changed) return;
    _recomputeUnread();
    try {
      await _supabase.markDoctorNotificationsRead(userId);
    } catch (_) {
      // Non-fatal — a later refresh re-syncs.
    }
  }

  /// Mark the notifications for ONE appointment as read — called when the
  /// doctor confirms / cancels / completes the booking from the dashboard,
  /// so the bell reflects the alert was seen and handled. Precise per
  /// appointment (unlike [markDoctorEventsRead], which clears all doctor
  /// events on tab view); other rows stay untouched.
  Future<void> markAppointmentRead(String appointmentId) async {
    final user = Get.find<AuthController>().currentUser.value;
    final userId = user?.id;
    if (userId == null || appointmentId.isEmpty) return;

    var changed = false;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (!it.read && it.appointmentId == appointmentId) {
        items[i] = NotificationItem(
          id: it.id,
          type: it.type,
          title: it.title,
          body: it.body,
          data: it.data,
          read: true,
          createdAt: it.createdAt,
        );
        changed = true;
      }
    }
    if (changed) _recomputeUnread();
    try {
      // Always sync the server rows for this appointment (idempotent —
      // scoped to read=false, so it's a no-op when nothing matches). This
      // also covers the case where the local list is stale and doesn't yet
      // hold the notification: the row still gets cleared server-side.
      await _supabase.markAppointmentNotificationsRead(userId, appointmentId);
    } catch (_) {
      // Non-fatal — a later refresh re-syncs.
    }
  }

  /// Mark every notification as read.
  Future<void> markAllRead() async {
    final user = Get.find<AuthController>().currentUser.value;
    final userId = user?.id;
    if (userId == null) return;
    if (unreadCount.value == 0) return;
    for (var i = 0; i < items.length; i++) {
      if (!items[i].read) {
        items[i] = NotificationItem(
          id: items[i].id,
          type: items[i].type,
          title: items[i].title,
          body: items[i].body,
          data: items[i].data,
          read: true,
          createdAt: items[i].createdAt,
        );
      }
    }
    _recomputeUnread();
    try {
      await _supabase.markAllNotificationsRead(userId);
    } catch (_) {
      // Non-fatal.
    }
  }

  void _recomputeUnread() {
    unreadCount.value = items.where((n) => !n.read).length;
  }
}
