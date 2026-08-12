import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:DrsListing/services/launch_service.dart';

/// Records every canLaunch/launch request so the SMS fallback logic can be
/// asserted exactly. Replaces UrlLauncherPlatform.instance, which is what
/// url_launcher's canLaunchUrl/launchUrl delegates to.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> canLaunchCalls = [];
  final List<String> launchCalls = [];

  /// Returned by every [canLaunch] call.
  bool canLaunchResult = true;

  /// When set, decides [canLaunch]'s answer per URL (takes priority over
  /// [canLaunchResult]).
  bool Function(String url)? canLaunchOverride;

  /// When true, [canLaunch] throws (some devices throw instead of returning).
  bool throwOnCanLaunch = false;

  /// When true, [launch] throws (no app resolves the intent).
  bool throwOnLaunch = false;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    canLaunchCalls.add(url);
    if (throwOnCanLaunch) throw Exception('canLaunch exploded');
    if (canLaunchOverride != null) return canLaunchOverride!(url);
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

  late _FakeUrlLauncher fake;

  setUp(() {
    fake = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fake;
  });

  group('LaunchService.phone', () {
    test('sanitizes the phone number before building the tel: URI', () async {
      fake.canLaunchResult = true;

      // Patient mobiles often contain spaces/dashes. These must be
      // stripped so the dialer can parse the recipient.
      await LaunchService.phone('+91 98765-43210');

      expect(fake.canLaunchCalls, ['tel:+919876543210']);
      expect(fake.launchCalls, ['tel:+919876543210']);
    });

    test('does not launch when the phone is empty or null', () async {
      await LaunchService.phone(null);
      await LaunchService.phone('');
      expect(fake.canLaunchCalls, isEmpty);
      expect(fake.launchCalls, isEmpty);
    });

    test('does not crash when nothing can launch', () async {
      fake.canLaunchResult = false;
      await LaunchService.phone('9876543210');
      expect(fake.canLaunchCalls, ['tel:9876543210']);
      expect(fake.launchCalls, isEmpty);
    });
  });

  group('LaunchService.sms', () {
    test('sanitizes the phone number before building the sms: URI', () async {
      fake.canLaunchResult = true;

      // Google Places numbers often contain spaces/dashes. These must be
      // stripped so the SMS app can parse the recipient.
      await LaunchService.sms('+91 98765-43210');

      expect(fake.canLaunchCalls, ['sms:+919876543210']);
      expect(fake.launchCalls, ['sms:+919876543210']);
    });

    test(
      'falls back to smsto: when the sms: scheme cannot be launched',
      () async {
        // sms: is not resolvable on this device, but smsto: is.
        fake.canLaunchOverride = (url) => url.startsWith('smsto:');

        await LaunchService.sms('9876543210');

        expect(fake.canLaunchCalls, ['sms:9876543210', 'smsto:9876543210']);
        expect(fake.launchCalls, ['smsto:9876543210']);
      },
    );

    test('still launches directly when canLaunchUrl returns false for both '
        'schemes (Android false-negative fix)', () async {
      fake.canLaunchResult = false;

      await LaunchService.sms('9876543210');

      // canLaunch says no for both, but the direct launch attempt must
      // still be made — canLaunchUrl is unreliable for SMS intents. The
      // first scheme (sms:) resolves, so it is used.
      expect(fake.launchCalls, ['sms:9876543210']);
    });

    test('tolerates canLaunchUrl throwing by trying the next scheme', () async {
      fake.throwOnCanLaunch = true;
      fake.canLaunchResult = true;

      await LaunchService.sms('9876543210');

      // Both canLaunch calls threw, but the direct sms: attempt succeeds.
      expect(fake.launchCalls, ['sms:9876543210']);
    });

    test('includes the message body in the URI query', () async {
      fake.canLaunchResult = true;

      await LaunchService.sms('9876543210', message: 'Hi Doc');

      // Dart's Uri encodes query spaces as '+'.
      expect(fake.launchCalls, ['sms:9876543210?body=Hi+Doc']);
    });

    test('does not launch when the phone is empty or null', () async {
      await LaunchService.sms(null);
      await LaunchService.sms('');
      expect(fake.canLaunchCalls, isEmpty);
      expect(fake.launchCalls, isEmpty);
    });

    test('does not crash when every launch attempt fails', () async {
      fake.throwOnLaunch = true;
      // canLaunch says no for both schemes, so both direct launch attempts
      // are made — and both throw, which is caught (snackbar is a no-op in
      // a plain test with no Get.context).
      fake.canLaunchResult = false;
      await LaunchService.sms('9876543210');
      expect(fake.launchCalls, ['sms:9876543210', 'smsto:9876543210']);
    });
  });
}
