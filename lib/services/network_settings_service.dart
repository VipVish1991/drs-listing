import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the system Wi‑Fi / network settings page so the user can
/// re-enable their internet connection without leaving the app entirely.
///
/// * **Android** — the native handler in `MainActivity.kt` (channel
///   `drslisting/network_settings`) launches `Settings.ACTION_WIFI_SETTINGS`.
/// * **iOS** — there is no public API to deep-link into Settings > Wi‑Fi
///   (`UIApplication.openSettingsURLString` only opens the app's own
///   settings page). The closest available option is the
///   `App-Prefs:root=WIFI` URL scheme, which Settings has handled for
///   years; the scheme is declared in `ios/Runner/Info.plist`
///   (`LSApplicationQueriesSchemes`) so `canLaunchUrl` accepts it. Apple
///   doesn't guarantee the scheme, so any rejection is silently ignored —
///   the offline banner stays and the user can reach Wi‑Fi settings
///   manually.
/// * **Other platforms** — no-op.
class NetworkSettingsService {
  NetworkSettingsService._();

  static const MethodChannel _channel =
      MethodChannel('drslisting/network_settings');

  /// iOS Settings > Wi‑Fi deep link. Only meaningful on iOS; the
  /// `App-Prefs` scheme must be declared in `LSApplicationQueriesSchemes`.
  static final Uri _iosWifiSettingsUri =
      Uri(scheme: 'App-Prefs', path: 'root=WIFI');

  /// Opens the system Wi‑Fi / network settings page on Android and iOS.
  /// No-op on other platforms and whenever the platform refuses to open it.
  static Future<void> openWifiSettings() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _openIosWifiSettings();
      return;
    }
    try {
      await _channel.invokeMethod('openWifiSettings');
    } catch (_) {
      // Platform not supported / plugin unavailable — ignore.
    }
  }

  /// Opens Settings > Wi‑Fi via the `App-Prefs:root=WIFI` URL scheme.
  ///
  /// `canLaunchUrl` is consulted first; when it reports false the deep link
  /// is skipped (the system rejects it on this iOS version). If
  /// `canLaunchUrl` itself throws, a direct launch is still attempted so a
  /// false negative never blocks the (best-effort) open. Every failure is
  /// swallowed — this is a convenience, never a hard requirement.
  static Future<void> _openIosWifiSettings() async {
    var launch = false;
    try {
      launch = await canLaunchUrl(_iosWifiSettingsUri);
    } catch (_) {
      // canLaunchUrl failed — don't trust it, let the direct attempt decide.
      launch = true;
    }
    if (launch) {
      try {
        await launchUrl(_iosWifiSettingsUri,
            mode: LaunchMode.externalApplication);
      } catch (_) {
        // Settings rejected the deep link — silent no-op.
      }
    }
  }
}
