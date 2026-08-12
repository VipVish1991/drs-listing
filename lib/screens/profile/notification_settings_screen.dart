import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../controllers/notification_settings_controller.dart';

/// Lets the user toggle which push alerts they receive. The five switches
/// map to the notifications Edge Function's event names; the function
/// enforces them server-side against the user's own row, so the choice
/// follows the account across every device.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late final NotificationSettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.isRegistered<NotificationSettingsController>()
        ? Get.find<NotificationSettingsController>()
        : Get.put(NotificationSettingsController());
    _controller.loadPrefs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGradientHeader(),

              const SizedBox(height: 24),

              // ── Push Alerts ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(6),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section header
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.notifications_active_rounded,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Push Alerts',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textHeading,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Text(
                          'Choose which notifications you receive',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textCaption.withAlpha(180),
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFECEEF2)),

                      // Toggles (loading spinner while prefs load)
                      Obx(() {
                        if (_controller.isLoading.value) {
                          return const Padding(
                            padding: EdgeInsets.all(28),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        }
                        // While the master switch is off, the individual
                        // event toggles are disabled and shown off — their
                        // underlying values are preserved so turning the
                        // master back on restores the user's choices.
                        final allEnabled = _controller.allEnabled;
                        return Column(
                          children: [
                            // ── Master switch ──
                            _buildToggleTile(
                              icon: allEnabled
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_off_rounded,
                              color: AppColors.primary,
                              title: 'All Notifications',
                              subtitle: allEnabled
                                  ? 'All alerts are ON — tap to mute '
                                      'everything at once'
                                  : 'All alerts are OFF — tap to restore '
                                      'your preferences',
                              value: allEnabled,
                              onChanged: (v) => _controller.setPref(
                                NotificationSettingsController.eventAll,
                                v,
                              ),
                              emphasized: true,
                            ),
                            const Divider(
                              height: 1,
                              indent: 68,
                              color: Color(0xFFECEEF2),
                            ),
                            // ── Individual events (disabled when muted) ──
                            Obx(() {
                              final booked = _controller.prefs[
                                NotificationSettingsController.eventBooked
                              ] ??
                              true;
                              return _buildToggleTile(
                                icon: Icons.event_available_rounded,
                                color: AppColors.primary,
                                title: 'New Bookings',
                                subtitle:
                                    'When a patient books an appointment '
                                    'with you',
                                value: allEnabled ? booked : false,
                                onChanged: allEnabled
                                    ? (v) => _controller.setPref(
                                        NotificationSettingsController
                                            .eventBooked,
                                        v,
                                      )
                                    : null,
                              );
                            }),
                            const Divider(
                              height: 1,
                              indent: 68,
                              color: Color(0xFFECEEF2),
                            ),
                            Obx(() {
                              final cancelled = _controller.prefs[
                                NotificationSettingsController.eventCancelled
                              ] ??
                              true;
                              return _buildToggleTile(
                                icon: Icons.event_busy_rounded,
                                color: AppColors.error,
                                title: 'Cancellations',
                                subtitle: 'When an appointment is cancelled',
                                value: allEnabled ? cancelled : false,
                                onChanged: allEnabled
                                    ? (v) => _controller.setPref(
                                        NotificationSettingsController
                                            .eventCancelled,
                                        v,
                                      )
                                    : null,
                              );
                            }),
                            const Divider(
                              height: 1,
                              indent: 68,
                              color: Color(0xFFECEEF2),
                            ),
                            Obx(() {
                              final rescheduled = _controller.prefs[
                                NotificationSettingsController
                                    .eventRescheduled
                              ] ??
                              true;
                              return _buildToggleTile(
                                icon: Icons.event_repeat_rounded,
                                color: AppColors.accent,
                                title: 'Reschedules',
                                subtitle:
                                    'When a patient moves an appointment '
                                    'to a different slot',
                                value: allEnabled ? rescheduled : false,
                                onChanged: allEnabled
                                    ? (v) => _controller.setPref(
                                        NotificationSettingsController
                                            .eventRescheduled,
                                        v,
                                      )
                                    : null,
                              );
                            }),
                            const Divider(
                              height: 1,
                              indent: 68,
                              color: Color(0xFFECEEF2),
                            ),
                            // ── Clinic-initiated reschedules (patient
                            //    recipient — distinct from the patient-→doctor
                            //    Reschedules toggle above, so the patient can
                            //    mute either direction independently). ──
                            Obx(() {
                              final byDoctor = _controller.prefs[
                                NotificationSettingsController
                                    .eventRescheduledByDoctor
                              ] ??
                              true;
                              return _buildToggleTile(
                                icon: Icons.event_repeat_rounded,
                                color: AppColors.info,
                                title: 'Clinic Reschedules',
                                subtitle:
                                    'When the clinic moves your appointment '
                                    'to a different slot',
                                value: allEnabled ? byDoctor : false,
                                onChanged: allEnabled
                                    ? (v) => _controller.setPref(
                                        NotificationSettingsController
                                            .eventRescheduledByDoctor,
                                        v,
                                      )
                                    : null,
                              );
                            }),
                            const Divider(
                              height: 1,
                              indent: 68,
                              color: Color(0xFFECEEF2),
                            ),
                            Obx(() {
                              final statusChanged = _controller.prefs[
                                NotificationSettingsController.eventStatusChanged
                              ] ??
                              true;
                              return _buildToggleTile(
                                icon: Icons.update_rounded,
                                color: AppColors.info,
                                title: 'Status Updates',
                                subtitle:
                                    'When your appointment status changes '
                                    '(confirmed, completed, cancelled)',
                                value: allEnabled ? statusChanged : false,
                                onChanged: allEnabled
                                    ? (v) => _controller.setPref(
                                        NotificationSettingsController
                                            .eventStatusChanged,
                                        v,
                                      )
                                    : null,
                              );
                            }),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

              const SizedBox(height: 16),

              // ── Info note ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withAlpha(60),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'These preferences apply to your account on all '
                          'devices. You can also manage notification access '
                          'for the app in your device settings.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textBody,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

              const SizedBox(height: 40),
            ],
          ),
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
          const Column(
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
                'Manage your push alerts',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildToggleTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool emphasized = false,
  }) {
    final enabled = onChanged != null;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      activeThumbColor: AppColors.primary,
      activeTrackColor: AppColors.primary.withAlpha(60),
      secondary: Container(
        width: emphasized ? 48 : 42,
        height: emphasized ? 48 : 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(emphasized ? 14 : 12),
          color: color.withAlpha(enabled ? 25 : 12),
        ),
        child: Icon(
          icon,
          color: enabled ? color : AppColors.textCaption.withAlpha(120),
          size: emphasized ? 24 : 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: emphasized ? 16 : 15,
          fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
          color: enabled
              ? AppColors.textHeading
              : AppColors.textCaption.withAlpha(150),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12.5,
          color: AppColors.textCaption.withAlpha(enabled ? 180 : 120),
          height: 1.35,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
