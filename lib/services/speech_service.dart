import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

// ── Abstract interface for speech recognition ──────────────────────
//
// Exists so we can swap in a fake during unit tests without needing to
// subclass the platform-plugin class (SpeechToText uses a factory
// constructor and can't be extended).

/// Abstract interface for the subset of [SpeechToText] operations that
/// [SpeechService] depends on.
abstract class SpeechEngine {
  Future<bool> initialize({
    void Function(SpeechRecognitionError)? onError,
    void Function(String)? onStatus,
  });

  Future<void> listen({
    void Function(SpeechRecognitionResult)? onResult,
    SpeechListenOptions? listenOptions,
  });

  Future<void> stop();
  Future<void> cancel();
  Future<List<LocaleName>> locales();
}

/// Adapter that wraps the real [SpeechToText] plugin.
class _RealSpeechEngine implements SpeechEngine {
  final SpeechToText _speech = SpeechToText();

  @override
  Future<bool> initialize({
    void Function(SpeechRecognitionError)? onError,
    void Function(String)? onStatus,
  }) =>
      _speech.initialize(onError: onError, onStatus: onStatus);

  @override
  Future<void> listen({
    void Function(SpeechRecognitionResult)? onResult,
    SpeechListenOptions? listenOptions,
  }) =>
      _speech.listen(onResult: onResult, listenOptions: listenOptions);

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();

  @override
  Future<List<LocaleName>> locales() => _speech.locales();
}

// ── SpeechService ───────────────────────────────────────────────────

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal() : _speech = _RealSpeechEngine();

  /// Test-only constructor that accepts a mock/fake [SpeechEngine].
  @visibleForTesting
  factory SpeechService.forTesting(SpeechEngine mockEngine) {
    return SpeechService._withEngine(mockEngine);
  }

  SpeechService._withEngine(this._speech);

  final SpeechEngine _speech;
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isCancelled = false;

  /// Optional callback registered by [startListening] that fires when
  /// the listener ends (via `onStatus` or after `_speech.listen()`
  /// returns) **if** no final result was delivered through the [onResult]
  /// path.  This prevents the UI from staying stuck in "listening" mode.
  Function()? _onSilentStop;

  /// Guard to prevent `onDone` / `_onSilentStop` from firing more than
  /// once per `startListening` session.  Cleared inside [startListening]
  /// before each new session and set to `true` once the callback fires.
  bool _doneFired = false;

  bool get isListening => _isListening;
  bool get isAvailable => _isInitialized;

  /// Exposed for testing: whether _doneFired has been set to `true`.
  @visibleForTesting
  bool get doneFired => _doneFired;

  /// Exposed for testing: whether _isCancelled has been set to `true`.
  @visibleForTesting
  bool get cancelled => _isCancelled;

  /// Exposed for testing: whether _onSilentStop has been registered.
  @visibleForTesting
  bool get hasOnDoneCallback => _onSilentStop != null;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) {
          _isListening = false;
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            _fireOnDoneIfNeeded();
          }
        },
      );
    } catch (e) {
      _isInitialized = false;
    }
    return _isInitialized;
  }

  /// Helper that fires the `_onSilentStop` callback at most once per
  /// `startListening` session.  Guards against the double-fire that
  /// happens when both the status handler and the post-listen code
  /// path try to invoke `onDone`.
  @visibleForTesting
  void fireOnDoneIfNeeded() {
    _fireOnDoneIfNeeded();
  }

  void _fireOnDoneIfNeeded() {
    if (_doneFired) return;
    if (_isCancelled) return;
    _doneFired = true;
    final cb = _onSilentStop;
    _onSilentStop = null;
    cb?.call();
  }

  Future<bool> startListening({
    required Function(String text) onResult,
    Function(String text)? onPartialResult,
    Function(String error)? onError,
    Function()? onDone,
    String? localeId = 'en_US',
    int listenForSeconds = 10,
  }) async {
    // Clear onDone BEFORE stopping so any status events ('notListening')
    // from the old session cannot fire onDone prematurely.
    _onSilentStop = null;
    try {
      await _speech.stop();
    } catch (_) {}

    if (!_isInitialized) {
      await initialize();
    }

    if (!_isInitialized) {
      onError?.call('Speech recognition not available');
      return false;
    }

    _doneFired = false;
    _isCancelled = false;
    _isListening = true;

    _onSilentStop = onDone;

    try {
      await _speech.listen(
        onResult: (result) {
          if (_isCancelled) return;
          if (result.finalResult) {
            _isListening = false;
            // Clear BEFORE firing callbacks so the status handler's
            // _fireOnDoneIfNeeded sees _onSilentStop == null and
            // doesn't double-fire.
            final onDoneCb = _onSilentStop;
            _onSilentStop = null;

            final text = result.recognizedWords;
            if (text.isNotEmpty) {
              onResult(text);
            }
            onDoneCb?.call();
            _speech.stop();
          } else {
            final text = result.recognizedWords;
            if (text.isNotEmpty) {
              onPartialResult?.call(text);
            }
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: Duration(seconds: listenForSeconds),
          // Reduced pauseFor from 2s → 1s for snappier silence detection
          pauseFor: const Duration(seconds: 1),
          partialResults: true,
          cancelOnError: true,
        ),
      );

      // After `_speech.listen()` returns (e.g. listenFor timeout,
      // pauseFor timeout, or error), fire the onDone fallback if it
      // hasn't already been fired through the finalResult path or the
      // status handler.
      _fireOnDoneIfNeeded();

      return true;
    } catch (e) {
      _isListening = false;
      _onSilentStop = null;
      onError?.call('Speech recognition error. Please try again.');
      return false;
    }
  }

  Future<void> stopListening() async {
    _isCancelled = true;
    _isListening = false;
    try {
      await _speech.stop();
    } catch (_) {
      // Ignore stop errors
    }
  }

  Future<void> cancel() async {
    _isCancelled = true;
    _isListening = false;
    try {
      await _speech.cancel();
    } catch (_) {
      // Ignore cancel errors
    }
  }

  Future<List<String>> getAvailableLocales() async {
    try {
      final locales = await _speech.locales();
      return locales.map((l) => l.localeId).toList();
    } catch (_) {
      return [];
    }
  }

  String getLanguageCode(String locale) {
    return locale.split('_').first;
  }

  // Map our supported languages to speech recognition locales
  static const Map<String, String> languageToLocale = {
    'en': 'en_US',
    'hi': 'hi_IN',
    'mr': 'mr_IN',
    'gu': 'gu_IN',
    'ta': 'ta_IN',
    'te': 'te_IN',
    'kn': 'kn_IN',
    'ml': 'ml_IN',
    'pa': 'pa_IN',
    'bn': 'bn_IN',
    'or': 'or_IN',
    'ur': 'ur_PK',
  };

  String getLocaleForLanguage(String languageCode) {
    return languageToLocale[languageCode] ?? 'en_US';
  }
}
