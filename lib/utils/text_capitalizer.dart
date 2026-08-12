/// Utility for capitalizing words in text before saving to the database.
///
/// Handles special cases:
/// - "Dr." / "Dr" prefix is preserved (not lowercased)
/// - null/empty strings return as-is
/// - Multiple spaces are collapsed
/// - Non-ASCII / Devanagari text is left unchanged
String capitalizeWords(String? text) {
  if (text == null || text.isEmpty) return text ?? '';

  // Split by whitespace, filter empty tokens
  final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);

  final capitalized = words.map((word) {
    // Don't touch empty strings
    if (word.isEmpty) return word;

    // Preserve "Dr." / "Dr" prefix as-is
    if (word == 'Dr.' || word == 'Dr') return word;

    // Handle hyphenated words like "in-clinic" → "In-Clinic"
    if (word.contains('-')) {
      return word.split('-').map((part) => _capitalizeOne(part)).join('-');
    }

    return _capitalizeOne(word);
  }).join(' ');

  return capitalized;
}

/// Capitalize a single word: first letter uppercase, rest lowercase.
/// Non-alphabetic first characters (numbers, symbols) are left as-is.
String _capitalizeOne(String word) {
  if (word.isEmpty) return word;
  if (word.length == 1) return word.toUpperCase();
  return word[0].toUpperCase() + word.substring(1).toLowerCase();
}
