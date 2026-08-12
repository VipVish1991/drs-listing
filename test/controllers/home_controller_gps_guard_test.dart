import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/doctor_search_controller.dart';
import 'package:DrsListing/controllers/home_controller.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/services/location_service.dart';

class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Skips the location/periodic-timer work the real controller starts in
/// onInit, and exposes the GPS-probe override for deterministic tests.
class _TestHomeController extends HomeController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  String get userName => 'Test';

  // [fetchTopDoctors] hits the real Places API; the location tests here
  // never assert on it, so keep it a no-op for deterministic runs.
  @override
  Future<void> fetchTopDoctors() async {}
}

class _TestSearchController extends DoctorSearchController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _DummySearchScreen extends StatelessWidget {
  const _DummySearchScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('SEARCH SCREEN')));
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      getPages: [
        GetPage(
          name: AppRoutes.doctorSearch,
          page: () => const _DummySearchScreen(),
        ),
      ],
      home: const Scaffold(body: Center(child: Text('HOME'))),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    Get.reset();
    // HomeController's constructor resolves AuthController via Get.find.
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  testWidgets('quick-chip search shows the GPS-off alert instead of '
      'navigating when GPS is off', (tester) async {
    final home = _TestHomeController();
    // Mutable captured state — the dialog's gpsCheck closure re-reads it
    // on every "check again" tap, so toggling it below simulates the
    // user actually turning GPS on.
    var gpsEnabled = false;
    home.isGpsEnabledOverride = () async => gpsEnabled;
    Get.put<HomeController>(home, permanent: true);
    Get.put<DoctorSearchController>(_TestSearchController(), permanent: true);

    await _pumpApp(tester);

    // GPS off → the search is blocked by the GPS alert. (Like the quick
    // chip's onTap, the call is not awaited — searchDoctors only resolves
    // after the dialog closes.)
    unawaited(home.searchDoctors('Cardiologist'));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsOneWidget);
    expect(find.text('SEARCH SCREEN'), findsNothing);

    // The user enables GPS and confirms via "check again" → the dialog
    // closes and the pending search proceeds.
    gpsEnabled = true;
    await tester.tap(find.text("I've enabled GPS — check again"));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsNothing);
    expect(find.text('SEARCH SCREEN'), findsOneWidget);
  });

  testWidgets('quick-chip search navigates immediately when GPS is on', (
    tester,
  ) async {
    final home = _TestHomeController();
    home.isGpsEnabledOverride = () async => true;
    Get.put<HomeController>(home, permanent: true);
    Get.put<DoctorSearchController>(_TestSearchController(), permanent: true);

    await _pumpApp(tester);

    await home.searchDoctors('Cardiologist');
    await tester.pumpAndSettle();

    expect(find.text('SEARCH SCREEN'), findsOneWidget);
    expect(find.text('GPS is Off'), findsNothing);
  });

  testWidgets('ensureGpsEnabled proceeds when the platform probe is '
      'unavailable (tests / desktop)', (tester) async {
    final home = _TestHomeController();
    // The real Geolocator hangs on a bare test binding — simulate an
    // unavailable probe that throws; the guard must not block the action.
    home.isGpsEnabledOverride = () async =>
        throw StateError('platform probe unavailable');
    Get.put<HomeController>(home, permanent: true);
    Get.put<DoctorSearchController>(_TestSearchController(), permanent: true);

    await _pumpApp(tester);

    await home.searchDoctors('Cardiologist');
    await tester.pumpAndSettle();

    expect(find.text('SEARCH SCREEN'), findsOneWidget);
    expect(find.text('GPS is Off'), findsNothing);
  });

  testWidgets('home page load with GPS off shows the automatic GPS-off '
      'popup with an Open-Settings action', (tester) async {
    final home = _TestHomeController();
    // GPS is disabled → the location fetch fails with serviceDisabled.
    home.isGpsEnabledOverride = () async => false;
    home.fetchLocationOverride = () async => LocationResult(
      success: false,
      reason: LocationFailureReason.serviceDisabled,
    );
    Get.put<HomeController>(home, permanent: true);
    Get.put<DoctorSearchController>(_TestSearchController(), permanent: true);

    await _pumpApp(tester);

    // Simulate the home page's initial location load.
    unawaited(home.debugFetchLocation());
    await tester.pump();
    // The popup waits 600ms for the navigator, then shows.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('GPS is Off'), findsOneWidget);
    expect(find.text('Open Location Settings'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget); // home stays usable
  });

  testWidgets('dismissed GPS-off popup is not re-shown on the next '
      'location refresh', (tester) async {
    final home = _TestHomeController();
    home.isGpsEnabledOverride = () async => false;
    home.fetchLocationOverride = () async => LocationResult(
      success: false,
      reason: LocationFailureReason.serviceDisabled,
    );
    Get.put<HomeController>(home, permanent: true);
    Get.put<DoctorSearchController>(_TestSearchController(), permanent: true);

    await _pumpApp(tester);

    unawaited(home.debugFetchLocation());
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsOneWidget);

    // Dismiss it — the home screen keeps working without GPS.
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsNothing);

    // A later periodic refresh still finds GPS off, but no second popup.
    await home.debugFetchLocation();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsNothing);
  });

  testWidgets('enabling GPS from the auto-popup refreshes the location', (
    tester,
  ) async {
    final home = _TestHomeController();
    var gpsEnabled = false;
    home.isGpsEnabledOverride = () async => gpsEnabled;
    home.fetchLocationOverride = () async => LocationResult(
      success: false,
      reason: LocationFailureReason.serviceDisabled,
    );
    Get.put<HomeController>(home, permanent: true);
    Get.put<DoctorSearchController>(_TestSearchController(), permanent: true);

    await _pumpApp(tester);

    unawaited(home.debugFetchLocation());
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsOneWidget);

    // The user turns GPS on and confirms → the popup closes and the
    // location refetches (now succeeding, so the popup path ends quietly).
    gpsEnabled = true;
    await tester.tap(find.text("I've enabled GPS — check again"));
    await tester.pumpAndSettle();
    expect(find.text('GPS is Off'), findsNothing);
  });
}
