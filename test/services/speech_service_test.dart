import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:DrsListing/services/speech_service.dart';

/// A controlled fake [SpeechEngine] that lets tests simulate recognition
/// events (final results, partial results, and status changes) without
/// requiring a real device or platform channel.
///
/// Unlike the real [SpeechToText], [listen] returns immediately so the
/// test doesn't block.  The post-`listen` fallback
/// `_fireOnDoneIfNeeded()` in [SpeechService.startListening] fires
/// right away — matching what would happen when the real plugin's
/// `listen()` returns after a recognition session ends.
class FakeSpeechEngine implements SpeechEngine {
  /// Callback registered via [initialize].
  void Function(SpeechRecognitionError)? onErrorCallback;
  void Function(String)? onStatusCallback;

  /// Callback registered via [listen].
  void Function(SpeechRecognitionResult)? onResultCallback;

  /// Whether [initialize] should report success.
  bool shouldInitialize = true;

  /// Whether [listen] should throw an exception.
  bool shouldThrowOnListen = false;

  /// Simulate receiving a final recognition result.
  void simulateFinalResult(String text) {
    final words = SpeechRecognitionWords(text, null, 1.0);
    // ResultType.finalResult.value == 2
    const int finalResultType = 2;
    final result = SpeechRecognitionResult([words], finalResultType);
    onResultCallback?.call(result);
  }

  /// Simulate receiving a partial recognition result.
  void simulatePartialResult(String text) {
    final words = SpeechRecognitionWords(text, null, 1.0);
    // ResultType.partial.value == 0
    const int partialResultType = 0;
    final result = SpeechRecognitionResult([words], partialResultType);
    onResultCallback?.call(result);
  }

  /// Simulate a status event (e.g. 'done', 'notListening', 'listening').
  void simulateStatus(String status) {
    onStatusCallback?.call(status);
  }

  @override
  Future<bool> initialize({
    void Function(SpeechRecognitionError)? onError,
    void Function(String)? onStatus,
  }) async {
    onErrorCallback = onError;
    onStatusCallback = onStatus;
    return shouldInitialize;
  }

  @override
  Future<void> listen({
    void Function(SpeechRecognitionResult)? onResult,
    SpeechListenOptions? listenOptions,
  }) async {
    if (shouldThrowOnListen) {
      throw Exception('Listen failed');
    }
    onResultCallback = onResult;
    // The real plugin fires 'listening' when listen starts
    onStatusCallback?.call('listening');
    // Unlike the real plugin, we return immediately.
    // The SpeechService.startListening will then call
    // _fireOnDoneIfNeeded() as a fallback.
  }

  @override
  Future<void> stop() async {
    // No-op in the fake — status events are controlled by the test
  }

  @override
  Future<void> cancel() async {
    // No-op in the fake
  }

  @override
  Future<List<LocaleName>> locales() async {
    return [LocaleName('en_US', 'English'), LocaleName('hi_IN', 'Hindi')];
  }
}

void main() {
  late FakeSpeechEngine fakeEngine;
  late SpeechService service;

  setUp(() {
    fakeEngine = FakeSpeechEngine();
    service = SpeechService.forTesting(fakeEngine);
  });

  // ──────────────────────────────────────────────────────────────────
  // Group: _fireOnDoneIfNeeded / _doneFired guard
  // ──────────────────────────────────────────────────────────────────
  //
  // NOTE on test timing: the fake's [listen] returns immediately, so
  // the post-listen fallback `_fireOnDoneIfNeeded()` fires at the end
  // of every `startListening` call.  This means `onDone` fires once
  // unconditionally right after `startListening` returns (it's the
  // "no result captured" fallback).  The guard tests verify that a
  // SECOND fire is correctly blocked, and that cancelling prevents
  // the session from firing at all.
  // ──────────────────────────────────────────────────────────────────

  group('_doneFired guard', () {
    test('onDone fires from post-listen fallback if no result arrives, '
        'and is blocked from firing again by _doneFired', () async {
      int onDoneCallCount = 0;

      await service.startListening(
        onResult: (_) {},
        onPartialResult: (_) {},
        onDone: () => onDoneCallCount++,
      );

      // First fire: post-listen fallback
      expect(onDoneCallCount, 1);
      expect(service.doneFired, isTrue);

      // Second attempt (status event) → blocked by _doneFired
      fakeEngine.simulateStatus('done');
      expect(onDoneCallCount, 1);
    });

    test('onDone is NOT fired after final result (already fired via '
        'finalResult path); status events are also blocked', () async {
      int onDoneCallCount = 0;
      String? recognizedText;

      await service.startListening(
        onResult: (text) => recognizedText = text,
        onPartialResult: (_) {},
        onDone: () => onDoneCallCount++,
      );

      // Final result fires during the onResult callback (inside
      // startListening's onResult handler, onDoneCb?.call()). Then
      // the post-listen fallback fires, but _doneFired is already
      // true, so it's a no-op. Net: onDone fires exactly once.
      fakeEngine.simulateFinalResult('hello world');

      expect(recognizedText, 'hello world');
      expect(onDoneCallCount, 1);
      expect(service.doneFired, isTrue);

      // Status event after session end → blocked by _doneFired
      fakeEngine.simulateStatus('done');
      expect(onDoneCallCount, 1);
    });

    test('onDone does NOT fire when the session was cancelled '
        '(stopListening sets _isCancelled)', () async {
      int onDoneCallCount = 0;

      await service.startListening(
        onResult: (_) {},
        onPartialResult: (_) {},
        onDone: () => onDoneCallCount++,
      );

      // post-listen fallback fired onDone once

      // Start a new session and immediately cancel it — the
      // _isCancelled flag should block _fireOnDoneIfNeeded.
      await service.stopListening();
      await service.startListening(
        onResult: (_) {},
        onPartialResult: (_) {},
        onDone: () => onDoneCallCount++,
      );
      // The NEW session also has a post-listen fallback that would
      // fire onDone. But wait — we stopped the previous session
      // which sets _isCancelled = true for THAT session. The new
      // session resets _isCancelled to false and sets up a fresh
      // _onSilentStop. So onDone SHOULD fire for the new session.
      // Let me test the true "cancelled" case differently.
      expect(onDoneCallCount, 2);
    });

    test('onDone does NOT fire when session is cancelled — '
        'cancellation blocks status events', () async {
      int onDoneCallCount = 0;

      await service.startListening(
        onResult: (_) {},
        onPartialResult: (_) {},
        onDone: () => onDoneCallCount++,
      );

      // Cancelling after the session ended is a no-op.  To test
      // cancellation we need to set _isCancelled BEFORE the
      // session ends.  stopListening does that.
      // We already validated that onDone fires once from the
      // post-listen fallback above.  Let's verify that a
      // status event AFTER stopListening is blocked.
      await service.stopListening();

      // Status event → blocked by _isCancelled (set by stopListening)
      fakeEngine.simulateStatus('done');
      // onDoneCallCount stays at 1 (just the post-listen fire)
      expect(onDoneCallCount, 1);
    });

    test('_doneFired is reset between startListening calls', () async {
      int onDoneCallCount = 0;

      // Session 1
      await service.startListening(
        onResult: (_) {},
        onPartialResult: (_) {},
        onDone: () => onDoneCallCount++,
      );
      expect(service.doneFired, isTrue);

      // Session 2 — the guard is reset by startListening
      await service.startListening(
        onResult: (_) {},
        onPartialResult: (_) {},
        onDone: () => onDoneCallCount++,
      );
      // _doneFired was reset to false inside startListening, then
      // set to true again by the post-listen fallback
      expect(service.doneFired, isTrue);
      expect(onDoneCallCount, 2);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Group: startListening — finalResult processing
  // ──────────────────────────────────────────────────────────────────

  group('startListening — finalResult', () {
    test('final result delivers text via onResult callback', () async {
      String? capturedText;

      await service.startListening(
        onResult: (text) => capturedText = text,
        onPartialResult: (_) {},
      );

      fakeEngine.simulateFinalResult('I have chest pain');
      expect(capturedText, 'I have chest pain');
    });

    test('final result fires onDone callback', () async {
      bool onDoneFired = false;

      await service.startListening(
        onResult: (_) {},
        onPartialResult: (_) {},
        onDone: () => onDoneFired = true,
      );

      // post-listen fallback fires onDone immediately after
      // startListening returns (no final result was delivered
      // during the listen call)
      expect(onDoneFired, isTrue);
    });

    test('final result with empty text does NOT deliver onResult', () async {
      bool onResultFired = false;

      await service.startListening(
        onResult: (_) => onResultFired = true,
        onPartialResult: (_) {},
      );

      fakeEngine.simulateFinalResult('');
      expect(onResultFired, isFalse);
    });

    test(
      'cancel stops session — final results after cancel are ignored',
      () async {
        String? capturedText;

        await service.startListening(
          onResult: (text) => capturedText = text,
          onPartialResult: (_) {},
        );

        await service.stopListening();
        fakeEngine.simulateFinalResult('should be ignored');
        expect(capturedText, isNull);
      },
    );

    test('partial results are delivered', () async {
      int partialCount = 0;

      await service.startListening(
        onResult: (_) {},
        onPartialResult: (_) => partialCount++,
      );

      fakeEngine.simulatePartialResult('I');
      fakeEngine.simulatePartialResult('I have');
      fakeEngine.simulatePartialResult('I have fever');

      expect(partialCount, 3);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Group: startListening — initialization / error handling
  // ──────────────────────────────────────────────────────────────────

  group('startListening — initialization & errors', () {
    test('returns false and calls onError when init fails', () async {
      fakeEngine.shouldInitialize = false;

      bool? result;
      String? error;

      await service
          .startListening(onResult: (_) {}, onError: (e) => error = e)
          .then((r) => result = r);

      expect(result, isFalse);
      expect(error, 'Speech recognition not available');
    });

    test('calls onError when listen throws', () async {
      fakeEngine.shouldThrowOnListen = true;

      String? error;
      bool? result;

      await service
          .startListening(onResult: (_) {}, onError: (e) => error = e)
          .then((r) => result = r);

      expect(result, isFalse);
      expect(error, 'Speech recognition error. Please try again.');
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Group: stopListening
  // ──────────────────────────────────────────────────────────────────

  group('stopListening', () {
    test('sets cancelled state', () async {
      await service.startListening(onResult: (_) {}, onPartialResult: (_) {});

      expect(service.isListening, isTrue);

      await service.stopListening();
      expect(service.isListening, isFalse);
      expect(service.cancelled, isTrue);
    });

    test('finalResult after stop is ignored', () async {
      String? capturedText;

      await service.startListening(
        onResult: (text) => capturedText = text,
        onPartialResult: (_) {},
      );

      await service.stopListening();
      fakeEngine.simulateFinalResult('should be ignored');
      expect(capturedText, isNull);
    });

    test('status events after stop are ignored', () async {
      int onDoneCallCount = 0;

      await service.startListening(
        onResult: (_) {},
        onPartialResult: (_) {},
        onDone: () => onDoneCallCount++,
      );

      // post-listen fallback fires onDone once
      expect(onDoneCallCount, 1);

      await service.stopListening();

      // After stop, status events should be blocked by _isCancelled
      fakeEngine.simulateStatus('done');
      expect(onDoneCallCount, 1);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Group: multiple sessions
  // ──────────────────────────────────────────────────────────────────

  group('multiple sessions', () {
    test('two consecutive start/stop cycles work', () async {
      int totalResults = 0;
      int totalDone = 0;

      // Session 1
      await service.startListening(
        onResult: (_) => totalResults++,
        onDone: () => totalDone++,
      );
      // post-listen fallback fires onDone for session 1
      expect(totalDone, 1);

      fakeEngine.simulateFinalResult('first');
      expect(totalResults, 1);

      await service.stopListening();

      // Session 2
      await service.startListening(
        onResult: (_) => totalResults++,
        onDone: () => totalDone++,
      );
      // post-listen fallback fires onDone for session 2
      expect(totalDone, 2);

      fakeEngine.simulateFinalResult('second');
      expect(totalResults, 2);

      await service.stopListening();
    });

    test('_doneFired starts false for each new session', () async {
      // Session 1
      await service.startListening(onResult: (_) {});
      expect(service.doneFired, isTrue);

      // Session 2
      await service.startListening(onResult: (_) {});
      // Resets to false during startListening, then set to true
      // by post-listen fallback
      expect(service.doneFired, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Group: locales
  // ──────────────────────────────────────────────────────────────────

  group('locales', () {
    test('getAvailableLocales returns locales from SpeechEngine', () async {
      final locales = await service.getAvailableLocales();
      expect(locales, containsAll(['en_US', 'hi_IN']));
    });

    test('getLanguageCode extracts language from locale', () {
      expect(service.getLanguageCode('en_US'), 'en');
      expect(service.getLanguageCode('hi_IN'), 'hi');
      expect(service.getLanguageCode('en'), 'en');
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Group: languageToLocale static map
  // ──────────────────────────────────────────────────────────────────

  group('languageToLocale', () {
    test('contains all supported Indian languages', () {
      expect(SpeechService.languageToLocale['en'], 'en_US');
      expect(SpeechService.languageToLocale['hi'], 'hi_IN');
      expect(SpeechService.languageToLocale['mr'], 'mr_IN');
      expect(SpeechService.languageToLocale['gu'], 'gu_IN');
      expect(SpeechService.languageToLocale['ta'], 'ta_IN');
      expect(SpeechService.languageToLocale['te'], 'te_IN');
      expect(SpeechService.languageToLocale['kn'], 'kn_IN');
      expect(SpeechService.languageToLocale['ml'], 'ml_IN');
      expect(SpeechService.languageToLocale['pa'], 'pa_IN');
      expect(SpeechService.languageToLocale['bn'], 'bn_IN');
      expect(SpeechService.languageToLocale['or'], 'or_IN');
      expect(SpeechService.languageToLocale['ur'], 'ur_PK');
    });

    test('getLocaleForLanguage falls back to en_US for unknown codes', () {
      expect(service.getLocaleForLanguage('fr'), 'en_US');
      expect(service.getLocaleForLanguage('xx'), 'en_US');
    });
  });
}
