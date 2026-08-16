import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:DrsListing/models/appointment_model.dart';
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

/// Fake of the Google API surface — replaces [meetFlowGateway] so the flow
/// runs without Firebase / Google Sign-In / Calendar platform channels.
class _FakeMeetFlowGateway implements MeetFlowGateway {
  bool signInResult = true;
  bool throwOnSignIn = false;
  bool throwOnCreateEvent = false;

  /// What createEvent throws when [throwOnCreateEvent] is set (defaults to
  /// a generic exception).
  Exception createEventThrow = Exception('event exploded');

  /// What createEvent returns (the `{'id': ..., 'link': ...}` map).
  Map<String, String>? createEventResult = const {
    'id': 'evt_1',
    'link': 'https://meet.google.com/abc-def-ghi',
  };

  int signInCalls = 0;
  int createEventCalls = 0;
  String? lastTitle;
  String? lastDescription;
  DateTime? lastStart;
  DateTime? lastEnd;

  @override
  Future<bool> signIn(BuildContext context) async {
    signInCalls++;
    if (throwOnSignIn) throw Exception('sign-in exploded');
    return signInResult;
  }

  @override
  Future<Map<String, String>?> createEvent({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    createEventCalls++;
    lastTitle = title;
    lastDescription = description;
    lastStart = startTime;
    lastEnd = endTime;
    if (throwOnCreateEvent) throw createEventThrow;
    return createEventResult;
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

/// The same appointment but with a stored Meet link — simulates the OTHER
/// side having already started the meeting, so joining must reuse the room.
AppointmentModel _appointmentWithStoredLink() => _videoAppointment().copyWith(
      meetLink: 'https://meet.google.com/xyz-uvw-123',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeUrlLauncher urlLauncher;
  late _FakeMeetFlowGateway gateway;

  setUp(() {
    urlLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = urlLauncher;
    gateway = _FakeMeetFlowGateway();
    meetFlowGateway = gateway;
  });

  tearDown(() {
    // Restore the production gateway so other tests aren't affected.
    meetFlowGateway = SdkMeetFlowGateway();
  });

  /// Pumps a throwaway widget tree to obtain a real BuildContext (the flow
  /// requires one for Google Sign-In; the fake gateway ignores it).
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

  group('MeetConsultService mobile flow (mocked Google APIs)', () {
    testWidgets('joinConsultation: sign-in → event → opens the link',
        (tester) async {
      final context = await captureContext(tester);

      final result = await joinConsultation(context, _videoAppointment());

      // Google sign-in ran, then the calendar event was created with the
      // appointment's slot window (10:00 AM → 10:30 AM) and a title built
      // from the consultation type + doctor.
      expect(gateway.signInCalls, 1);
      expect(gateway.createEventCalls, 1);
      expect(gateway.lastTitle, 'Video Consultation — Dr. Sharma');
      expect(gateway.lastDescription, 'Fever since yesterday');
      expect(gateway.lastStart, DateTime(2026, 8, 3, 10, 0));
      expect(gateway.lastEnd, DateTime(2026, 8, 3, 10, 30));

      // The returned Meet link was opened externally.
      expect(urlLauncher.launchCalls, ['https://meet.google.com/abc-def-ghi']);
      expect(result.success, isTrue);
      expect(result.meetingLink, 'https://meet.google.com/abc-def-ghi');
    });

    testWidgets('joinConsultation: a stored link joins the SAME room — no '
        'sign-in, no new event', (tester) async {
      final context = await captureContext(tester);

      final result =
          await joinConsultation(context, _appointmentWithStoredLink());

      // Neither Google API was touched — the existing room is reopened.
      expect(gateway.signInCalls, 0);
      expect(gateway.createEventCalls, 0);
      expect(urlLauncher.launchCalls, ['https://meet.google.com/xyz-uvw-123']);
      expect(result.success, isTrue);
      expect(result.meetingLink, 'https://meet.google.com/xyz-uvw-123');
    });

    testWidgets('joinConsultation: cancelled sign-in never creates an event',
        (tester) async {
      final context = await captureContext(tester);
      gateway.signInResult = false;

      final result = await joinConsultation(context, _videoAppointment());

      expect(gateway.createEventCalls, 0);
      expect(urlLauncher.launchCalls, isEmpty);
      expect(result.success, isFalse);
      expect(result.error, 'Google Sign-In was cancelled.');
    });

    testWidgets('joinConsultation: failed event creation does not open a link',
        (tester) async {
      final context = await captureContext(tester);
      gateway.createEventResult = null;

      final result = await joinConsultation(context, _videoAppointment());

      expect(gateway.createEventCalls, 1);
      expect(urlLauncher.launchCalls, isEmpty);
      expect(result.success, isFalse);
      expect(result.error, 'Meeting creation failed.');
    });

    testWidgets('joinConsultation: literal null link string is treated as '
        'failure (upstream SDK quirk)', (tester) async {
      final context = await captureContext(tester);
      gateway.createEventResult = const {'id': 'evt_1', 'link': 'null'};

      final result = await joinConsultation(context, _videoAppointment());

      expect(urlLauncher.launchCalls, isEmpty);
      expect(result.success, isFalse);
      expect(result.error, 'Meeting creation failed.');
    });

    testWidgets('joinConsultation: createEvent throw surfaces a retry '
        'message', (tester) async {
      final context = await captureContext(tester);
      gateway.throwOnCreateEvent = true;

      final result = await joinConsultation(context, _videoAppointment());

      expect(urlLauncher.launchCalls, isEmpty);
      expect(result.success, isFalse);
      expect(result.error, 'Could not create the meeting. Try again.');
    });

    testWidgets('joinConsultation: a Calendar-API-disabled 403 surfaces the '
        'actionable enable hint', (tester) async {
      final context = await captureContext(tester);
      gateway.throwOnCreateEvent = true;
      gateway.createEventThrow = Exception(
        'DetailedApiRequestError(status: 403, message: Google Calendar '
        'API has not been used in project 450216527653 before or it is '
        'disabled.)',
      );

      final result = await joinConsultation(context, _videoAppointment());

      expect(urlLauncher.launchCalls, isEmpty);
      expect(result.success, isFalse);
      expect(result.error, contains(kCalendarApiEnableUrl));
      expect(result.error, contains('disabled'));
    });

    testWidgets('startConsultation: profile entry uses the passed title and '
        'opens the link', (tester) async {
      final context = await captureContext(tester);

      final result = await startConsultation(
        context,
        title: 'Video Consultation — Dr. Meet',
      );

      expect(gateway.signInCalls, 1);
      expect(gateway.createEventCalls, 1);
      expect(gateway.lastTitle, 'Video Consultation — Dr. Meet');
      expect(gateway.lastDescription, '');
      // now → +30 min window (start is ~now, so just assert the range).
      expect(gateway.lastStart, isNotNull);
      expect(gateway.lastEnd!.difference(gateway.lastStart!), const Duration(minutes: 30));
      expect(urlLauncher.launchCalls, ['https://meet.google.com/abc-def-ghi']);
      expect(result.success, isTrue);
    });

    testWidgets('appointment without a parseable time falls back to a '
        'now→+30min window', (tester) async {
      final context = await captureContext(tester);
      final appointment = AppointmentModel(
        appointmentId: 'APT_MEET_IO_2',
        consultationType: 'tele',
      );

      await joinConsultation(context, appointment);

      expect(gateway.createEventCalls, 1);
      expect(gateway.lastStart, isNotNull);
      expect(
        gateway.lastEnd!.difference(gateway.lastStart!),
        const Duration(minutes: 30),
      );
    });
  });
}
