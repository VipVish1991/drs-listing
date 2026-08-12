import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:DrsListing/services/connectivity_service.dart';

void main() {
  tearDown(() {
    // Reset probe + pending banner state so a test that flips
    // reachability can't leak into the next test. (Each test sets its
    // own online state at the start, so no applyResult is needed here.)
    ConnectivityService.instance.resetReachabilityForTest();
  });

  testWidgets('shows no banner while online', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: appScaffoldMessengerKey,
        home: const Scaffold(body: Center(child: Text('app'))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Start online → no offline banner.
    ConnectivityService.instance.applyResult(true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('No internet connection'), findsNothing);
  });

  testWidgets('shows the offline banner when the connection drops and '
      'hides it when connectivity returns', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: appScaffoldMessengerKey,
        home: const Scaffold(body: Center(child: Text('app'))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Connection drops → persistent banner appears with Settings + Retry.
    ConnectivityService.instance.applyResult(false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('No internet connection'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Still offline after another event → the banner is not re-shown.
    ConnectivityService.instance.applyResult(false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('No internet connection'), findsOneWidget);

    // Connectivity returns → banner disappears automatically. (The exit
    // animation runs on the first pump; the banner leaves the tree on
    // the following frame.)
    ConnectivityService.instance.applyResult(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.textContaining('No internet connection'), findsNothing);
  });

  group('offline banner actions', () {
    testWidgets('tapping Settings invokes the Wi-Fi settings channel and '
        'swallows the platform error (catch path)', (tester) async {
      // The platform handler doesn't exist in tests — mock the channel to
      // record the call and then throw (exactly what a missing handler /
      // unsupported platform produces), so the catch path inside
      // NetworkSettingsService.openWifiSettings is exercised.
      const channel = MethodChannel('drslisting/network_settings');
      final invoked = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          invoked.add(call);
          throw PlatformException(
            code: 'not_implemented',
            message: 'No plugin implementation on this platform',
          );
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: appScaffoldMessengerKey,
          home: const Scaffold(body: Center(child: Text('app'))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Connection drops → the banner with its Settings action appears.
      // (Banner insertion and its entrance animation each need their own
      // pump, plus a settle frame, before the action button is laid out in
      // its final — hit-testable — position.)
      ConnectivityService.instance.applyResult(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Settings'), findsOneWidget);

      // Tap Settings → the method channel is actually invoked (proving the
      // button is wired) and the platform error is swallowed: no uncaught
      // exception, no crash, the banner stays visible.
      await tester.tap(find.widgetWithText(TextButton, 'Settings'));
      await tester.pump();
      await tester.pump();

      expect(invoked, hasLength(1));
      expect(invoked.single.method, 'openWifiSettings');
      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('internet reachability probe', () {
    testWidgets('keeps online when the probe succeeds', (tester) async {
      ConnectivityService.instance.probeHttpClient = MockClient(
        (request) async => http.Response('', 204),
      );
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: appScaffoldMessengerKey,
          home: const Scaffold(body: Center(child: Text('app'))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Interface present (e.g. Wi-Fi) → applyResult(true); the probe
      // agrees there is internet → still online, no banner.
      ConnectivityService.instance.applyResult(true);
      await tester.pump(const Duration(milliseconds: 300));
      await ConnectivityService.instance.runReachabilityProbe();
      await tester.pump(const Duration(milliseconds: 300));

      expect(ConnectivityService.instance.online.value, isTrue);
      expect(find.textContaining('No internet connection'), findsNothing);
    });

    testWidgets('marks offline + shows the banner when the probe fails '
        'even though a Wi-Fi interface is present (router without internet)',
        (tester) async {
      ConnectivityService.instance.probeHttpClient = MockClient(
        (request) async => throw http.ClientException('no internet'),
      );
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: appScaffoldMessengerKey,
          home: const Scaffold(body: Center(child: Text('app'))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Wi-Fi interface is up but the probe fails → the service reports
      // offline and the banner appears (connectivity_plus alone would
      // have said online, hiding it).
      ConnectivityService.instance.applyResult(true);
      await tester.pump(const Duration(milliseconds: 300));
      await ConnectivityService.instance.runReachabilityProbe();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(ConnectivityService.instance.online.value, isFalse);
      expect(find.textContaining('No internet connection'), findsOneWidget);

      // Internet comes back → probe succeeds → banner hides.
      ConnectivityService.instance.probeHttpClient = MockClient(
        (request) async => http.Response('', 204),
      );
      await ConnectivityService.instance.runReachabilityProbe();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(ConnectivityService.instance.online.value, isTrue);
      expect(find.textContaining('No internet connection'), findsNothing);
    });
  });
}
