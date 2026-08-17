import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/services/meet_consult_service.dart';
import 'package:DrsListing/services/meet_consult_service_io.dart';

/// Records url_launcher calls so the flow's final "open the link" step can
/// be asserted.
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

AppointmentModel _videoAppointment() => AppointmentModel(
      appointmentId: 'APT_MEET_IO_1',
      doctorName: 'Dr. Sharma',
      patientName: 'Rahul Sharma',
      appointmentDate: '2026-08-03',
      appointmentTime: '10:00 AM',
      consultationType: 'video',
      symptoms: 'Fever since yesterday',
    );

/// The same appointment but with a stored Meet link — simulates an
/// appointment created after the static-link change, which carries the
/// shared room pre-filled.
AppointmentModel _appointmentWithStoredLink() => _videoAppointment().copyWith(
      meetLink: kStaticMeetLink,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeUrlLauncher urlLauncher;

  setUp(() {
    urlLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = urlLauncher;
  });

  /// Pumps a throwaway widget tree to obtain a real BuildContext (the flow
  /// requires one for the URL launch).
  Future<BuildContext> captureContext(WidgetTester tester) async {
    BuildContext? captured;
    await tester.pumpWidget(
      Builder(builder: (context) {
        captured = context;
        return const SizedBox.shrink();
      }),
    );
    return captured!;
  }

  group('MeetConsultService mobile flow (static meeting room)', () {
    testWidgets('joinConsultation opens the STATIC room when the '
        'appointment has no stored link', (tester) async {
      final context = await captureContext(tester);

      final result = await joinConsultation(context, _videoAppointment());

      // Every meeting uses the same fixed room — no sign-in, no event.
      expect(urlLauncher.launchCalls, [kStaticMeetLink]);
      expect(result.success, isTrue);
      expect(result.meetingLink, kStaticMeetLink);
    });

    testWidgets('joinConsultation: a stored link opens that exact room',
        (tester) async {
      final context = await captureContext(tester);

      final result =
          await joinConsultation(context, _appointmentWithStoredLink());

      expect(urlLauncher.launchCalls, [kStaticMeetLink]);
      expect(result.success, isTrue);
      expect(result.meetingLink, kStaticMeetLink);
    });

    testWidgets('joinConsultation: a legacy appointment with a different '
        'stored room still joins THAT room', (tester) async {
      final context = await captureContext(tester);
      const legacy = 'https://meet.google.com/xyz-uvw-123';
      final appointment = _videoAppointment().copyWith(meetLink: legacy);

      final result = await joinConsultation(context, appointment);

      expect(urlLauncher.launchCalls, [legacy]);
      expect(result.success, isTrue);
      expect(result.meetingLink, legacy);
    });

    testWidgets('startConsultation opens the STATIC room regardless of the '
        'passed title', (tester) async {
      final context = await captureContext(tester);

      final result = await startConsultation(
        context,
        title: 'Video Consultation — Dr. Meet',
      );

      expect(urlLauncher.launchCalls, [kStaticMeetLink]);
      expect(result.success, isTrue);
      expect(result.meetingLink, kStaticMeetLink);
    });
  });
}
