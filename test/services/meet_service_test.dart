import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:DrsListing/services/meet_service.dart';

/// Records every launch request so MeetService's launching can be asserted
/// exactly. Replaces UrlLauncherPlatform.instance, which is what
/// url_launcher's canLaunchUrl/launchUrl delegate to (same pattern as the
/// LaunchService tests).
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> canLaunchCalls = [];
  final List<String> launchCalls = [];

  bool canLaunchResult = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    canLaunchCalls.add(url);
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

  group('MeetService.codeOf', () {
    test('extracts the code from a full URL', () {
      expect(
        MeetService.codeOf('https://meet.google.com/abc-defg-hij'),
        'abc-defg-hij',
      );
    });

    test('accepts a scheme-less host path', () {
      expect(
        MeetService.codeOf('meet.google.com/abc-defg-hij'),
        'abc-defg-hij',
      );
    });

    test('accepts a bare code', () {
      expect(MeetService.codeOf('abc-defg-hij'), 'abc-defg-hij');
    });

    test('strips query / trailing cruft', () {
      expect(
        MeetService.codeOf('https://meet.google.com/abc-defg-hij?pli=1'),
        'abc-defg-hij',
      );
      expect(
        MeetService.codeOf('https://meet.google.com/abc-defg-hij/'),
        'abc-defg-hij',
      );
    });

    test('trims surrounding whitespace', () {
      expect(MeetService.codeOf('  abc-defg-hij  '), 'abc-defg-hij');
    });

    test('rejects non-meet or malformed input', () {
      expect(MeetService.codeOf('https://zoom.us/j/123456'), isNull);
      expect(MeetService.codeOf('abc'), isNull);
      expect(MeetService.codeOf('abc-def'), isNull);
      expect(MeetService.codeOf('abc-defg-hij-klm'), isNull);
      expect(MeetService.codeOf('ABC-DEFG-HIJ'), isNull);
      expect(MeetService.codeOf(''), isNull);
      expect(MeetService.codeOf('not a link'), isNull);
    });
  });

  group('MeetService.normalize', () {
    test('builds the full URL from a bare code', () {
      expect(
        MeetService.normalize('abc-defg-hij'),
        'https://meet.google.com/abc-defg-hij',
      );
    });

    test('passes a full URL through unchanged', () {
      expect(
        MeetService.normalize('https://meet.google.com/abc-defg-hij'),
        'https://meet.google.com/abc-defg-hij',
      );
    });

    test('returns null for invalid input (never invents codes)', () {
      expect(MeetService.normalize('not a link'), isNull);
    });
  });

  group('MeetService.openMeeting', () {
    test('launches the normalized meet URL', () async {
      await MeetService.openMeeting('abc-defg-hij');
      expect(fake.launchCalls, ['https://meet.google.com/abc-defg-hij']);
    });

    test('does not launch for invalid input', () async {
      await MeetService.openMeeting('foo');
      expect(fake.launchCalls, isEmpty);
    });
  });

  group('MeetService.startNewMeeting', () {
    test('opens meet.new so Google generates a real link', () async {
      await MeetService.startNewMeeting();
      expect(fake.launchCalls, ['https://meet.new/']);
    });
  });

  group('MeetService.copyLink', () {
    test('stores the normalized URL on the clipboard', () async {
      // Capture the clipboard write on the platform channel (the default
      // test mock clipboard isn't available in plain unit tests).
      String? written;
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          written = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });

      await MeetService.copyLink('abc-defg-hij');

      expect(written, 'https://meet.google.com/abc-defg-hij');
    });
  });

  group('MeetService share', () {
    test('shares over WhatsApp with a prefilled invite', () async {
      await MeetService.shareViaWhatsApp('9876543210', 'abc-defg-hij');
      expect(
        fake.launchCalls.single,
        startsWith('https://wa.me/919876543210?text='),
      );
      // The invite body embeds the real meet URL (percent-encoded).
      expect(
        fake.launchCalls.single,
        contains('%3A%2F%2Fmeet.google.com'),
      );
    });

    test('shares over SMS with the invite body', () async {
      await MeetService.shareViaSms('9876543210', 'abc-defg-hij');
      expect(
        fake.launchCalls.single,
        startsWith('sms:9876543210?body='),
      );
      expect(fake.launchCalls.single, contains('meet.google.com'));
    });

    test('does not launch when there is no link or number', () async {
      await MeetService.shareViaWhatsApp(null, 'abc-defg-hij');
      await MeetService.shareViaSms('9876543210', 'not a link');
      expect(fake.launchCalls, isEmpty);
    });
  });
}
