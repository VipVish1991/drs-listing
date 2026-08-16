import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/services/meet_consult_service.dart';
import 'package:DrsListing/services/meet_consult_service_web.dart';

/// Records url_launcher calls so the web fallback can be asserted.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchCalls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

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

AppointmentModel _remoteAppointment() => AppointmentModel(
      appointmentId: 'APT_MEET_1',
      patientName: 'Rahul Sharma',
      appointmentDate: '2026-08-03',
      appointmentTime: '10:00 AM',
      consultationType: 'video',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeUrlLauncher fake;

  setUp(() {
    fake = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fake;
  });

  group('MeetConsultService (web fallback)', () {
    testWidgets('no stored link → friendly error, no URL launched',
        (tester) async {
      BuildContext? captured;
      await tester.pumpWidget(
        Builder(builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        }),
      );

      final result =
          await joinConsultation(captured!, _remoteAppointment());

      expect(fake.launchCalls, isEmpty);
      expect(result.success, isFalse);
      expect(result.meetingLink, isNull);
    });

    testWidgets('stored link opens that exact room externally',
        (tester) async {
      const stored = 'https://meet.google.com/abc-def-ghi';
      BuildContext? captured;
      await tester.pumpWidget(
        Builder(builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        }),
      );

      final result = await joinConsultation(
        captured!,
        _remoteAppointment().copyWith(meetLink: stored),
      );

      expect(fake.launchCalls, [stored]);
      expect(result.success, isTrue);
      expect(result.meetingLink, stored);
    });

    testWidgets('startConsultation (profile entry) reports mobile-only '
        'with no URL launched', (tester) async {
      BuildContext? captured;
      await tester.pumpWidget(
        Builder(builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        }),
      );

      final result = await startConsultation(
        captured!,
        title: 'Video Consultation — Dr. Meet',
      );

      expect(fake.launchCalls, isEmpty);
      expect(result.success, isFalse);
    });

    test('exposes the shared MeetJoinResult shape', () async {
      const ok = MeetJoinResult.success('https://meet.google.com/abc-def-ghi');
      const bad = MeetJoinResult.failure('nope');

      expect(ok.success, isTrue);
      expect(ok.meetingLink, 'https://meet.google.com/abc-def-ghi');
      expect(ok.error, isNull);
      expect(bad.success, isFalse);
      expect(bad.error, 'nope');
      expect(bad.meetingLink, isNull);
    });
  });
}
