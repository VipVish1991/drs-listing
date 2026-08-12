import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:record/record.dart';
import '../config/constants.dart';

/// Result of an audio transcription attempt.
class TranscriptionResult {
  final bool success;
  final String? text;
  final String? error;

  TranscriptionResult({required this.success, this.text, this.error});
}

/// Service that records audio from the microphone and sends it to
/// OpenAI's Whisper API for transcription.
///
/// This is especially useful for Indian languages where the device's
/// built-in speech recognition may be inaccurate.
class AudioTranscriptionService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordedFilePath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Start recording audio.  The recording is saved to a temporary file.
  ///
  /// Returns `true` if recording started successfully.
  Future<bool> startRecording() async {
    if (_isRecording) return false;

    // Check microphone permission
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    try {
      // Create a unique temp file path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final dir = Directory.systemTemp;
      _recordedFilePath = '${dir.path}/voice_input_$timestamp.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
        ),
        path: _recordedFilePath!,
      );

      _isRecording = true;
      return true;
    } catch (e) {
      _recordedFilePath = null;
      return false;
    }
  }

  /// Stop recording and send the audio to OpenAI's Whisper API for
  /// transcription.
  ///
  /// [languageCode] is an optional ISO-639-1 language hint (e.g. `'hi'`,
  /// `'mr'`) that Whisper uses to improve accuracy.
  Future<TranscriptionResult> stopAndTranscribe({
    String? languageCode,
  }) async {
    if (!_isRecording) {
      return TranscriptionResult(
        success: false,
        error: 'Not recording',
      );
    }

    _isRecording = false;

    String? filePath;
    try {
      filePath = await _recorder.stop();
    } catch (e) {
      return TranscriptionResult(
        success: false,
        error: 'Failed to stop recording',
      );
    }

    // Use the stored path if the recorder didn't return one
    filePath ??= _recordedFilePath;

    if (filePath == null || !File(filePath).existsSync()) {
      return TranscriptionResult(
        success: false,
        error: 'No audio file found',
      );
    }

    final file = File(filePath);
    if (await file.length() < 100) {
      // Too short or empty – probably no speech detected
      await file.delete();
      _recordedFilePath = null;
      return TranscriptionResult(
        success: false,
        error: 'No speech detected',
      );
    }

    try {
      final transcribed = await _transcribeWithWhisper(file, languageCode);
      return transcribed;
    } catch (e) {
      return TranscriptionResult(
        success: false,
        error: 'Transcription failed: $e',
      );
    } finally {
      // Clean up the temp file
      try {
        await file.delete();
      } catch (_) {}
      _recordedFilePath = null;
    }
  }

  /// Cancel an ongoing recording without processing.
  Future<void> cancel() async {
    _isRecording = false;
    try {
      await _recorder.stop();
    } catch (_) {}
    if (_recordedFilePath != null) {
      final file = File(_recordedFilePath!);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      _recordedFilePath = null;
    }
  }

  /// Release the recorder resources.
  void dispose() {
    _recorder.dispose();
  }

  // ── Private helpers ───────────────────────────────────────────────

  /// Send the audio file to Groq's Whisper-compatible API for transcription.
  ///
  /// [languageCode] is an optional ISO-639-1 language hint sent to Whisper
  /// so it can better specialise on the spoken language.
  Future<TranscriptionResult> _transcribeWithWhisper(
    File audioFile, [
    String? languageCode,
  ]) async {
    final apiKey = AppConstants.groqApiKey;
    if (apiKey.isEmpty) {
      return TranscriptionResult(
        success: false,
        error: 'Groq API key not configured',
      );
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConstants.groqBaseUrl}/audio/transcriptions'),
    );

    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = 'whisper-large-v3-turbo';
    request.fields['response_format'] = 'json';

    // Pass the language hint so Whisper can specialise on the spoken
    // language.  Whisper accepts ISO-639-1 two-letter codes.
    if (languageCode != null && languageCode.isNotEmpty) {
      request.fields['language'] = languageCode;
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        audioFile.path,
        contentType: MediaType('audio', 'm4a'),
      ),
    );

    try {
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(responseBody);
        final text = decoded['text'] as String? ?? '';
        if (text.trim().isEmpty) {
          return TranscriptionResult(
            success: false,
            error: 'No speech detected',
          );
        }
        return TranscriptionResult(success: true, text: text.trim());
      } else {
        return TranscriptionResult(
          success: false,
          error: 'Whisper API error (${response.statusCode}): $responseBody',
        );
      }
    } catch (e) {
      return TranscriptionResult(
        success: false,
        error: 'Network error: $e',
      );
    }
  }
}
