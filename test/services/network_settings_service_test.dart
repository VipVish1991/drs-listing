import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:DrsListing/services/network_settings_service.dart';

/// Records every canLaunch/launch request (mirrors the fake in
/// launch_service_test.dart) so the iOS URL-scheme path can be asserted.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> canLaunchCalls = [];
  final List<String> launchCalls = [];

  /// Returned by every [canLaunch] call.
  bool canLaunchResult = true;

  /// When true, [canLaunch] throws (some devices throw instead of
  /// answering) — the service must still attempt the direct launch.
  bool throwOnCanLaunch = false;

  /// When true, [launch] throws (Settings rejected the deep link).
  bool throwOnLaunch = false;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    canLaunchCalls.add(url);
    if (throwOnCanLaunch) throw Exception('canLaunch exploded');
    return canLaunchResult;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchCalls.add(url);
    if (throwOnLaunch) throw Exception('launch exploded');
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const androidChannel = MethodChannel('drslisting/network_settings');

  setUp(() {
    // Default platform in tests is Android — the channel path.
    debugDefaultTargetPlatformOverride = null;
    UrlLauncherPlatform.instance = _FakeUrlLauncher();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, null);
  });

  group('Android (default target platform)', () {
    test('invokes the drslisting/network_settings channel method', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, (call) async {
        calls.add(call);
        return null;
      });

      await NetworkSettingsService.openWifiSettings();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'openWifiSettings');
    });

    test('swallows a missing platform handler (catch path)', () async {
      // No mock registered → invokeMethod throws MissingPluginException,
      // which the service must swallow.
      await NetworkSettingsService.openWifiSettings();
      // Reaching here without a thrown error is the assertion.
    });
  });

  group('iOS', () {
    // Dart's Uri normalizes the scheme to lowercase ('app-prefs'), which
    // iOS matches case-insensitively — both spellings are declared in
    // LSApplicationQueriesSchemes to be safe.
    const wifiSettingsUrl = 'app-prefs:root=WIFI';

    test('launches the App-Prefs:root=WIFI URL via url_launcher', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final fake = UrlLauncherPlatform.instance as _FakeUrlLauncher;

      await NetworkSettingsService.openWifiSettings();

      expect(fake.canLaunchCalls, [wifiSettingsUrl]);
      expect(fake.launchCalls, [wifiSettingsUrl]);
    });

    test('skips the launch when canLaunchUrl reports the scheme is rejected',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final fake = UrlLauncherPlatform.instance as _FakeUrlLauncher
        ..canLaunchResult = false;

      await NetworkSettingsService.openWifiSettings();

      expect(fake.canLaunchCalls, [wifiSettingsUrl]);
      expect(fake.launchCalls, isEmpty);
    });

    test('still attempts a direct launch when canLaunchUrl throws',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final fake = UrlLauncherPlatform.instance as _FakeUrlLauncher
        ..throwOnCanLaunch = true;

      await NetworkSettingsService.openWifiSettings();

      // canLaunchUrl blew up → the service doesn't trust it and launches
      // directly (mirrors the LaunchService.sms false-negative fix).
      expect(fake.launchCalls, [wifiSettingsUrl]);
    });

    test('swallows a launch failure (catch path)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final fake = UrlLauncherPlatform.instance as _FakeUrlLauncher
        ..throwOnLaunch = true;

      await NetworkSettingsService.openWifiSettings();

      // Settings rejected the deep link → swallowed, no crash.
      expect(fake.launchCalls, [wifiSettingsUrl]);
    });
  });
}
