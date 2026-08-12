/// Utility to sanitize text strings before rendering in Text widgets.
///
/// Some external data sources (AI responses, speech transcription) can
/// produce strings with invalid UTF-16 surrogate pairs that crash the
/// Flutter text renderer with "string is not well-formed UTF-16".
class TextSanitizer {
  /// Removes orphaned UTF-16 surrogates (high without low or vice versa)
  /// from [input].
  ///
  /// Also strips the ZWJ (Zero Width Joiner, U+200D) and Variation
  /// Selectors (U+FE0F-U+FE0F) when they appear in an invalid context —
  /// some Android font configurations can't render complex emoji ZWJ
  /// sequences and crash during text layout.
  static String sanitize(String? input) {
    if (input == null || input.isEmpty) return input ?? '';

    final output = StringBuffer();
    final runes = input.runes.toList(growable: false);

    for (int i = 0; i < runes.length; i++) {
      final code = runes[i];

      // Skip orphaned high surrogates (0xD800–0xDBFF without a following low)
      if (code >= 0xD800 && code <= 0xDBFF) {
        if (i + 1 >= runes.length || runes[i + 1] < 0xDC00 || runes[i + 1] > 0xDFFF) {
          output.write('\uFFFD'); // replacement character
          continue;
        }
      }

      // Skip orphaned low surrogates (0xDC00–0xDFFF without a preceding high)
      if (code >= 0xDC00 && code <= 0xDFFF) {
        if (i == 0 || runes[i - 1] < 0xD800 || runes[i - 1] > 0xDBFF) {
          output.write('\uFFFD');
          continue;
        }
      }

      // Replace variation selectors that are not attached to a valid base
      if (code >= 0xFE00 && code <= 0xFE0F) {
        if (i == 0) continue; // orphaned VS → skip
        // Keep if preceded by an emoji character
        final prev = runes[i - 1];
        if (prev < 0x2600 && prev != 0x200D) continue;
      }

      output.writeCharCode(code);
    }

    return output.toString();
  }
}
