import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/services/connectivity_service.dart';
import 'package:DrsListing/services/wifi_status_service.dart';
import 'package:DrsListing/widgets/connectivity_status_card.dart';

/// Pumps the card inside a plain Scaffold (no other app chrome).
Future<void> _pumpCard(
  WidgetTester tester, {
  required Future<WifiStatus?> Function() fetchStatus,
  bool autoRefresh = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConnectivityStatusCard(
          fetchStatus: fetchStatus,
          autoRefresh: autoRefresh,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    // Start every test from the online state (the singleton leaks between
    // tests in this file — a card left offline would fetch on the next
    // pump and assert against a stale status).
    ConnectivityService.instance.applyResult(true);
  });

  tearDown(() {
    ConnectivityService.instance.applyResult(true);
  });

  testWidgets('is hidden while online', (tester) async {
    await _pumpCard(tester, fetchStatus: () async => null);

    expect(find.byKey(const Key('connectivity_status_card')), findsNothing);
    expect(find.text('You\'re offline'), findsNothing);
  });

  testWidgets('appears when offline and shows Wi-Fi name + signal bars',
      (tester) async {
    var fetches = 0;
    await _pumpCard(
      tester,
      fetchStatus: () async {
        fetches++;
        return const WifiStatus(
          wifiEnabled: true,
          connected: true,
          ssid: 'HomeWiFi',
          rssi: -57,
          signalLevel: 3,
          linkSpeedMbps: 130,
          locationGranted: true,
        );
      },
    );

    // Still online → no card.
    expect(find.byKey(const Key('connectivity_status_card')), findsNothing);

    // Connection drops → the card appears and reads the Wi-Fi details.
    ConnectivityService.instance.applyResult(false);
    await tester.pump(); // rebuild (offline) + start the fetch
    await tester.pump(const Duration(milliseconds: 300)); // fetch resolves

    expect(find.byKey(const Key('connectivity_status_card')), findsOneWidget);
    expect(find.text('You\'re offline'), findsOneWidget);
    expect(find.text('Connected to HomeWiFi'), findsOneWidget);
    expect(find.text('3/4'), findsOneWidget);
    expect(fetches, 1);

    // Connectivity returns → the card disappears again. (The exit
    // animation starts on the rebuild frame, completes after 300ms, and
    // the outgoing child leaves the tree on the frame after that.)
    ConnectivityService.instance.applyResult(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byKey(const Key('connectivity_status_card')), findsNothing);
  });

  testWidgets('shows a Wi-Fi-off state when the radio is disabled',
      (tester) async {
    await _pumpCard(
      tester,
      fetchStatus: () async => const WifiStatus(
        wifiEnabled: false,
        connected: false,
        locationGranted: true,
      ),
    );

    ConnectivityService.instance.applyResult(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('You\'re offline'), findsOneWidget);
    expect(find.text('Wi-Fi is turned off'), findsOneWidget);
    // No signal bars when there is nothing to measure.
    expect(find.text('3/4'), findsNothing);
  });

  testWidgets('shows the generic state when the status is unavailable',
      (tester) async {
    await _pumpCard(tester, fetchStatus: () async => null);

    ConnectivityService.instance.applyResult(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('You\'re offline'), findsOneWidget);
    expect(find.text('Check your network connection'), findsOneWidget);
  });

  testWidgets('hides the network name when location permission is missing',
      (tester) async {
    await _pumpCard(
      tester,
      fetchStatus: () async => const WifiStatus(
        wifiEnabled: true,
        connected: true,
        ssid: null,
        signalLevel: 2,
        locationGranted: false,
      ),
    );

    ConnectivityService.instance.applyResult(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Connected to Wi-Fi (name hidden)'), findsOneWidget);
    expect(find.textContaining('Grant location access'), findsOneWidget);
  });

  testWidgets('tap on refresh re-reads the Wi-Fi status', (tester) async {
    var fetches = 0;
    await _pumpCard(
      tester,
      fetchStatus: () async {
        fetches++;
        return const WifiStatus(
          wifiEnabled: true,
          connected: true,
          ssid: 'HomeWiFi',
          signalLevel: 2,
          locationGranted: true,
        );
      },
    );

    ConnectivityService.instance.applyResult(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fetches, 1);

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fetches, 2);
  });

  testWidgets('offers a shortcut to the Wi-Fi settings', (tester) async {
    await _pumpCard(tester, fetchStatus: () async => null);

    ConnectivityService.instance.applyResult(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Wi-Fi settings'), findsOneWidget);
  });
}
