import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/utils/text_sanitizer.dart';

void main() {
  group('TextSanitizer.sanitize', () {
    test('returns empty string for null/empty input', () {
      expect(TextSanitizer.sanitize(null), '');
      expect(TextSanitizer.sanitize(''), '');
    });

    test('leaves well-formed text unchanged', () {
      const plain = 'Dr. Shashwat Kumar — Cardiologist';
      expect(TextSanitizer.sanitize(plain), plain);
    });

    test('replaces a lone high surrogate with U+FFFD', () {
      // \uD83D is a high surrogate with no matching low surrogate.
      final input = 'Broken \uD83D text';
      final out = TextSanitizer.sanitize(input);
      expect(out.contains('\uD83D'), isFalse, reason: 'lone high surrogate removed');
      expect(out, contains('Broken'));
      expect(out, contains('text'));
      expect(_hasUnpairedSurrogate(out), isFalse);
    });

    test('replaces a lone low surrogate with U+FFFD', () {
      // \uDE00 is a low surrogate with no matching high surrogate.
      final input = 'Broken \uDE00 text';
      final out = TextSanitizer.sanitize(input);
      expect(out.contains('\uDE00'), isFalse, reason: 'lone low surrogate removed');
      expect(_hasUnpairedSurrogate(out), isFalse);
    });

    test('preserves valid surrogate pairs (emoji)', () {
      // 😀 = \uD83D\uDE00 — a valid pair that must survive intact.
      const emoji = '\uD83D\uDE00';
      final out = TextSanitizer.sanitize('Feeling $emoji today');
      expect(out, contains(emoji));
      expect(_hasUnpairedSurrogate(out), isFalse);
    });

    test('sanitizes a whole string full of lone surrogates', () {
      final input = '\uD83D\uDE00\uD83D\uDE00bad\uD83D';
      final out = TextSanitizer.sanitize(input);
      expect(_hasUnpairedSurrogate(out), isFalse);
      expect(out, contains('bad'));
      expect(out, contains('\uD83D\uDE00')); // valid pair preserved
    });

    test('output is always render-safe (no unpaired surrogates anywhere)', () {
      final nasty = [
        '\uD800', // lone high
        '\uDFFF', // lone low
        'a\uDC00b', // lone low in middle
        '\uDBFF\uD800', // two highs
        '\uD83D\uDE00', // valid pair (safe)
        '😀 text 👍',
      ];
      for (final s in nasty) {
        final out = TextSanitizer.sanitize(s);
        expect(_hasUnpairedSurrogate(out), isFalse,
            reason: 'input "$s" → output must be render-safe');
      }
    });

    test('handles ZWJ emoji sequences without crashing', () {
      // 👨‍⚕️ doctor emoji (ZWJ sequence) should survive or be degraded
      // gracefully — never crash the layout.
      const doctor = '\u{1F468}\u200D\u2695\uFE0F';
      final out = TextSanitizer.sanitize('$doctor Consult a doctor');
      expect(_hasUnpairedSurrogate(out), isFalse);
      expect(out, isNotEmpty);
    });
  });
}

/// Returns true when [s] contains a UTF-16 code unit in the surrogate range
/// that is not part of a valid high+low pair — i.e. a string the Flutter
/// text engine would reject with "string is not well-formed UTF-16".
bool _hasUnpairedSurrogate(String s) {
  final units = s.codeUnits;
  for (int i = 0; i < units.length; i++) {
    final u = units[i];
    if (u >= 0xD800 && u <= 0xDBFF) {
      // High surrogate — must be followed by a low surrogate.
      if (i + 1 >= units.length) return true;
      final next = units[i + 1];
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++; // skip the low surrogate
    } else if (u >= 0xDC00 && u <= 0xDFFF) {
      return true; // lone low surrogate
    }
  }
  return false;
}
