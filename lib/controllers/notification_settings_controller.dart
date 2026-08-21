import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/auth_controller.dart';
import '../services/supabase_service.dart';

/// Push-notification preferences for the logged-in user.
///
/// The five toggles map 1:1 to the notifications Edge Function's event
/// names — the function enforces them server-side against the RECIPIENT's
/// users.notification_prefs, so this screen is the single place a user
/// controls which alerts their devices receive (across all devices).
/// Missing keys are fail-open (default ON), so a new event needs no DB
/// migration — the server and this controller both treat an absent key as
/// "send".
class NotificationSettingsController extends GetxController {
  /// Event names — must match the notifications Edge Function + the
  /// users.notification_prefs keys in the DB migration.
  static const String eventBooked = 'appointment_booked';
  static const String eventCancelled = 'appointment_cancelled';
  static const String eventRescheduled = 'appointment_rescheduled';
  static const String eventRescheduledByDoctor =
      'appointment_rescheduled_by_doctor';
  static const String eventStatusChanged = 'appointment_status_changed';
  static const String eventPaymentStatusChanged = 'payment_status_changed';

  /// Master-switch key: `all: false` disables EVERY event at once (checked
  /// first by the Edge Function). The per-event keys are preserved beneath
  /// it, so turning the master back on restores the granular choices.
  static const String eventAll = 'all';

  /// The toggles shown on the settings screen, in display order.
  static const List<String> eventKeys = [
    eventBooked,
    eventCancelled,
    eventRescheduled,
    eventRescheduledByDoctor,
    eventStatusChanged,
    eventPaymentStatusChanged,
  ];

  /// All persisted keys — the master switch plus the three events. Used for
  /// defaults and when loading saved prefs.
  static const List<String> allKeys = [
    eventAll,
    ...eventKeys,
  ];

  /// Whether the master switch is on (all alerts allowed). Missing key
  /// defaults to ON, matching the server's fail-open behaviour.
  bool get allEnabled => prefs[eventAll] ?? true;

  final SupabaseService _supabase = SupabaseService();

  final RxBool isLoading = false.obs;

  /// event name → enabled. Missing keys default to ON (server treats a
  /// missing key as "send" too, so the UI matches the server).
  final RxMap<String, bool> prefs = <String, bool>{
    for (final k in allKeys) k: true,
  }.obs;

  /// Load the user's saved preferences from the users table. Non-fatal: on
  /// any failure (offline, migration not applied, not logged in) the
  /// defaults stay — the server also treats missing prefs as "send".
  Future<void> loadPrefs() async {
    final auth = Get.find<AuthController>();
    final user = auth.currentUser.value;
    if (user?.id == null || user?.mobile == null) return;

    isLoading.value = true;
    try {
      final saved = await _supabase.getUserNotificationPrefs(
        user!.id!,
        user.mobile!,
      );
      if (saved != null) {
        prefs.assignAll({
          for (final k in allKeys) k: saved[k] as bool? ?? true,
        });
      }
    } catch (_) {
      // Non-fatal — defaults remain.
    } finally {
      isLoading.value = false;
    }
  }

  /// Serialises saves so a slow older write can never overwrite a newer one,
  /// and monotonically increasing version so a stale failure only reverts the
  /// latest toggle.
  int _saveVersion = 0;
  Future<void> _saveChain = Future.value();

  /// Toggle one event. Optimistic UI: the switch flips immediately, the save
  /// happens in the background, and a failed save reverts the toggle with a
  /// snackbar so the user always sees the true server state. Rapid toggles
  /// are queued in order; only the newest toggle reverts on failure.
  Future<void> setPref(String event, bool enabled) async {
    final previous = prefs[event] ?? true;
    final version = ++_saveVersion;
    prefs[event] = enabled;

    final auth = Get.find<AuthController>();
    final userId = auth.currentUser.value?.id;
    final mobile = auth.currentUser.value?.mobile;
    if (userId == null || (mobile ?? '').isEmpty) return;

    final snapshot = Map<String, bool>.from(prefs);
    final completer = Completer<void>();
    _saveChain = _saveChain.then((_) async {
      try {
        await _supabase.saveUserNotificationPrefs(userId, mobile!, snapshot);
      } catch (_) {
        // Save failed — revert ONLY if no newer toggle has happened since
        // (a newer save's snapshot already includes this event's value and
        // will overwrite the server next).
        if (version == _saveVersion) {
          prefs[event] = previous;
          if (Get.context != null) {
            Get.snackbar(
              'Could not save settings',
              'Please check your connection and try again.',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: AppColors.error,
              colorText: Colors.white,
            );
          }
        }
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }
}
