/// Formats large counts into a compact, human-readable form so dashboard
/// stats stay scannable: 999 → "999", 1000 → "1K", 12300 → "12.3K",
/// 1000000 → "1M".
///
/// Uses a single decimal only when the fraction is meaningful and the
/// unit is below 10 (e.g. "1.5K", "1.2M"); larger units render whole
/// numbers ("12K", "123K", "10M").
String compactCount(num value) {
  if (value >= 1000000000) return '${_compact(value / 1000000000)}B';
  if (value >= 1000000) return '${_compact(value / 1000000)}M';
  if (value >= 1000) return '${_compact(value / 1000)}K';
  return value.round().toString();
}

/// Trims a scaled unit to its cleanest representation: "1.0" → "1",
/// "12.3" stays, "10.0" → "10".
String _compact(double unit) {
  final text = unit.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
