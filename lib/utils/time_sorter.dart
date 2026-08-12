/// Shared helpers for sorting appointment time strings by REAL clock time.
///
/// A raw string compare mis-orders 12-hour times: `"10:00 AM"` would sort
/// before `"9:00 AM"` because `'1' < '9'`. These helpers convert to minutes
/// since midnight so chronological ordering is always correct.
library;

/// Convert a 12-hour time string (e.g. `"9:00 AM"`, `"02:30 PM"`) to total
/// minutes since midnight.
///
/// Returns 0 for unparseable input so malformed times sort to the top of an
/// ascending list without throwing.
int timeToMinutes(String time12h) {
  final parts = time12h.trim().split(' ');
  if (parts.length != 2) return 0;
  final hm = parts[0].split(':');
  final h = int.tryParse(hm[0]) ?? 0;
  final m = int.tryParse(hm.length > 1 ? hm[1] : '0') ?? 0;
  final isPM = parts[1].toUpperCase() == 'PM';
  final h24 = h == 12 ? (isPM ? 12 : 0) : (isPM ? h + 12 : h);
  return h24 * 60 + m;
}

/// Compare two 12-hour time strings by real clock time (ascending).
int compareTimeStrings(String a, String b) {
  return timeToMinutes(a).compareTo(timeToMinutes(b));
}
