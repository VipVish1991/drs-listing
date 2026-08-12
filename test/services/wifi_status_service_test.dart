import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/services/wifi_status_service.dart';

void main() {
  group('WifiStatus.fromJson', () {
    test('parses a full native response', () {
      final status = WifiStatus.fromJson(const {
        'wifiEnabled': true,
        'connected': true,
        'ssid': 'CaféWiFi',
        'rssi': -57,
        'signalLevel': 3,
        'linkSpeedMbps': 130,
        'frequencyMhz': 5180,
        'locationGranted': true,
      });

      expect(status.wifiEnabled, isTrue);
      expect(status.connected, isTrue);
      expect(status.ssid, 'CaféWiFi');
      expect(status.rssi, -57);
      expect(status.signalLevel, 3);
      expect(status.linkSpeedMbps, 130);
      expect(status.frequencyMhz, 5180);
      expect(status.locationGranted, isTrue);
      expect(status.hasSsid, isTrue);
    });

    test('handles the Wi-Fi-off / not-connected state', () {
      final off = WifiStatus.fromJson(const {
        'wifiEnabled': false,
        'connected': false,
        'ssid': null,
        'rssi': null,
        'signalLevel': null,
        'linkSpeedMbps': null,
        'frequencyMhz': null,
        'locationGranted': true,
      });

      expect(off.wifiEnabled, isFalse);
      expect(off.connected, isFalse);
      expect(off.ssid, isNull);
      expect(off.signalLevel, isNull);
      expect(off.hasSsid, isFalse);
    });

    test('defaults safely when keys are missing or malformed', () {
      final status = WifiStatus.fromJson(const <dynamic, dynamic>{
        'connected': 1, // truthy-but-not-bool → not a == true
        'rssi': 'not-a-number', // non-num → null
      });

      expect(status.wifiEnabled, isFalse);
      expect(status.connected, isFalse);
      expect(status.rssi, isNull);
      expect(status.signalLevel, isNull);
      expect(status.linkSpeedMbps, isNull);
      expect(status.frequencyMhz, isNull);
      expect(status.locationGranted, isFalse);
      expect(status.safeSignalLevel, 0);
    });

    test('coerces num rssi/level values to int', () {
      final status = WifiStatus.fromJson(const {
        'wifiEnabled': true,
        'connected': true,
        'rssi': -61.0,
        'signalLevel': 2.0,
        'locationGranted': true,
      });

      expect(status.rssi, -61);
      expect(status.signalLevel, 2);
    });
  });

  group('WifiStatus.safeSignalLevel', () {
    test('clamps negative / out-of-range levels into 0..4', () {
      expect(const WifiStatus(
        wifiEnabled: true,
        connected: true,
        signalLevel: 7,
        locationGranted: true,
      ).safeSignalLevel, 4);

      expect(const WifiStatus(
        wifiEnabled: true,
        connected: true,
        signalLevel: -3,
        locationGranted: true,
      ).safeSignalLevel, 0);

      // Null level (not connected) reads as the weakest bar.
      expect(const WifiStatus(
        wifiEnabled: false,
        connected: false,
        locationGranted: true,
      ).safeSignalLevel, 0);
    });
  });
}
