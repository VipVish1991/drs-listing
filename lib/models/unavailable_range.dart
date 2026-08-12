/// One inclusive date range when a doctor is unavailable, e.g.
/// 2026-08-10 → 2026-08-12 (leave, holiday, travel).
///
/// Persisted as a JSON object inside the doctors table's
/// `unavailable_ranges` JSONB array: `{"start":"YYYY-MM-DD","end":"YYYY-MM-DD"}`.
class UnavailableRange {
  /// Start of the range (date-only; time of day is ignored).
  final DateTime start;

  /// End of the range (date-only; time of day is ignored). Always >= [start].
  final DateTime end;

  /// Both endpoints are normalized to midnight (date-only), so a range
  /// built from e.g. `DateTime.now()` still contains its own start/end
  /// dates — time-of-day must never leak into the date math.
  UnavailableRange({required DateTime start, required DateTime end})
    : start = DateTime(start.year, start.month, start.day),
      end = DateTime(end.year, end.month, end.day);

  /// True when [date] falls inside this range (inclusive of both ends).
  bool contains(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// True when the range covers today — drives the doctor profile's
  /// "Available / Unavailable" status button.
  bool get isActive => contains(DateTime.now());

  /// Parses one range object. A reversed range (start after end) is
  /// normalized by swapping instead of throwing.
  factory UnavailableRange.fromJson(Map<String, dynamic> json) {
    var start = _parseDate(json['start']);
    var end = _parseDate(json['end']);
    if (start.isAfter(end)) {
      final tmp = start;
      start = end;
      end = tmp;
    }
    return UnavailableRange(start: start, end: end);
  }

  Map<String, dynamic> toJson() => {'start': _fmt(start), 'end': _fmt(end)};

  /// Human label like "10 Aug 2026 – 12 Aug 2026".
  String get label => '${_ddMMM(start)} – ${_ddMMM(end)}';

  /// Returns the subset of [isoDates] ('yyyy-MM-dd' keys) that fall inside
  /// any of [ranges]. Used by the booking screens to disable unavailable
  /// dates without re-parsing every date.
  static Set<String> matchingIsoDates(
    Iterable<String> isoDates,
    List<UnavailableRange> ranges,
  ) {
    if (ranges.isEmpty) return {};
    final matched = <String>{};
    for (final iso in isoDates) {
      final date = DateTime.tryParse(iso);
      if (date == null) continue;
      if (ranges.any((r) => r.contains(date))) matched.add(iso);
    }
    return matched;
  }

  /// Parses the `unavailable_ranges` JSONB array from the doctors table.
  /// Malformed entries are skipped so one bad row can't crash the UI.
  static List<UnavailableRange> listFromJson(Object? value) {
    if (value is! List) return const [];
    final ranges = <UnavailableRange>[];
    for (final item in value) {
      if (item is Map) {
        try {
          ranges.add(
            UnavailableRange.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {
          // Skip malformed entries.
        }
      }
    }
    return ranges;
  }

  static DateTime _parseDate(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return DateTime.now();
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _fmt(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String _ddMMM(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
