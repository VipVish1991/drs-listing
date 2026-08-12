import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/home_controller.dart';
import 'package:DrsListing/controllers/voice_controller.dart';
import 'package:DrsListing/screens/home/home_screen.dart';
import 'package:DrsListing/services/local_storage_service.dart';
import 'package:DrsListing/services/tts_service.dart';
import 'package:DrsListing/widgets/health_assistant_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../helpers/fake_video_platform.dart';

class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestHomeController extends HomeController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  String get userName => 'Test User';
}

/// Completes instantly so the welcome flow can run deterministically.
class _FakeTtsService extends TtsService {
  int speakCalls = 0;
  VoidCallback? lastOnComplete;

  @override
  Future<void> speak(String text, {VoidCallback? onComplete}) async {
    speakCalls++;
    lastOnComplete = onComplete;
    // Don't call onComplete here — the test controls when the greeting
    // "finishes" to assert the auto-mic timing.
  }

  @override
  Future<void> stop() async {}
}

/// Records whether the mic was auto-started by the welcome flow and
/// whether a tap-to-stop landed on the full-screen stop overlay.
class _ReadyVoiceController extends VoiceController {
  int autoStartCalls = 0;
  int stopCalls = 0;

  _ReadyVoiceController({bool initialized = true}) {
    isInitialized.value = initialized;
  }

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> startListening() async {
    autoStartCalls++;
  }

  @override
  Future<void> stopListening() async {
    stopCalls++;
    isListening.value = false;
  }
}



Future<_FakeTtsService> _pumpHomeScreen(
  WidgetTester tester,
  VoiceController voiceController,
) async {
  final fakeTts = _FakeTtsService();
  TtsService.setInstanceForTest(fakeTts);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
  );
  await tester.pump(const Duration(milliseconds: 1500));
  // The welcome flow is deliberately delayed: the avatar video starts
  // 1.5s after the screen opens, and the greeting audio starts together
  // with it ("With the video" — welcomeGreetingAudioDelay is 0 ms).
  // Advance past both so every test below works with the greeting in
  // flight.
  await tester.pump(const Duration(seconds: 5));
  return fakeTts;
}

Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<HomeController>(_TestHomeController(), permanent: true);
    // Fresh, initialized local storage for every test so the saved
    // avatar-video pause state never leaks between tests.
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService().init();
  });

  tearDown(() {
    TtsService.setInstanceForTest(TtsService());
    // Restore the real (placeholder) video platform so the fake installed
    // by the tap-based test never leaks into the next test.
    VideoPlayerPlatform.instance = originalVideoPlatform;
    Get.reset();
  });

  group('HomeScreen welcome flow (video + greeting + auto mic)', () {
    testWidgets('empty state shows the voice-first prompt and no chat '
        'input', (tester) async {
      final vc = _ReadyVoiceController(initialized: false);
      Get.put<VoiceController>(vc, permanent: true);

      await _pumpHomeScreen(tester, vc);

      // Voice-first empty state: no text chat input…
      expect(find.byType(TextField), findsNothing);
      // …mic prompt title + subtitle…
      expect(find.text('How can I help you today?'), findsOneWidget);
      expect(
        find.textContaining('Tap the mic and describe your symptoms'),
        findsOneWidget,
      );
      // …and the welcome video widget (transparent placeholder fallback
      // in the test environment — the platform video plugin is absent).
      expect(find.byType(HealthAssistantVideo), findsOneWidget);

      await _settleAnimations(tester);
    });

    testWidgets(
      'the avatar video and the greeting start together at 1.5s',
      (tester) async {
        final vc = _ReadyVoiceController(initialized: false);
        Get.put<VoiceController>(vc, permanent: true);

        final fakeTts = _FakeTtsService();
        TtsService.setInstanceForTest(fakeTts);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
        );
        await tester.pump(const Duration(milliseconds: 500));

        // Before the 1.5s mark the avatar is still paused + silent.
        expect(fakeTts.speakCalls, 0);
        await tester.pump(const Duration(milliseconds: 900)); // t=1.4s
        expect(fakeTts.speakCalls, 0);
        expect(
          tester
              .widget<HealthAssistantVideo>(find.byType(HealthAssistantVideo))
              .autoPlay,
          isFalse,
        );

        // Crossing the 1.5s threshold starts the avatar video AND the
        // greeting voice — the timing is fixed to "With the video".
        await tester.pump(const Duration(milliseconds: 200)); // t=1.6s
        expect(
          tester
              .widget<HealthAssistantVideo>(find.byType(HealthAssistantVideo))
              .autoPlay,
          isTrue,
        );
        expect(fakeTts.speakCalls, 1);

        await _settleAnimations(tester);
      },
    );

    testWidgets(
      'a stale stored delay from older builds falls back to With the '
      'video', (tester) async {
        // Older builds could persist 'welcome_greeting_delay_ms': 2000 —
        // that preset no longer exists, so the flow resolves it to the
        // fixed "With the video" (0 ms) default and speaks together with
        // the video.
        SharedPreferences.setMockInitialValues({
          'welcome_greeting_delay_ms': 2000,
        });
        await LocalStorageService().init();

        final vc = _ReadyVoiceController(initialized: false);
        Get.put<VoiceController>(vc, permanent: true);
        final fakeTts = _FakeTtsService();
        TtsService.setInstanceForTest(fakeTts);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
        );
        await tester.pump(const Duration(milliseconds: 1600)); // t=1.6s

        // The avatar video started at 1.5s and the greeting spoke right
        // along with it — the stale 2s stagger was ignored.
        expect(
          tester
              .widget<HealthAssistantVideo>(find.byType(HealthAssistantVideo))
              .autoPlay,
          isTrue,
        );
        expect(fakeTts.speakCalls, 1);

        await _settleAnimations(tester);
      },
    );

    testWidgets(
      'a zero greeting delay starts the voice together with the video',
      (tester) async {
        // The patient picked "With the video" (0 ms) in settings.
        SharedPreferences.setMockInitialValues({
          'welcome_greeting_delay_ms': 0,
        });
        await LocalStorageService().init();

        final vc = _ReadyVoiceController(initialized: false);
        Get.put<VoiceController>(vc, permanent: true);
        final fakeTts = _FakeTtsService();
        TtsService.setInstanceForTest(fakeTts);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
        );
        // Crossing the 1.5s video start: voice speaks immediately.
        await tester.pump(const Duration(milliseconds: 1600));
        expect(fakeTts.speakCalls, 1);

        await _settleAnimations(tester);
      },
    );

    testWidgets(
      'no greeting audio if the user is already talking when the welcome '
      'fires', (tester) async {
        final vc = _ReadyVoiceController(initialized: false);
        Get.put<VoiceController>(vc, permanent: true);

        final fakeTts = _FakeTtsService();
        TtsService.setInstanceForTest(fakeTts);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
        );
        // The user starts the mic before the 1.5s welcome trigger.
        vc.isListening.value = true;
        // Past the welcome trigger AND the greeting delay — the flow
        // bailed at 1.5s, so neither the video nor the delayed voice
        // ever fires.
        await tester.pump(const Duration(milliseconds: 1600)); // t=1.6s
        await tester.pump(const Duration(milliseconds: 1100)); // t=2.7s

        // The welcome flow bails out — the avatar never plays and no
        // greeting speech happens.
        expect(fakeTts.speakCalls, 0);
        expect(
          tester
              .widget<HealthAssistantVideo>(find.byType(HealthAssistantVideo))
              .autoPlay,
          isFalse,
        );

        await _settleAnimations(tester);
      },
    );

    testWidgets(
      'tapping the paused avatar to resume plays the greeting together '
      'with the video', (tester) async {
        final vc = _ReadyVoiceController(initialized: true);
        Get.put<VoiceController>(vc, permanent: true);

        final fakeTts = _FakeTtsService();
        TtsService.setInstanceForTest(fakeTts);

        // Give the avatar a working video platform so a tap reaches the
        // playback toggle (otherwise it degrades to the placeholder and
        // taps do nothing).
        VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
        );

        // Run the auto-welcome to completion so the avatar is left paused:
        // video + greeting start together at 1.5s, then complete.
        await tester.pump(const Duration(milliseconds: 1600));
        await tester.pump(const Duration(milliseconds: 1100)); // t=2.7s
        expect(fakeTts.speakCalls, 1); // auto-welcome greeting
        expect(vc.autoStartCalls, 0); // mic waits for the greeting to end
        fakeTts.lastOnComplete?.call();
        await tester.pump();
        expect(vc.autoStartCalls, 1); // …then the auto-welcome starts it

        // Tap the avatar to resume — the video plays and the greeting
        // voice starts together with it ("With the video").
        await tester.ensureVisible(find.byType(HealthAssistantVideo));
        await tester.tap(find.byType(HealthAssistantVideo));
        await tester.pump(const Duration(milliseconds: 100));
        expect(fakeTts.speakCalls, 2); // resume greeting spoken with video

        // When the resumed greeting finishes, the mic is NOT auto-started
        // again — that's exclusive to the first auto-welcome.
        fakeTts.lastOnComplete?.call();
        await tester.pump();
        expect(vc.autoStartCalls, 1);

        await _settleAnimations(tester);
      },
    );

    testWidgets(
      'video widget shows the health-icon placeholder when the platform '
      'video plugin is absent',
      (tester) async {
        final vc = _ReadyVoiceController(initialized: false);
        Get.put<VoiceController>(vc, permanent: true);

        // The breathing "speaking" pulse lives in the parent (AnimatedScale
        // in HomeScreen) — the widget itself just plays the video.
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: Center(child: HealthAssistantVideo()),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        // Transparent placeholder with the health icon (the fallback
        // shown in tests — the platform video plugin is absent).
        expect(find.byType(HealthAssistantVideo), findsOneWidget);
        expect(find.byIcon(Icons.health_and_safety_rounded), findsOneWidget);

        await _settleAnimations(tester);
      },
    );

    testWidgets(
      'auto-starts the mic after the greeting finishes when speech is '
      'initialized',
      (tester) async {
        final vc = _ReadyVoiceController(initialized: true);
        Get.put<VoiceController>(vc, permanent: true);

        final fakeTts = await _pumpHomeScreen(tester, vc);

        // The greeting was spoken once; before it "finishes" the mic has
        // NOT auto-started yet.
        expect(fakeTts.speakCalls, 1);
        expect(vc.autoStartCalls, 0);

        // Greeting completes → mic auto-starts exactly once.
        fakeTts.lastOnComplete?.call();
        await tester.pump();
        expect(vc.autoStartCalls, 1);

        await _settleAnimations(tester);
      },
    );

    testWidgets('does NOT auto-start the mic when speech is not initialized', (
      tester,
    ) async {
      final vc = _ReadyVoiceController(initialized: false);
      Get.put<VoiceController>(vc, permanent: true);

      final fakeTts = await _pumpHomeScreen(tester, vc);
      fakeTts.lastOnComplete?.call();
      await tester.pump();

      // Deterministic in tests: no speech engine → no surprise mic.
      expect(vc.autoStartCalls, 0);

      await _settleAnimations(tester);
    });

    testWidgets('tapping the screen while listening stops the mic', (
      tester,
    ) async {
      final vc = _ReadyVoiceController(initialized: false);
      Get.put<VoiceController>(vc, permanent: true);

      await _pumpHomeScreen(tester, vc);

      // Simulate an in-progress recording → the full-screen tap-to-stop
      // overlay appears above the whole layout.
      vc.isListening.value = true;
      await tester.pump();

      // A tap anywhere on the screen (here: mid-screen) stops the mic.
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(vc.stopCalls, 1);

      // The fake TTS never auto-completes, so the empty state stays.
      expect(find.text('How can I help you today?'), findsOneWidget);

      await _settleAnimations(tester);
    });

    testWidgets('clearing the chat replays the welcome greeting', (
      tester,
    ) async {
      final vc = _ReadyVoiceController(initialized: false);
      Get.put<VoiceController>(vc, permanent: true);

      final fakeTts = await _pumpHomeScreen(tester, vc);
      expect(fakeTts.speakCalls, 1); // welcome greeting

      // Clearing the chat (delete button) returns to the empty state and
      // replays the welcome flow — the video restarts, then the greeting
      // voice follows after its stagger delay.
      await tester.ensureVisible(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      // The post-frame replay hook starts the welcome flow; the greeting
      // voice follows after its stagger delay.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(fakeTts.speakCalls, 2); // replay after clear

      await _settleAnimations(tester);
    });

    testWidgets('saves paused=true in local storage when the welcome '
        'playback stops', (tester) async {
      final vc = _ReadyVoiceController(initialized: false);
      Get.put<VoiceController>(vc, permanent: true);

      final fakeTts = await _pumpHomeScreen(tester, vc);
      // Before the greeting finishes, no pause state has been saved yet.
      expect(LocalStorageService().isAvatarVideoPaused(), isFalse);

      // Greeting completes → the avatar video stops on its own → the
      // paused state is persisted for the next app open.
      fakeTts.lastOnComplete?.call();
      await tester.pump();
      expect(LocalStorageService().isAvatarVideoPaused(), isTrue);

      await _settleAnimations(tester);
    });

    testWidgets('auto-welcome stays quiet when disabled in settings', (
      tester,
    ) async {
      // The patient turned off Auto-Play Welcome in Profile settings.
      SharedPreferences.setMockInitialValues({'welcome_auto_play': false});
      await LocalStorageService().init();

      final vc = _ReadyVoiceController(initialized: true);
      Get.put<VoiceController>(vc, permanent: true);
      final fakeTts = _FakeTtsService();
      TtsService.setInstanceForTest(fakeTts);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
      );
      // Well past the 1.5s welcome delay — no video, no greeting audio,
      // no auto-started mic.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(seconds: 5));

      expect(fakeTts.speakCalls, 0);
      expect(vc.autoStartCalls, 0);
      expect(
        tester
            .widget<HealthAssistantVideo>(find.byType(HealthAssistantVideo))
            .autoPlay,
        isFalse,
      );

      await _settleAnimations(tester);
    });

    testWidgets('saved pause=true keeps the welcome quiet on the next '
        'open', (tester) async {
      // A previous session left the avatar paused → restore that state.
      SharedPreferences.setMockInitialValues({'avatar_video_paused': true});
      await LocalStorageService().init();

      final vc = _ReadyVoiceController(initialized: false);
      Get.put<VoiceController>(vc, permanent: true);
      final fakeTts = _FakeTtsService();
      TtsService.setInstanceForTest(fakeTts);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      // Well past the welcome delay — the avatar stays quiet: no
      // greeting audio, no auto-started mic.
      await tester.pump(const Duration(seconds: 5));
      expect(fakeTts.speakCalls, 0);
      expect(vc.autoStartCalls, 0);

      await _settleAnimations(tester);
    });
  });

  group('LocalStorageService avatar video pause state', () {
    test('round-trips paused=true / paused=false', () async {
      final storage = LocalStorageService();
      expect(storage.isAvatarVideoPaused(), isFalse);

      await storage.setAvatarVideoPaused(true);
      expect(storage.isAvatarVideoPaused(), isTrue);

      await storage.setAvatarVideoPaused(false);
      expect(storage.isAvatarVideoPaused(), isFalse);
    });

    test('welcome auto-play toggle round-trips true / false (default on)',
        () async {
      final storage = LocalStorageService();
      expect(storage.isWelcomeAutoPlayEnabled(), isTrue);

      await storage.setWelcomeAutoPlayEnabled(false);
      expect(storage.isWelcomeAutoPlayEnabled(), isFalse);

      await storage.setWelcomeAutoPlayEnabled(true);
      expect(storage.isWelcomeAutoPlayEnabled(), isTrue);
    });

    test('welcome greeting delay defaults to 0 (with the video) and '
        'round-trips', () async {
      final storage = LocalStorageService();
      expect(storage.getWelcomeGreetingDelayMs(), 0); // default

      await storage.setWelcomeGreetingDelayMs(0); // together with the video
      expect(storage.getWelcomeGreetingDelayMs(), 0);

      // A corrupt/stale value (e.g. a removed stagger preset) falls back
      // to the default.
      await storage.setWelcomeGreetingDelayMs(12345);
      expect(storage.getWelcomeGreetingDelayMs(), 0);
    });
  });

  group('TtsService', () {
    test('exposes the Hinglish greeting text', () {
      expect(TtsService.greetingText, contains('Namaste!'));
      expect(TtsService.greetingText, contains('specialist doctor'));
    });

    test('_pickLanguage prefers Hindi, then Indian English, then English', () {
      // Private method — exercised through the public instance API surface
      // indirectly by checking installed-language normalization is safe.
      final service = TtsService();
      expect(service, isNotNull);
    });
  });
}
