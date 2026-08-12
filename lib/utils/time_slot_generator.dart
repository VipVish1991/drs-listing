/// Generates a list of bookable time slots between [start] and [end]
/// (both 24h "HH:MM" strings), spaced [durationMinutes] apart, formatted
/// in 12-hour clock with AM/PM — e.g. "09:00 AM", "09:30 AM".
///
/// Returns an empty list for an invalid or zero-length range instead of
/// throwing, so callers can render "No slots" without extra guards.
List<String> generateTimeSlots(String start, String end, int durationMinutes) {
  if (durationMinutes <= 0) return [];

  final startMinutes = _toMinutes(start);
  final endMinutes = _toMinutes(end);
  if (startMinutes == null ||
      endMinutes == null ||
      endMinutes <= startMinutes) {
    return [];
  }

  final slots = <String>[];
  for (
    var m = startMinutes;
    m + durationMinutes <= endMinutes;
    m += durationMinutes
  ) {
    slots.add(_formatMinutes(m));
  }
  return slots;
}

/// Converts a 24h "HH:MM" string to a 12h "h:mm AM/PM" display string.
String to12h(String time24) {
  final parts = time24.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? parts[1] : '00';
  final ampm = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m $ampm';
}

int? _toMinutes(String time24) {
  final parts = time24.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _formatMinutes(int totalMinutes) {
  final h = (totalMinutes ~/ 60) % 24;
  final m = totalMinutes % 60;
  final time24 =
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  return to12h(time24);
}
