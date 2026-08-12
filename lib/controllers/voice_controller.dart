import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../config/constants.dart';
import '../services/speech_service.dart';
import '../utils/text_sanitizer.dart';
import '../services/ai_service.dart';
import '../services/audio_transcription_service.dart';
import '../services/local_storage_service.dart';
import '../services/places_service.dart';
import '../models/ai_response_model.dart';
import '../models/doctor_model.dart';

class VoiceController extends GetxController {
  final SpeechService _speechService = SpeechService();
  final AiService _aiService = AiService();
  final LocalStorageService _storage = LocalStorageService();
  final AudioTranscriptionService _audioService = AudioTranscriptionService();
  final PlacesService _placesService = PlacesService();

  final RxBool isListening = false.obs;
  final RxBool isProcessing = false.obs;
  final RxBool isInitialized = false.obs;
  final RxBool isRecordingAudio = false.obs; // true when recording for Whisper
  final RxBool isTranscribing = false.obs; // true while Whisper processes audio
  final RxString currentText = ''.obs;
  final RxList<ChatMessage> messages = <ChatMessage>[].obs;
  final RxString selectedLanguage = RxString('en');
  final RxString aiResponseText = ''.obs;
  final Rx<AiResponseModel?> latestAnalysis = Rx<AiResponseModel?>(null);
  final RxString micError = ''.obs;

  /// Recommended doctors from the latest AI analysis — populated
  /// automatically after each symptom analysis so doctor cards can be
  /// shown inline in the chat.
  final RxList<DoctorModel> recommendedDoctors = <DoctorModel>[].obs;
  final RxBool isLoadingDoctors = false.obs;

  bool _isInitializing = false;

  /// Callbacks used by [VoiceListeningScreen] to get real-time updates
  /// during the voice recording/analysis flow.
  /// Called when a final speech result is available.
  void Function(String text)? onVoiceResult;

  /// Called with partial speech results for real-time display.
  void Function(String text)? onVoicePartialResult;

  /// Whether the current language should use recording + Whisper API
  /// instead of the device's built-in speech-to-text.
  ///
  /// For English the device STT is fast and accurate; for Indian
  /// languages we use OpenAI Whisper which has much better accuracy.
  bool get _shouldUseWhisper => _baseLanguage != 'en';

  /// Extract the base ISO-639-1 language code from a locale string.
  /// e.g. 'en-IN' -> 'en', 'hi-IN' -> 'hi'
  String get _baseLanguage => selectedLanguage.value.split('-').first;

  @override
  void onInit() {
    super.onInit();
    selectedLanguage.value = _storage.getPreferredLanguage();
    _loadChatHistory();
    // NOTE: the speech engine is deliberately NOT initialized here. On
    // Android that init triggers the OS microphone-permission prompt, so
    // it must happen only once the user is actually on the patient
    // dashboard (post-login) — the HomeScreen calls [initSpeech] there.
  }

  /// Warm up the speech engine (and surface the OS microphone-permission
  /// prompt on Android). Called by the patient dashboard right after
  /// login so the permission is asked at the right moment instead of at
  /// app startup. Idempotent and non-fatal.
  Future<void> initSpeech() => _initSpeech();

  Future<void> _initSpeech() async {
    if (_isInitializing) return;
    if (isInitialized.value) return;

    _isInitializing = true;
    isInitialized.value = false;
    try {
      final initialized = await _speechService.initialize();
      isInitialized.value = initialized;
      if (!initialized) {
        micError.value = 'Speech recognition not available';
      }
    } finally {
      _isInitializing = false;
    }
  }

  void _loadChatHistory() {
    final history = _storage.getChatHistory();

    debugPrint(
      '[VoiceController] Loading ${history.length} messages | '
      'analysis found: ${history.where((e) => e['analysis'] != null).length}',
    );

    messages.value = history.map((entry) {
      final rawAnalysis = entry['analysis'];

      // Restore analysis (specialist info) — defensive parsing with type-safe Map.from
      AiResponseModel? analysis;
      if (rawAnalysis != null && rawAnalysis is Map) {
        try {
          analysis = AiResponseModel.fromJson(
            Map<String, dynamic>.from(rawAnalysis),
          );
        } catch (_) {}
      }

      return ChatMessage(
        text: TextSanitizer.sanitize(entry['text']?.toString() ?? ''),
        isUser: entry['is_user'] as bool? ?? true,
        timestamp: entry['timestamp'] != null
            ? DateTime.tryParse(entry['timestamp'].toString()) ?? DateTime.now()
            : DateTime.now(),
        analysis: analysis,
      );
    }).toList();
  }

  void _saveChatHistory() {
    final data = messages.map((m) => m.toJson()).toList();
    _storage.saveChatHistory(data);
  }

  /// Start listening/recording based on the selected language.
  ///
  /// For **English**: uses device speech-to-text (fast, real-time).
  /// For **other languages**: starts recording audio which will be sent
  /// to OpenAI Whisper for more accurate transcription.
  Future<void> startListening() async {
    if (isListening.value || isProcessing.value || _isInitializing) return;

    // Ensure a clean start for both voice paths
    _resetVoiceState();

    if (_shouldUseWhisper) {
      await _startRecordingForWhisper();
    } else {
      await _startLocalStt();
    }
  }

  /// Start device speech-to-text (used for English).
  Future<void> _startLocalStt() async {
    // Re-initialize if previously failed
    if (!isInitialized.value) {
      micError.value = 'Initializing...';
      _isInitializing = false;
      await _initSpeech();
      if (!isInitialized.value) {
        micError.value = 'Speech recognition unavailable';
        return;
      }
    }

    micError.value = '';
    final locale =
        SpeechService.languageToLocale[_baseLanguage] ?? 'en_US';

    isListening.value = true;

    try {
      final started = await _speechService.startListening(
        onResult: (text) {
          // Final result received — auto-stop mic and process
          if (text.isNotEmpty) {
            final sanitized = TextSanitizer.sanitize(text);
            currentText.value = sanitized;
            isListening.value = false;

            // Notify the listening screen callback
            onVoiceResult?.call(sanitized);

            sendMessage(sanitized);
          }
        },
        onPartialResult: (text) {
          if (isListening.value) {
            final sanitized = TextSanitizer.sanitize(text);
            currentText.value = sanitized;

            // Notify the listening screen callback for real-time display
            onVoicePartialResult?.call(sanitized);
          }
        },
        onDone: () {
          // onDone fires when speech recognition ends without a final
          // result (silence timeout, listenFor timeout, or error).
          // Only send if we have accumulated partial text and aren't
          // already processing.
          isListening.value = false;
          if (currentText.value.isNotEmpty && !isProcessing.value) {
            final text = currentText.value;
            onVoiceResult?.call(text);
            sendMessage(text);
          }
        },
        onError: (error) {
          debugPrint('Speech error: $error');
          isListening.value = false;
          micError.value = error;
        },
        localeId: locale,
      );

      if (!started) {
        isListening.value = false;
        micError.value = 'Could not start listening';
      }
    } catch (e) {
      isListening.value = false;
      micError.value = 'Speech error occurred. Please try again.';
      debugPrint('startListening error: $e');
    }
  }

  /// Start recording audio for Whisper API transcription.
  Future<void> _startRecordingForWhisper() async {
    micError.value = '';
    isRecordingAudio.value = true;
    isListening.value = true;
    currentText.value = '';

    final started = await _audioService.startRecording();
    if (!started) {
      isListening.value = false;
      isRecordingAudio.value = false;
      micError.value =
          'Could not start recording. Please check microphone permissions.';
    }
  }

  /// Stop listening/recording.
  ///
  /// For English: cancels the device STT.
  /// For other languages: stops recording and transcribes via Whisper.
  Future<void> stopListening() async {
    if (_shouldUseWhisper) {
      await _stopRecordingAndTranscribe();
    } else {
      _cancelLocalStt();
    }
  }

  /// Cancel device speech-to-text.
  void _cancelLocalStt() {
    isListening.value = false;
    try {
      _speechService.stopListening();
    } catch (_) {}
    // Don't clear currentText here — let the status bar display
    // the last transcribed text for a moment.
  }

  /// Stop recording and send the audio to OpenAI Whisper for
  /// transcription, then process the result.
  Future<void> _stopRecordingAndTranscribe() async {
    if (!isRecordingAudio.value) return;

    isRecordingAudio.value = false;
    isTranscribing.value = true; // Show "Transcribing via AI..."
    micError.value = '';

    try {
      final result = await _audioService.stopAndTranscribe(
        languageCode: _baseLanguage,
      );

      isTranscribing.value = false;

      if (result.success && result.text != null && result.text!.isNotEmpty) {
        final sanitized = TextSanitizer.sanitize(result.text!);
        currentText.value = sanitized;
        isListening.value = false;
        await sendMessage(sanitized);
      } else {
        isListening.value = false;
        micError.value =
            result.error ?? 'Could not understand audio. Please try again.';
      }
    } catch (e) {
      isTranscribing.value = false;
      isListening.value = false;
      micError.value = 'Transcription failed. Please try again.';
      debugPrint('Whisper transcription error: $e');
    }
  }


  /// Reset all voice-related UI states to their defaults.
  /// Call this before starting a new voice session.
  void _resetVoiceState() {
    isListening.value = false;
    isRecordingAudio.value = false;
    isTranscribing.value = false;
    currentText.value = '';
    micError.value = '';
    // Don't reset isProcessing — let sendMessage handle that.
  }

  /// Send a text message through the AI analysis pipeline.
  ///
  /// 1. Adds the user message to chat.
  /// 2. Translates to English if needed.
  /// 3. Analyzes symptoms via AI.
  /// 4. Adds the AI response to chat.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (isProcessing.value) return;

    isListening.value = false;
    isRecordingAudio.value = false;
    isTranscribing.value = false;
    micError.value = '';

    // Add user message
    final userMessage = ChatMessage(text: text.trim(), isUser: true);
    messages.add(userMessage);
    _saveChatHistory();

    // Process with AI
    isProcessing.value = true;
    aiResponseText.value = '';
    recommendedDoctors.clear();

    try {
      // Translate if not English
      String analysisText = text.trim();
      if (_baseLanguage != 'en') {
        analysisText = await _aiService.translateToEnglish(
          text.trim(),
          _baseLanguage,
        );
      }

      // Analyze symptoms
      final analysis = await _aiService.analyzeSymptoms(analysisText);
      latestAnalysis.value = analysis;

      // Build response text
      final responseText = _buildResponseText(analysis);
      aiResponseText.value = responseText;

      // Add AI message
      final aiMessage = ChatMessage(
        text: responseText,
        isUser: false,
        analysis: analysis,
      );
      messages.add(aiMessage);
      _saveChatHistory();

      // Automatically fetch recommended doctors based on the specialist
      // identified by the AI.  isProcessing remains true while the
      // fetch is in flight so the shimmer bubble shows the status
      // label "Finding nearby specialists..." and transitions smoothly
      // to doctor cards once complete.
      if (analysis.specialist.isNotEmpty &&
          analysis.specialist != 'General Physician') {
        await _fetchRecommendedDoctors(analysis.specialist, analysis.symptoms);
      }
    } catch (e) {
      final errorMsg = ChatMessage(
        text: 'I apologize, but I encountered an error. Please try again.',
        isUser: false,
      );
      messages.add(errorMsg);
      _saveChatHistory();
    } finally {
      isProcessing.value = false;
    }
  }

  /// Fetch doctors matching the recommended specialist and store them
  /// in [recommendedDoctors] for inline card display.
  Future<void> _fetchRecommendedDoctors(String specialist, List<String> symptoms) async {
    if (isLoadingDoctors.value) return;
    isLoadingDoctors.value = true;

    try {
      final radius = _storage.getSearchRadiusKm() * 1000;
      final result = await _placesService.searchNearbyHealthcare(
        specialization: specialist,
        radius: radius,
        symptoms: symptoms,
      );

      if (result.doctors.isNotEmpty) {
        // Take top 3 recommendations to avoid overwhelming the chat
        recommendedDoctors.value = result.doctors.take(3).toList();
      }
    } catch (_) {
      // Silently fail — the user can still tap "Find near me"
    } finally {
      isLoadingDoctors.value = false;
    }
  }

  String _buildResponseText(AiResponseModel analysis) {
    final buffer = StringBuffer();

    buffer.writeln('🩺 Health Analysis');
    buffer.writeln('');
    buffer.writeln('📋 Identified Symptoms: ${TextSanitizer.sanitize(analysis.symptoms.join(", "))}');
    buffer.writeln('');
    buffer.writeln('🩺 Recommended Specialist: ${TextSanitizer.sanitize(analysis.specialist)}');

    if (analysis.explanation != null && analysis.explanation!.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('💡 ${TextSanitizer.sanitize(analysis.explanation!)}');
    }

    return buffer.toString();
  }

  void setLanguage(String languageCode) {
    final normalized = AppConstants.resolveLanguageCode(languageCode);
    selectedLanguage.value = normalized;
    _storage.setPreferredLanguage(normalized);
  }

  void clearChat() {
    messages.clear();
    latestAnalysis.value = null;
    aiResponseText.value = '';
    currentText.value = '';
    micError.value = '';
    _storage.clearChatHistory();
  }

  /// Cancel any current listening/recording without triggering the
  /// normal completion callbacks.  Used when the listening screen is
  /// dismissed mid-flow.
  void cancelCurrentListening() {
    isListening.value = false;
    isRecordingAudio.value = false;
    isTranscribing.value = false;
    try {
      _speechService.stopListening();
      _speechService.cancel();
      _audioService.cancel();
    } catch (_) {}
  }

  @override
  void onClose() {
    try {
      _speechService.stopListening();
      _speechService.cancel();
      _audioService.cancel();
      _audioService.dispose();
    } catch (_) {}
    super.onClose();
  }
}
