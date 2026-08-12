import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/home_controller.dart';
import 'package:DrsListing/controllers/voice_controller.dart';
import 'package:DrsListing/models/ai_response_model.dart';
import 'package:DrsListing/screens/home/home_screen.dart';
import 'package:DrsListing/services/tts_service.dart';
import 'package:DrsListing/widgets/voice_button.dart';

/// Test doubles that skip the network/location/speech work their real
/// counterparts start in onInit (mirrors the pattern in
/// main_shell_test.dart and profile_screen_test.dart).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestHomeController extends HomeController {
  @override
  // ignore: must_call_super
  void onInit() {}

  /// Overridden so the header shows a deterministic greeting.
  @override
  String get userName => 'Test User';
}

/// Skips speech init AND the AI pipeline — sendMessage only adds the user
/// bubble so the voice flow can be asserted without network.
class _TestVoiceController extends VoiceController {
  int stopCalls = 0;

  _TestVoiceController() {
    // Mark the speech engine as ready so the delayed welcome flow's
    // auto-start-mic step completes synchronously — with the welcome
    // delay now 3s it fires inside these tests, and an uninitialized
    // engine would otherwise spin up retry timers that never settle.
    isInitialized.value = true;
  }

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> sendMessage(String text) async {
    messages.add(ChatMessage(text: text.trim(), isUser: true));
  }

  @override
  Future<void> startListening() async {
    // No-op — never touch the real mic in layout tests.
  }

  @override
  Future<void> stopListening() async {
    stopCalls++;
    isListening.value = false;
  }
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

/// Pumps [HomeScreen] with test controllers registered.
Future<void> _pumpHomeScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

/// Lets every flutter_animate effect on the screen run to completion so no
/// "Timer is still pending" guard trips at the end of a test (mirrors
/// main_shell_test.dart). The extra beat covers the welcome flow — avatar
/// video and greeting audio start together at 1.5s — so its timers have
/// fully fired by the end of the test.
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUp(() {
    Get.reset();
    TtsService.setInstanceForTest(_FakeTtsService());
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<HomeController>(_TestHomeController(), permanent: true);
  });

  tearDown(() {
    TtsService.setInstanceForTest(TtsService());
    Get.reset();
  });

  group('HomeScreen voice-first layout', () {
    testWidgets('has no text chat input — the design is voice-only', (
      tester,
    ) async {
      Get.put<VoiceController>(_TestVoiceController(), permanent: true);
      await _pumpHomeScreen(tester);

      // The text chat input (TextField) was removed from the home screen.
      expect(find.byType(TextField), findsNothing);

      // Empty state still shows the mic prompt + quick symptom chips.
      expect(find.text('How can I help you today?'), findsOneWidget);
      expect(
        find.textContaining('Tap the mic and describe your symptoms'),
        findsOneWidget,
      );
      expect(find.text('Fever & Cold'), findsOneWidget);
      expect(find.text('Headache'), findsOneWidget);

      await _settleAnimations(tester);
    });

    testWidgets('voice controls render (filter / mic / delete)', (
      tester,
    ) async {
      Get.put<VoiceController>(_TestVoiceController(), permanent: true);
      await _pumpHomeScreen(tester);

      // Filter + delete flank the mic button.
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      // Main voice button (mic) — always visible on the voice-first home.
      expect(find.byType(VoiceButton), findsOneWidget);

      await _settleAnimations(tester);
    });

    testWidgets('tapping the screen while listening stops the mic', (
      tester,
    ) async {
      final vc = _TestVoiceController();
      Get.put<VoiceController>(vc, permanent: true);
      await _pumpHomeScreen(tester);

      // Simulate an in-progress recording → the full-screen stop overlay
      // appears above the whole layout.
      vc.isListening.value = true;
      await tester.pump();

      // A tap anywhere on the screen (here: mid-screen) stops the mic.
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();

      expect(vc.stopCalls, 1);

      await _settleAnimations(tester);
    });
  });
}
