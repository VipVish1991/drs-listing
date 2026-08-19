import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/ai_response_model.dart';

class AiService {
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;
  AiService._internal();

  Future<AiResponseModel> analyzeSymptoms(String userMessage) async {
    // 1. Try Groq first (free, no credit card needed)
    final groq = await _analyzeWithProvider(
      userMessage,
      AppConstants.groqBaseUrl,
      AppConstants.groqApiKey,
      AppConstants.groqModel,
    );
    if (groq != null) return groq;

    // 2. Last resort: local keyword-based analysis
    return _localAnalysis(userMessage);
  }

  /// Shared symptom-analysis helper.
  Future<AiResponseModel?> _analyzeWithProvider(
    String message,
    String baseUrl,
    String apiKey,
    String model,
  ) async {
    if (apiKey.isEmpty) return null;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': _systemPrompt(),
            },
            {'role': 'user', 'content': message},
          ],
          'temperature': 0.3,
          'max_tokens': 1500,
          'reasoning_effort': 'low',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;

        // Strip markdown code-block fences and <think> tags that some models wrap JSON in
        String cleaned = content.trim();

        // Remove <think>...</think> blocks (Qwen, etc.)
        final thinkStart = cleaned.indexOf('<think>');
        if (thinkStart != -1) {
          final thinkEnd = cleaned.indexOf('</think>', thinkStart);
          if (thinkEnd != -1) {
            cleaned = (cleaned.substring(0, thinkStart) + cleaned.substring(thinkEnd + 9)).trim();
          }
        }

        if (cleaned.startsWith('```')) {
          // Remove opening ```json or ``` and any trailing ```
          final firstNewline = cleaned.indexOf('\n');
          if (firstNewline != -1) {
            cleaned = cleaned.substring(firstNewline + 1);
          }
          if (cleaned.endsWith('```')) {
            cleaned = cleaned.substring(0, cleaned.length - 3);
          }
          cleaned = cleaned.trim();
        }

        try {
          final jsonContent = jsonDecode(cleaned);
          return AiResponseModel.fromJson(jsonContent as Map<String, dynamic>);
        } catch (_) {
          return AiResponseModel.fromText(content);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Shared system prompt used by both OpenAI and Groq.
  String _systemPrompt() {
    return 'You are a medical symptom analysis AI. Analyze the user\'s symptom description and respond ONLY in valid JSON with these exact keys: specialist, symptoms, explanation, severity, recommendation.\n'
        '\n'
        '--- EXAMPLE OUTPUT ---\n'
        '{\n'
        '  "specialist": "Cardiologist",\n'
        '  "symptoms": ["chest pain", "shortness of breath"],\n'
        '  "explanation": "Your chest pain and shortness of breath could indicate a heart-related issue. A cardiologist can perform the necessary tests to rule out serious conditions.",\n'
        '  "severity": "moderate",\n'
        '  "recommendation": "Please consult a Cardiologist as soon as possible. If the pain worsens or spreads to your arm/jaw, call emergency services immediately."\n'
        '}\n'
        '---\\n'
        '\n'
        'CRITICAL — Map the user\'s symptoms to the most appropriate specialist. Use this guide:\n'
        '\n'
        '❤️  Cardiology: chest pain, heart issues, blood pressure, palpitations, fainting, high/low BP → Cardiologist\n'
        '🧠  Neurology: headache, migraine, dizziness, seizures, paralysis, memory loss, numbness → Neurologist\n'
        '🦴  Orthopedics: back/neck/joint/knee/shoulder pain, bone, fracture, injury, sprain → Orthopedic\n'
        '🫁  Pulmonology: breathing problems, asthma, respiratory issues, tuberculosis, cough >3 weeks → Pulmonologist\n'
        '🫀  Gastroenterology: stomach pain, acidity, indigestion, vomiting, nausea, diarrhea, constipation, jaundice, liver issues → Gastroenterologist\n'
        '🩺  General Physician: fever, cold, cough, body pain, weakness, fatigue, dehydration, general checkup, dengue/malaria/typhoid symptoms → General Physician\n'
        '🩹  Dermatology: skin rash, allergy, itching, acne, hair fall, dandruff → Dermatologist\n'
        '👁️  Ophthalmology: eye pain, redness, vision problems, blurred vision → Ophthalmologist\n'
        '👂  ENT: ear pain, hearing loss, sore throat, sinus, nose bleeding, snoring → ENT Specialist\n'
        '🦷  Dentistry: tooth pain, dental issues, gum problems → Dentist\n'
        '🍬  Diabetology: diabetes, blood sugar issues → Diabetologist\n'
        '🦋  Endocrinology: thyroid, hormone issues, weight gain/loss → Endocrinologist\n'
        '🤰  Gynecology: pregnancy, period, menstrual problems, pcos, infertility → Gynecologist\n'
        '🚻  Urology: urine issues, burning/frequent urination, urinary infection → Urologist\n'
        '🫘  Nephrology: kidney problems, kidney pain → Nephrologist\n'
        '🧠  Psychiatry: mental health, stress, anxiety, depression, sleep problems, insomnia → Psychiatrist\n'
        '👶  Pediatrics: child, baby, vaccination, growth issues → Pediatrician\n'
        '🎗  Oncology: cancer, tumor, unusual lumps, unexplained weight loss → Oncologist\n'
        '🛡️  Immunology: recurring infections, low immunity → Immunologist\n'
        '💕  Sexology: sexual health, erectile dysfunction → Sexologist\n'
        '🔥  General Surgery: burns, wounds requiring surgery → General Surgeon\n'
        '\n'
        'SEVERITY guidelines (use one of: mild / moderate / emergency):\n'
        '- mild: common cold, minor headache, indigestion, small cuts\n'
        '- moderate: persistent fever >3 days, recurring pain, chronic conditions\n'
        '- emergency: chest pain, difficulty breathing, seizures, unconsciousness, severe bleeding, suspected stroke/heart attack — add urgent disclaimer\n'
        '\n'
        'NEVER default to General Physician unless the symptoms truly have no specific match. Be accurate and responsible. Always recommend consulting a real doctor. For emergency symptoms, include an urgent care disclaimer.';
  }

  String _resolveSpecialist(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }

    if (value is Map) {
      for (final key in ['specialist', 'doctor', 'name', 'type']) {
        final candidate = value[key];
        if (candidate is String && candidate.isNotEmpty) {
          return candidate;
        }
      }
    }

    return 'General Physician';
  }

  AiResponseModel _localAnalysis(String message) {
    final lowerMessage = message.toLowerCase();
    final symptoms = <String>[];
    String specialist = 'General Physician';

    // Check for matching symptoms
    for (final entry in AppConstants.symptomToSpecialist.entries) {
      if (lowerMessage.contains(entry.key)) {
        symptoms.add(entry.key);
        final resolvedSpecialist = _resolveSpecialist(entry.value);
        if (resolvedSpecialist != 'General Physician') {
          specialist = resolvedSpecialist;
        }
      }
    }

    // Determine severity
    String severity = 'mild';
    if (lowerMessage.contains('severe') ||
        lowerMessage.contains('emergency') ||
        lowerMessage.contains('unconscious') ||
        lowerMessage.contains('chest pain') ||
        lowerMessage.contains('difficulty breathing') ||
        lowerMessage.contains('heart attack') ||
        lowerMessage.contains('stroke') ||
        lowerMessage.contains('bleeding heavily') ||
        lowerMessage.contains('heavy bleeding')) {
      severity = 'emergency';
    } else if (lowerMessage.contains('high') ||
        lowerMessage.contains('extreme') ||
        lowerMessage.contains('chronic') ||
        lowerMessage.contains('persistent')) {
      severity = 'moderate';
    }

    return AiResponseModel(
      specialist: specialist,
      symptoms: symptoms.isNotEmpty ? symptoms : ['General discomfort'],
      severity: severity,
      recommendation: 'Please consult a $specialist for proper diagnosis.',
    );
  }

  Future<String> translateToEnglish(String text, String sourceLanguage) async {
    // 1. Try Groq
    final groqResult = await _translateWithProvider(
      text,
      AppConstants.groqBaseUrl,
      AppConstants.groqApiKey,
      AppConstants.groqModel,
    );
    if (groqResult != null) return groqResult;

    // 2. Return original text if translation fails
    return text;
  }

  /// Shared translation helper.
  Future<String?> _translateWithProvider(
    String text,
    String baseUrl,
    String apiKey,
    String model,
  ) async {
    if (apiKey.isEmpty) return null;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a translator. Translate the following text to English. Respond only with the translated text, nothing else.',
            },
            {'role': 'user', 'content': text},
          ],
          'temperature': 0.1,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      }
    } catch (_) {}
    return null;
  }
}
