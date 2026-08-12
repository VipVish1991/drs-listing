import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/utils/text_capitalizer.dart';

void main() {
  group('capitalizeWords', () {
    // ── Basic cases ──────────────────────────────────────────────

    test('capitalizes first letter of every word', () {
      expect(capitalizeWords('john smith'), 'John Smith');
    });

    test('handles single word', () {
      expect(capitalizeWords('hello'), 'Hello');
    });

    test('handles already capitalized input', () {
      // Should be idempotent
      expect(capitalizeWords('John Smith'), 'John Smith');
    });

    test('handles ALL CAPS input', () {
      expect(capitalizeWords('JOHN SMITH'), 'John Smith');
    });

    test('handles mixed case input', () {
      expect(capitalizeWords('jOhN sMiTh'), 'John Smith');
    });

    // ── Edge cases ───────────────────────────────────────────────

    test('returns empty string for null', () {
      expect(capitalizeWords(null), '');
    });

    test('returns empty string for empty string', () {
      expect(capitalizeWords(''), '');
    });

    test('returns empty string for whitespace-only', () {
      expect(capitalizeWords('   '), '');
    });

    test('collapses multiple spaces between words', () {
      expect(capitalizeWords('john    smith'), 'John Smith');
    });

    test('trims leading whitespace', () {
      expect(capitalizeWords('  john smith'), 'John Smith');
    });

    test('trims trailing whitespace', () {
      expect(capitalizeWords('john smith  '), 'John Smith');
    });

    test('handles newlines and tabs', () {
      expect(capitalizeWords('john\nsmith\tjane'), 'John Smith Jane');
    });

    test('handles single character', () {
      expect(capitalizeWords('a'), 'A');
    });

    test('handles single character repeated', () {
      expect(capitalizeWords('a b c'), 'A B C');
    });

    // ── Dr. prefix preservation ──────────────────────────────────

    test('preserves Dr. prefix', () {
      expect(capitalizeWords('dr. john smith'), 'Dr. John Smith');
    });

    test('preserves Dr prefix without period', () {
      expect(capitalizeWords('dr john smith'), 'Dr John Smith');
    });

    test('handles Dr. at the start of the name', () {
      expect(capitalizeWords('dr. nikhil motiramani'), 'Dr. Nikhil Motiramani');
    });

    test('handles Dr in the middle of text', () {
      // This is an unusual edge case — "dr" in the middle gets lowercased
      // by _capitalizeOne, which is the expected behavior since it's not
      // a standalone word boundary match
      expect(capitalizeWords('call dr smith'), 'Call Dr Smith');
    });

    // ── Hyphenated words ─────────────────────────────────────────

    test('capitalizes each part of hyphenated words', () {
      expect(capitalizeWords('in-clinic consultation'), 'In-Clinic Consultation');
    });

    test('handles multiple hyphens in one word', () {
      expect(capitalizeWords('up-to-date'), 'Up-To-Date');
    });

    // ── Numbers and symbols ──────────────────────────────────────

    test('preserves numbers in text', () {
      expect(capitalizeWords('room 101'), 'Room 101');
    });

    test('handles addresses with numbers', () {
      expect(capitalizeWords('123 main street'), '123 Main Street');
    });

    test('handles text with apostrophes', () {
      // _capitalizeOne lowercases all chars after the first, so
      // "O'Brien" → "O'brien" (the 'B' after apostrophe becomes 'b')
      expect(capitalizeWords("o'brien clinic"), "O'brien Clinic");
    });

    // ── Non-ASCII text ───────────────────────────────────────────

    test('handles Devanagari text (unchanged)', () {
      // Devanagari characters are not affected by toUpperCase/toLowerCase
      expect(capitalizeWords('राज स्वास्थ्य अस्पताल'),
          'राज स्वास्थ्य अस्पताल');
    });

    // ── Real-world use cases ─────────────────────────────────────

    test('handles full patient name', () {
      expect(capitalizeWords('john doe'), 'John Doe');
    });

    test('handles doctor name', () {
      expect(capitalizeWords('dr. nikhil motiramani dm cardiologist'),
          'Dr. Nikhil Motiramani Dm Cardiologist');
      // Note: "DM" → "Dm" because _capitalizeOne lowercases trailing chars.
      // This is the expected behavior for user-entered text.
    });

    test('handles symptoms', () {
      expect(capitalizeWords('chest pain and shortness of breath'),
          'Chest Pain And Shortness Of Breath');
    });

    test('handles address with comma', () {
      // Commas are attached to the preceding word, so "street," keeps the comma
      expect(capitalizeWords('123 main street, new york'),
          '123 Main Street, New York');
    });

    test('handles address with hyphenated area', () {
      expect(capitalizeWords('sector 1 shankar nagar'),
          'Sector 1 Shankar Nagar');
    });

    test('handles hospital name', () {
      expect(capitalizeWords('raj health hospital'), 'Raj Health Hospital');
    });

    // ── Common words in English ──────────────────────────────────

    test('capitalizes lowercase single characters properly', () {
      expect(capitalizeWords('a b c d'), 'A B C D');
    });

    // ── Edge: very long strings ──────────────────────────────────

    test('handles long strings without crashing', () {
      final long = List.filled(100, 'word').join(' ');
      final result = capitalizeWords(long);
      expect(result, List.filled(100, 'Word').join(' '));
    });

    // ── Edge: special characters only ────────────────────────────

    test('handles text with only special characters', () {
      // Symbols become uppercased first char, but toLowerCase doesn't affect them
      expect(capitalizeWords('!!!'), '!!!');
    });

    test('handles text with possessive apostrophe', () {
      // The apostrophe-s is lowercased by _capitalizeOne
      expect(capitalizeWords("doctor's clinic"), "Doctor's Clinic");
    });

    // ── Edge: word with numbers only ─────────────────────────────

    test('handles numeric-only words', () {
      // _capitalizeOne only uppercases first char; the 'b' stays lowercase
      expect(capitalizeWords('room 101b'), 'Room 101b');
    });
  });
}
