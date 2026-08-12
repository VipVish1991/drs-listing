import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Snapshot of the device's Wi-Fi state, reported by the native side
/// (`MainActivity.kt`, channel `drslisting/wifi_info`).
///
/// [ssid] and the signal fields are only meaningful when [connected] is
/// true; [ssid] additionally requires location permission on Android
/// 8.1+ (see [locationGranted]).
class WifiStatus {
  /// Whether the Wi-Fi radio is turned on at all.
  final bool wifiEnabled;

  /// Whether the device is currently associated with an access point.
  final bool connected;

  /// The connected network's name (SSID), or null when unknown / not
  /// connected / location permission missing.
  final String? ssid;

  /// Signal strength in dBm (typically between -40 and -90), or null when
  /// not connected.
  final int? rssi;

  /// Signal strength as 0..4 bars (0 = weakest), or null when not connected.
  final int? signalLevel;

  /// Connection speed in Mbps, or null when not connected.
  final int? linkSpeedMbps;

  /// Wi-Fi channel frequency in MHz, or null when not connected.
  final int? frequencyMhz;

  /// True when the app holds a location permission — required to read the
  /// SSID on Android 8.1+.
  final bool locationGranted;

  const WifiStatus({
    required this.wifiEnabled,
    required this.connected,
    this.ssid,
    this.rssi,
    this.signalLevel,
    this.linkSpeedMbps,
    this.frequencyMhz,
    required this.locationGranted,
  });

  /// Clamped 0..4 bar level — safe for the signal-bars UI even when the
  /// platform reports an out-of-range or null value.
  int get safeSignalLevel => (signalLevel ?? 0).clamp(0, 4);

  bool get hasSsid => ssid != null && ssid!.isNotEmpty;

  /// Builds a [WifiStatus] from the native map. Unknown/missing keys fall
  /// back to safe defaults so a partial response never crashes the UI.
  factory WifiStatus.fromJson(Map<dynamic, dynamic> json) {
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    return WifiStatus(
      wifiEnabled: json['wifiEnabled'] == true,
      connected: json['connected'] == true,
      ssid: json['ssid'] as String?,
      rssi: asInt(json['rssi']),
      signalLevel: asInt(json['signalLevel']),
      linkSpeedMbps: asInt(json['linkSpeedMbps']),
      frequencyMhz: asInt(json['frequencyMhz']),
      locationGranted: json['locationGranted'] == true,
    );
  }
}

/// Reads the connected Wi-Fi network details (name + signal strength) for
/// the home screen's offline connectivity status card.
///
/// The platform handler lives in `MainActivity.kt` (channel
/// `drslisting/wifi_info`) and only exists on Android — on every other
/// platform (including web and tests) [getWifiStatus] returns null so the
/// card simply shows its generic offline state.
class WifiStatusService {
  WifiStatusService._();

  static final WifiStatusService instance = WifiStatusService._();

  static const MethodChannel _channel = MethodChannel('drslisting/wifi_info');

  /// Reads the current Wi-Fi status, or null when unavailable (non-Android,
  /// platform error, no WifiManager).
  Future<WifiStatus?> getWifiStatus() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final raw =
          await _channel.invokeMapMethod<String, dynamic>('getWifiStatus');
      if (raw == null) return null;
      return WifiStatus.fromJson(raw);
    } catch (_) {
      // Channel missing / platform error — the card falls back to the
      // generic offline message.
      return null;
    }
  }
}
