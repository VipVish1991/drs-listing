import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech wrapper around [FlutterTts].
///
/// Speaks the welcome greeting on the patient home screen and lets the
/// user replay it. All platform calls are guarded so an unavailable TTS
/// engine (unsupported platform, missing voice pack, or tests) degrades
/// silently instead of crashing the UI.
///
/// The instance is swappable via [setInstanceForTest] so widget tests can
/// inject a fake that completes immediately (the real [FlutterTts] never
/// responds on a bare test binding — it hangs forever, which would block
/// the welcome flow's mic auto-start).
class TtsService {
  TtsService();

  static TtsService instance = TtsService();

  /// Replaces [instance] with a fake for widget tests.
  @visibleForTesting
  static void setInstanceForTest(TtsService tts) => instance = tts;

  final FlutterTts _tts = FlutterTts();

  /// The one-to-one chat greeting spoken when the chat is empty.
  ///
  /// Hinglish on purpose — the app targets Indian users who describe
  /// symptoms in Hindi or English.
  static const String greetingText =
      'Hello! Namaste! Aap bilkul freely mujhe apni health problem ya '
      'symptoms bata sakti hain. Aap Hindi ya English mein baat kar sakti hain. '
      'Main aapki problem ko samajhne mein help karungi aur aapke symptoms '
      'ke basis par aapke liye suitable specialist doctor suggest karungi.';

  /// Whether speech is currently being produced (drives the avatar's
  /// speaking animation).
  @visibleForTesting
  bool isSpeaking = false;

  /// Speaks the welcome [greetingText].
  ///
  /// [onComplete] fires when speech finishes (or immediately when TTS is
  /// unavailable) so the caller can chain the next step (e.g. auto-start
  /// the mic).
  Future<void> speakGreeting({VoidCallback? onComplete}) async {
    await speak(greetingText, onComplete: onComplete);
  }

  /// The doctor-dashboard welcome greeting — Hinglish like the patient
  /// greeting, but aimed at the doctor's daily workflow on the dashboard.
  static String doctorGreetingText(String? doctorName) {
    final name = (doctorName == null || doctorName.trim().isEmpty)
        ? 'Doctor'
        : doctorName.trim();
    return 'Namaste $name! Welcome to your dashboard. '
        'Aap yahan aaj ki appointments dekh sakte hain, apni availability '
        'manage kar sakte hain, aur naye patient requests confirm kar '
        'sakte hain.';
  }

  /// Speaks the doctor-dashboard welcome [doctorGreetingText].
  ///
  /// [onComplete] fires when speech finishes (or immediately when TTS is
  /// unavailable) so the caller can chain the next step.
  Future<void> speakDoctorGreeting({
    String? doctorName,
    VoidCallback? onComplete,
  }) async {
    await speak(doctorGreetingText(doctorName), onComplete: onComplete);
  }

  /// Speaks [text] with the app's preferred TTS language.
  ///
  /// Tries Hindi first for the Hinglish greeting; falls back to Indian
  /// English when the device has no Hindi voice pack.
  Future<void> speak(String text, {VoidCallback? onComplete}) async {
    try {
      _tts.setCompletionHandler(() {
        isSpeaking = false;
        onComplete?.call();
      });
      _tts.setErrorHandler((message) {
        debugPrint('TTS error: $message');
        isSpeaking = false;
        onComplete?.call();
      });
      _tts.setCancelHandler(() {
        isSpeaking = false;
      });

      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      // Make speak() resolve only after the utterance actually finishes so
      // the completion handler (and thus the mic auto-start) is reliable.
      await _tts.awaitSpeakCompletion(true);

      // Pick a language the device actually has installed — trying to set
      // an unavailable one makes speak() silently no-op ("not audible").
      final installed = await _getInstalledLanguages();
      final language = _pickLanguage(installed);
      await _tts.setLanguage(language);

      isSpeaking = true;
      await _tts.speak(text);
    } catch (e) {
      // TTS engine unavailable (tests, unsupported platform, or a missing
      // native engine) — degrade silently and let the caller continue.
      debugPrint('TTS unavailable: $e');
      isSpeaking = false;
      onComplete?.call();
    }
  }

  /// Stops any ongoing speech.
  Future<void> stop() async {
    isSpeaking = false;
    try {
      await _tts.stop();
    } catch (_) {
      // Ignore — stopping when nothing is playing is a no-op.
    }
  }

  /// Returns the list of languages the device's TTS engine reports as
  /// installed, normalized to the form 'xx-XX' (or 'xx' when regional is
  /// missing). Empty on failure.
  Future<List<String>> _getInstalledLanguages() async {
    try {
      final languages = await _tts.getLanguages;
      if (languages == null) return const [];
      final normalized = <String>[];
      for (final raw in languages) {
        final parts = raw.toString().split('-');
        if (parts.isEmpty) continue;
        final lang = parts.first.toLowerCase();
        final region = parts.length > 1 ? parts[1].toUpperCase() : '';
        normalized.add(region.isNotEmpty ? '$lang-$region' : lang);
      }
      return normalized;
    } catch (_) {
      return const [];
    }
  }

  /// Best available voice for the Hinglish greeting: Hindi, then Indian
  /// English, then plain English, then whatever the device reports.
  String _pickLanguage(List<String> installed) {
    const preferred = ['hi-IN', 'hi', 'en-IN', 'en-GB', 'en-US', 'en'];
    for (final candidate in preferred) {
      if (installed.any((l) => l.toLowerCase() == candidate.toLowerCase())) {
        return candidate;
      }
    }
    // Fall back to the device default — speak() will use whatever voice
    // the engine has. An empty list also lands here.
    return installed.isNotEmpty ? installed.first : 'en-US';
  }
}
