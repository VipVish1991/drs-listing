import '../utils/text_sanitizer.dart';

class AiResponseModel {
  final String specialist;
  final List<String> symptoms;
  final String? explanation;
  final String? severity;
  final String? recommendation;

  AiResponseModel({
    required this.specialist,
    required this.symptoms,
    this.explanation,
    this.severity,
    this.recommendation,
  });

  factory AiResponseModel.fromJson(Map<String, dynamic> json) {
    return AiResponseModel(
      specialist:
          TextSanitizer.sanitize(json['specialist']?.toString() ?? 'General Physician'),
      symptoms: (json['symptoms'] as List?)
              ?.map((e) => TextSanitizer.sanitize(e?.toString() ?? ''))
              .toList() ??
          [],
      explanation: json['explanation']?.toString() != null
          ? TextSanitizer.sanitize(json['explanation']!.toString())
          : null,
      severity: json['severity']?.toString() != null
          ? TextSanitizer.sanitize(json['severity']!.toString())
          : null,
      recommendation: json['recommendation']?.toString() != null
          ? TextSanitizer.sanitize(json['recommendation']!.toString())
          : null,
    );
  }

  factory AiResponseModel.fromText(String text) {
    // Parse AI response text
    final specialist = TextSanitizer.sanitize(_extractSpecialist(text));
    final symptoms =
        _extractSymptoms(text).map(TextSanitizer.sanitize).toList();
    return AiResponseModel(
      specialist: specialist,
      symptoms: symptoms,
      explanation: TextSanitizer.sanitize(text),
      recommendation: 'Please consult a $specialist for proper diagnosis.',
    );
  }

  /// Removes surrounding double-quotes and any escaped quotes from a
  /// raw extracted value.  Handles both `"Cardiologist"` (plain JSON)
  /// and `\"Cardiologist\"` (escaped within a string).
  static String _stripQuotes(String value) {
    return value
        .replaceAll('\\"', '')
        .replaceAll('"', '')
        .trim();
  }

  static String _extractSpecialist(String text) {
    final patterns = [
      RegExp(r'specialist[:\s]+([^.\r\n]+)', caseSensitive: false),
      RegExp(r'recommend[:\s]+([^.\r\n]+)', caseSensitive: false),
      RegExp(r'consult[:\s]+([^.\r\n]+)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final raw = match.group(1)?.trim();
        if (raw != null && raw.isNotEmpty) {
          return _stripQuotes(raw);
        }
      }
    }
    return 'General Physician';
  }

  static List<String> _extractSymptoms(String text) {
    final match = RegExp(
      r'symptoms[:\s]+([^.\r\n]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      return match
              .group(1)
              ?.split(',')
              .map((s) => _stripQuotes(s))
              .where((s) => s.isNotEmpty)
              .toList() ??
          [];
    }
    return [];
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final AiResponseModel? analysis;

  ChatMessage({
    required String text,
    required this.isUser,
    DateTime? timestamp,
    this.analysis,
  })  : text = TextSanitizer.sanitize(text),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'is_user': isUser,
      'timestamp': timestamp.toIso8601String(),
      if (analysis != null)
        'analysis': {
          'specialist': analysis!.specialist,
          'symptoms': analysis!.symptoms,
        },
    };
  }
}
