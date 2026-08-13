import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/home_controller.dart';
import 'package:DrsListing/controllers/voice_controller.dart';
import 'package:DrsListing/screens/home/home_screen.dart';
import 'package:DrsListing/services/tts_service.dart';

import '../helpers/mock_permissions.dart';

class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestHomeController extends HomeController {
  @override
  // ignore: must_call_super
  void onInit() {
    // The real controller opens the location-permission gate during its
    // own init; the double skips that, so open it explicitly or the home
    // screen's GPS→mic sequencing (which awaits this) would stall.
    completeLocationPermissionFlowForTest();
  }

  @override
  String get userName => 'Test';
}

/// HomeController whose location-permission gate stays PENDING until the
/// test releases it — simulates the GPS permission dialog still being on
/// screen (the real controller shows it ~500ms after the dashboard
/// opens). Lets the sequencing be asserted: mic must NOT be asked before
/// the GPS flow resolves.
class _PendingFlowHomeController extends HomeController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  String get userName => 'Test';
}

/// Completes instantly so the welcome flow never hangs.
class _FakeTtsService extends TtsService {
  @override
  Future<void> speak(String text, {VoidCallback? onComplete}) async {
    onComplete?.call();
  }

  @override
  Future<void> stop() async {}
}

/// Counts how many times the dashboard asked the voice controller to warm
/// up the speech engine (the step that triggers the OS mic-permission
/// prompt on Android).
class _TrackingVoiceController extends VoiceController {
  int initSpeechCalls = 0;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> initSpeech() async {
    initSpeechCalls++;
  }

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}
}

void main() {
  setUp(() {
    Get.reset();
    // The home screen's GPS→mic sequencing awaits the microphone probe;
    // an unmocked permission_handler channel never resolves in widget
    // tests, so resolve it as granted.
    mockMicPermissionGranted();
    TtsService.setInstanceForTest(_FakeTtsService());
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<HomeController>(_TestHomeController(), permanent: true);
  });

  tearDown(() {
    clearMicPermissionMock();
    TtsService.setInstanceForTest(TtsService());
    Get.reset();
  });

  testWidgets('opening the patient dashboard asks for the mic by kicking '
      'off speech init (post-login, not at app startup)', (tester) async {
    final vc = _TrackingVoiceController();
    Get.put<VoiceController>(vc, permanent: true);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The dashboard requested speech/mic initialization exactly once.
    expect(vc.initSpeechCalls, 1);

    // Flush the welcome flow timers so nothing leaks between tests.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('mic is asked only AFTER the GPS permission flow resolves '
      '(one OS prompt at a time)', (tester) async {
    final vc = _TrackingVoiceController();
    Get.put<VoiceController>(vc, permanent: true);

    // Swap the auto-completing HomeController (setUp) for one whose
    // location-permission gate stays PENDING — simulating the GPS
    // permission dialog still being on screen.
    Get.delete<HomeController>(force: true);
    final pendingHome = _PendingFlowHomeController();
    Get.put<HomeController>(pendingHome, permanent: true);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The GPS prompt is unresolved → the mic must NOT be asked yet.
    expect(vc.initSpeechCalls, 0,
        reason: 'mic permission must wait for the GPS flow to resolve');

    // The user answers the GPS dialog → the gate opens → the mic is asked
    // right after, exactly once.
    pendingHome.completeLocationPermissionFlowForTest();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(vc.initSpeechCalls, 1,
        reason: 'mic permission is asked exactly once, right after GPS');

    // Flush the welcome-flow timers so nothing leaks between tests.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('creating the voice controller alone does NOT init speech '
      '(permission deferred to the dashboard)', (tester) async {
    final vc = _TrackingVoiceController();
    Get.put<VoiceController>(vc, permanent: true);

    // Give any (removed) app-startup auto-init a chance to run.
    await tester.pump(const Duration(seconds: 1));
    expect(vc.initSpeechCalls, 0);

    // Opening the dashboard is what triggers it.
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(vc.initSpeechCalls, 1);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(seconds: 5));
  });
}
