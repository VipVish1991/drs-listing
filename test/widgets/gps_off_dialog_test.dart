import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/widgets/gps_off_dialog.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: Center(child: Text('HOME'))),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    Get.reset();
  });

  testWidgets('shows the GPS-off alert when the probe reports GPS off and '
      'blocks until the user enables it', (tester) async {
    await _pumpApp(tester);

    // Mutable captured state — the dialog's gpsCheck closure re-reads it
    // on every "check again" tap, so toggling it below simulates the user
    // actually turning GPS on.
    var gpsEnabled = false;
    final gate = ensureGpsEnabled(gpsCheck: () async => gpsEnabled);

    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsOneWidget);
    // The blocking gate stays a trap — no "Not now" escape hatch leaks in.
    expect(find.text('Not now'), findsNothing);

    // The user enables GPS and confirms → the gate resolves true.
    gpsEnabled = true;
    await tester.tap(find.text("I've enabled GPS — check again"));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsNothing);
    expect(await gate, isTrue);
  });

  testWidgets('returns immediately when GPS is on — no alert', (tester) async {
    await _pumpApp(tester);

    final ok = await ensureGpsEnabled(gpsCheck: () async => true);

    expect(ok, isTrue);
    await tester.pump();
    expect(find.text('GPS is Off'), findsNothing);
  });

  testWidgets('never blocks when the platform probe is unavailable '
      '(tests / desktop)', (tester) async {
    await _pumpApp(tester);

    final ok = await ensureGpsEnabled(
      gpsCheck: () async => throw StateError('platform probe unavailable'),
    );

    expect(ok, isTrue);
    await tester.pump();
    expect(find.text('GPS is Off'), findsNothing);
  });

  testWidgets('dismissible variant shows a Not now escape and closes '
      'without enabling GPS', (tester) async {
    await _pumpApp(tester);

    var gpsEnabled = false;
    final prompt = showGpsOffDialog(
      gpsCheck: () async => gpsEnabled,
      dismissible: true,
    );

    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsOneWidget);
    // A gentle prompt has an escape hatch — the blocking gate does not.
    expect(find.text('Not now'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsNothing);
    // Dismissed without GPS on → resolves false (caller knows to wait).
    expect(await prompt, isFalse);
  });

  testWidgets('dismissible variant still resolves true when the user '
      'enables GPS and checks again', (tester) async {
    await _pumpApp(tester);

    var gpsEnabled = false;
    final prompt = showGpsOffDialog(
      gpsCheck: () async => gpsEnabled,
      dismissible: true,
    );

    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsOneWidget);

    gpsEnabled = true;
    await tester.tap(find.text("I've enabled GPS — check again"));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsNothing);
    expect(await prompt, isTrue);
  });
}
