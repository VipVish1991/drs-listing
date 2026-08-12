import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/appointment_controller.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/home_controller.dart';
import 'package:DrsListing/controllers/profile_controller.dart';
import 'package:DrsListing/controllers/voice_controller.dart';
import 'package:DrsListing/screens/main_shell.dart';
import 'package:DrsListing/services/tts_service.dart';

/// Test doubles that skip the network/speech/location work their real
/// counterparts start in onInit (mirrors the pattern in
/// doctor_detail_screen_test.dart and about_screen_test.dart).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestVoiceController extends VoiceController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Skips geolocation permission checks and the 60s periodic location timer.
class _TestHomeController extends HomeController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestAppointmentController extends AppointmentController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestProfileController extends ProfileController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Completes instantly — the real FlutterTts never responds on a bare
/// test binding (it hangs the MethodChannel), which would block the home
/// screen's welcome flow.
class _FakeTtsService extends TtsService {
  @override
  Future<void> speak(String text, {VoidCallback? onComplete}) async {
    onComplete?.call();
  }
}

/// Lets every flutter_animate effect in the shell run to completion so no
/// "Timer is still pending" guard trips at the end of a test.
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    // Start each test with a clean Get container.
    Get.reset();
    TtsService.setInstanceForTest(_FakeTtsService());
    Get.put<VoiceController>(_TestVoiceController(), permanent: true);
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<HomeController>(_TestHomeController(), permanent: true);
    Get.put<AppointmentController>(
      _TestAppointmentController(),
      permanent: true,
    );
    Get.put<ProfileController>(_TestProfileController(), permanent: true);
  });

  testWidgets('Main shell shows the four tabs and switches between them', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const MainShell()),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Appointments'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Switch to the Profile tab — the shell must not try to refresh the
    // removed API-usage counter, and the row must not appear.
    await tester.tap(find.text('Profile'));
    await tester.pump();
    await tester.pump();
    expect(find.text('API Calls Today'), findsNothing);

    await _settleAnimations(tester);
  });
}
