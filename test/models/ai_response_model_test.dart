import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/models/ai_response_model.dart';
import '../helpers/test_data.dart';

void main() {
  group('AiResponseModel', () {
    group('fromJson', () {
      test('parses full JSON correctly', () {
        final json = {
          'specialist': 'Cardiologist',
          'symptoms': ['chest pain', 'shortness of breath'],
          'explanation': 'Possible heart issue.',
          'severity': 'moderate',
          'recommendation': 'Consult a cardiologist.',
        };

        final model = AiResponseModel.fromJson(json);

        expect(model.specialist, 'Cardiologist');
        expect(model.symptoms, ['chest pain', 'shortness of breath']);
        expect(model.explanation, 'Possible heart issue.');
        expect(model.severity, 'moderate');
        expect(model.recommendation, 'Consult a cardiologist.');
      });

      test('defaults specialist to General Physician when missing', () {
        final json = {
          'symptoms': ['fever'],
        };
        final model = AiResponseModel.fromJson(json);
        expect(model.specialist, 'General Physician');
      });

      test('defaults symptoms to empty list when missing', () {
        final json = {'specialist': 'Neurologist'};
        final model = AiResponseModel.fromJson(json);
        expect(model.symptoms, isEmpty);
      });

      test('handles null fields gracefully', () {
        final json = <String, dynamic>{};
        final model = AiResponseModel.fromJson(json);
        expect(model.specialist, 'General Physician');
        expect(model.symptoms, isEmpty);
        expect(model.explanation, isNull);
        expect(model.severity, isNull);
        expect(model.recommendation, isNull);
      });

      test('coerces specialist from non-String values', () {
        final json = {'specialist': 123};
        final model = AiResponseModel.fromJson(json);
        expect(model.specialist, '123'); // toString() on int
      });
    });

    group('fromText', () {
      test('extracts specialist from text pattern', () {
        final text = 'Recommended Specialist: Cardiologist';
        final model = AiResponseModel.fromText(text);
        expect(model.specialist, 'Cardiologist');
      });

      test('extracts specialist from "consult" pattern', () {
        final text = 'Please consult a Neurologist for proper diagnosis.';
        final model = AiResponseModel.fromText(text);
        // The regex captures everything after "consult " until a period/newline
        expect(model.specialist, 'a Neurologist for proper diagnosis');
      });

      test('extracts specialist from "recommend" pattern', () {
        final text = 'I recommend an Orthopedic for your joint pain.';
        final model = AiResponseModel.fromText(text);
        // The regex captures everything after "recommend " until a period/newline
        expect(model.specialist, 'an Orthopedic for your joint pain');
      });

      test(
        'falls back to General Physician when no specialist pattern found',
        () {
          final text = 'You seem to be healthy. Take rest.';
          final model = AiResponseModel.fromText(text);
          expect(model.specialist, 'General Physician');
        },
      );

      test('extracts symptoms from text pattern', () {
        final text = 'Symptoms: fever, cough, headache';
        final model = AiResponseModel.fromText(text);
        expect(model.symptoms, ['fever', 'cough', 'headache']);
      });

      test('returns empty symptoms when no pattern matches', () {
        final text = 'You have a fever.';
        final model = AiResponseModel.fromText(text);
        expect(model.symptoms, isEmpty);
      });

      test('preserves explanation text', () {
        final text = 'Symptoms: fever. Specialist: GP. You may have a cold.';
        final model = AiResponseModel.fromText(text);
        expect(model.explanation, text);
      });
    });

    group('edge cases', () {
      test('handles empty string in fromText', () {
        final model = AiResponseModel.fromText('');
        expect(model.specialist, 'General Physician');
        expect(model.symptoms, isEmpty);
      });

      test('handles symptoms with trailing spaces', () {
        final text = 'Symptoms: fever , cough ,  headache ';
        final model = AiResponseModel.fromText(text);
        expect(model.symptoms, ['fever', 'cough', 'headache']);
      });

      test('case-insensitive specialist matching', () {
        final text = 'SPECIALIST: cardiologist';
        final model = AiResponseModel.fromText(text);
        expect(model.specialist, 'cardiologist');
      });
    });
  });

  group('ChatMessage', () {
    test('creates a user message', () {
      final msg = ChatMessage(text: 'I have a headache', isUser: true);
      expect(msg.text, 'I have a headache');
      expect(msg.isUser, isTrue);
      expect(msg.analysis, isNull);
      expect(msg.timestamp, isA<DateTime>());
    });

    test('creates an AI message with analysis', () {
      final analysis = AiResponseModel(
        specialist: 'Neurologist',
        symptoms: ['headache'],
      );
      final msg = ChatMessage(
        text: 'See a neurologist',
        isUser: false,
        analysis: analysis,
      );
      expect(msg.text, 'See a neurologist');
      expect(msg.isUser, isFalse);
      expect(msg.analysis?.specialist, 'Neurologist');
    });

    test('defaults timestamp to now when not provided', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final msg = ChatMessage(text: 'test', isUser: true);
      final after = DateTime.now().add(const Duration(seconds: 1));
      expect(msg.timestamp.isAfter(before), isTrue);
      expect(msg.timestamp.isBefore(after), isTrue);
    });

    test('preserves provided timestamp', () {
      final ts = DateTime(2025, 1, 15, 10, 30);
      final msg = ChatMessage(text: 'test', isUser: true, timestamp: ts);
      expect(msg.timestamp, ts);
    });

    group('toJson', () {
      test('serializes user message without analysis', () {
        final msg = ChatMessage(text: 'Hello', isUser: true);
        final json = msg.toJson();
        expect(json['text'], 'Hello');
        expect(json['is_user'], isTrue);
        expect(json['timestamp'], isA<String>());
        expect(json.containsKey('analysis'), isFalse);
      });

      test('serializes AI message with analysis', () {
        final msg = ChatMessage(
          text: 'Response',
          isUser: false,
          analysis: analysisCardiologist(),
        );
        final json = msg.toJson();
        expect(json['is_user'], isFalse);
        expect(json['analysis'], isA<Map<String, dynamic>>());
        expect(json['analysis']['specialist'], 'Cardiologist');
        expect(json['analysis']['symptoms'], [
          'chest pain',
          'shortness of breath',
        ]);
      });

      test('serializes without analysis when null', () {
        final msg = ChatMessage(
          text: 'Response',
          isUser: false,
          analysis: null,
        );
        final json = msg.toJson();
        expect(json.containsKey('analysis'), isFalse);
      });
    });
  });
}
