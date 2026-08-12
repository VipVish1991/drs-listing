import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import '../config/theme.dart';

/// Safe GPS-service probe — the platform plugin throws MissingPluginException
/// on bare test bindings / unsupported platforms, and can hang in widget
/// tests, so both cases resolve to `false` (GPS off) instead of blocking.
Future<bool> _gpsEnabledSafe() async {
  try {
    return await Geolocator.isLocationServiceEnabled().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
  } catch (_) {
    return false;
  }
}

/// Shared **GPS gate** for every location-dependent action on both the
/// patient side (quick-chip search, pull-to-refresh, manual location
/// request) and the doctor side (nearby healthcare places): probes the GPS
/// service and, when it's off, shows the [showGpsOffDialog] alert (with an
/// Open-Settings action) and blocks the caller until the user enables it.
/// Returns `true` when GPS is on by the time the call completes.
///
/// A broken/unavailable platform probe (bare test bindings, desktop,
/// missing plugin) never blocks the action — it resolves to `true` so the
/// caller proceeds. Pass [gpsCheck] to inject a fake probe (tests) — the
/// same probe is then reused for the dialog's "check again" button so a
/// mutable value can simulate the user turning GPS on mid-flow.
Future<bool> ensureGpsEnabled({Future<bool> Function()? gpsCheck}) async {
  // Gate-time probe: the raw platform call so an unavailable plugin throws
  // and the catch below lets the action proceed (tests, desktop). The
  // dialog's check-again probe is the safe wrapper so that button can
  // never throw either — unless the caller supplied an explicit probe.
  final probe = gpsCheck ?? Geolocator.isLocationServiceEnabled;
  try {
    // Timeout so a hung platform probe can never block the action forever.
    final enabled = await probe().timeout(const Duration(seconds: 5));
    if (enabled) return true;
  } catch (_) {
    // Geolocator unavailable / unresponsive (tests, desktop) — never
    // block the action.
    return true;
  }
  return showGpsOffDialog(gpsCheck: gpsCheck ?? _gpsEnabledSafe);
}

/// Shows a **"GPS is Off"** alert and blocks until the user either opens
/// location settings or confirms GPS is now enabled.
///
/// Used as a gate before location-dependent actions (quick-chip doctor
/// search, pull-to-refresh, manual location request) so the user is always
/// told exactly why the action can't run and how to fix it.
///
/// With [dismissible] the alert is a gentle prompt instead of a trap: a
/// **"Not now"** button (and barrier tap) lets the user keep browsing —
/// used by the patient home page's automatic GPS-off popup so it never
/// locks the user out of the app. The prompt still returns `true` when GPS
/// is enabled by the time it closes.
///
/// Returns `true` when GPS is enabled by the time the dialog closes.
Future<bool> showGpsOffDialog({
  Future<bool> Function()? gpsCheck,
  bool dismissible = false,
}) async {
  final probe = gpsCheck ?? _gpsEnabledSafe;
  var enabled = false;

  await Get.dialog(
    PopScope(
      canPop: dismissible,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.gps_fixed, color: AppColors.primary, size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'GPS is Off',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Location services are turned off. DrsListing needs your '
              'GPS enabled to find nearby doctors, hospitals, and '
              'healthcare providers for you.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withAlpha(80)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Turn on GPS / Location Services from your device '
                      'settings, then come back and tap “check again”.',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  await Geolocator.openLocationSettings();
                } catch (_) {
                  // Unsupported platform — the check-again button below
                  // still lets the user proceed.
                }
              },
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Open Location Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () async {
                if (await probe()) {
                  enabled = true;
                  Get.back();
                }
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("I've enabled GPS — check again"),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (dismissible) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Get.back(),
                child: const Text(
                  'Not now',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textCaption,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    barrierDismissible: dismissible,
  );

  return enabled;
}
