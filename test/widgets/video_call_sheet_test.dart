import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/widgets/video_call_sheet.dart';

/// Records every launch request so the sheet's Join/Share actions can be
/// asserted (same pattern as the LaunchService/MeetService tests).
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

AppointmentModel _appointment({String? meetLink}) => AppointmentModel(
      appointmentId: 'APT123',
      consultationType: 'video',
      patientName: 'Ravi',
      callNumber: '9876543210',
      meetLink: meetLink,
    );

/// Pumps the sheet directly inside a Scaffold (the production code shows it
/// via Get.bottomSheet; the widget itself is layout-agnostic).
Future<List<String?>> _pumpSheet(
  WidgetTester tester, {
  required AppointmentModel appointment,
  String otherPartyLabel = 'Doctor',
  bool Function(String?)? saveResult,
}) async {
  final saved = <String?>[];
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: VideoCallSheet(
          appointment: appointment,
          sharePhone: appointment.callNumber,
          otherPartyLabel: otherPartyLabel,
          onSaveLink: (link) async {
            saved.add(link);
            return saveResult?.call(link) ?? true;
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return saved;
}

/// Flushes a Get.snackbar shown by the sheet's async save chain so no
/// pending timer/ticker leaks past the test. Get snackbars animate over
/// 1s and the display timer is 4s — force-close first (probed: pumping the
/// timer out and only then closing double-closes and leaks the ticker),
/// then pump past the 1s reverse animation, then dispose + settle.
Future<void> _flushSnackbars(WidgetTester tester) async {
  Get.closeAllSnackbars();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  late _FakeUrlLauncher fake;

  setUp(() {
    Get.reset();
    fake = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fake;
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('no-link state shows the create-link prompt, not Join', (
    tester,
  ) async {
    await _pumpSheet(tester, appointment: _appointment());

    expect(find.textContaining('No meeting link yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('video_call_start')), findsOneWidget);
    expect(find.byKey(const ValueKey('video_call_paste')), findsOneWidget);
    expect(find.byKey(const ValueKey('video_call_join')), findsNothing);
    expect(find.byKey(const ValueKey('video_call_copy')), findsNothing);
    expect(find.byKey(const ValueKey('video_call_share')), findsNothing);
  });

  testWidgets('link state shows the code, Join, Copy and Share', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      appointment: _appointment(
        meetLink: 'https://meet.google.com/abc-defg-hij',
      ),
      otherPartyLabel: 'Patient',
    );

    expect(find.text('Meeting link ready'), findsOneWidget);
    expect(find.text('abc-defg-hij'), findsOneWidget);
    expect(find.byKey(const ValueKey('video_call_join')), findsOneWidget);
    expect(find.byKey(const ValueKey('video_call_copy')), findsOneWidget);
    expect(find.text('Send to Patient'), findsOneWidget);
  });

  testWidgets('Join opens the saved meeting link', (tester) async {
    await _pumpSheet(
      tester,
      appointment: _appointment(
        meetLink: 'https://meet.google.com/abc-defg-hij',
      ),
    );

    await tester.tap(find.byKey(const ValueKey('video_call_join')));
    await tester.pump();

    expect(fake.launchCalls, ['https://meet.google.com/abc-defg-hij']);
  });

  testWidgets(
    'pasting a valid link saves the NORMALIZED url and updates the sheet',
    (tester) async {
      final saved = await _pumpSheet(tester, appointment: _appointment());

      // Open the paste dialog and enter a bare code (not a full URL) —
      // normalization must produce the full meet URL before saving.
      await tester.tap(find.byKey(const ValueKey('video_call_paste')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('meet_link_field')),
        'abc-defg-hij',
      );
      await tester.tap(find.byKey(const ValueKey('meet_link_save')));
      // Settle the dialog's exit animation + snackbar entrance before
      // asserting (pumpAndSettle is safe: it never waits on the snackbar's
      // 4s display timer).
      await tester.pumpAndSettle();

      expect(saved, ['https://meet.google.com/abc-defg-hij']);
      // The sheet now shows the ready state with the code.
      expect(find.text('Meeting link ready'), findsOneWidget);
      expect(find.text('abc-defg-hij'), findsOneWidget);
      expect(find.byKey(const ValueKey('video_call_join')), findsOneWidget);

      await _flushSnackbars(tester);
    },
  );

  testWidgets('an invalid link is rejected without saving', (tester) async {
    final saved = await _pumpSheet(tester, appointment: _appointment());

    await tester.tap(find.byKey(const ValueKey('video_call_paste')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('meet_link_field')),
      'not-a-meet-link',
    );
    await tester.tap(find.byKey(const ValueKey('meet_link_save')));
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
    expect(
      find.textContaining('That does not look like a Google Meet link'),
      findsOneWidget,
    );
    // Still no link state.
    expect(find.byKey(const ValueKey('video_call_join')), findsNothing);

    await _flushSnackbars(tester);
  });

  testWidgets('Send shares the link over WhatsApp with the invite', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      appointment: _appointment(
        meetLink: 'https://meet.google.com/abc-defg-hij',
      ),
    );

    await tester.tap(find.byKey(const ValueKey('video_call_share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video_call_share_whatsapp')));
    await tester.pumpAndSettle();

    expect(
      fake.launchCalls.single,
      startsWith('https://wa.me/919876543210?text='),
    );
    expect(fake.launchCalls.single, contains('meet.google.com'));
  });
}
