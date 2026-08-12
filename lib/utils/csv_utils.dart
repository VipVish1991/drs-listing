/// Shared CSV-building helpers used by the export utilities (payment
/// history CSV, patient-history CSV). Pure and testable: no I/O, no
/// platform channels.
library;

/// Joins [fields] into one CSV line with RFC 4180 escaping.
String csvRow(List<String> fields) => fields.map(csvEscape).join(',');

/// RFC 4180 escaping: quote fields containing a comma, quote, or line
/// break, and double any inner quotes.
String csvEscape(String field) {
  if (field.contains(',') ||
      field.contains('"') ||
      field.contains('\n') ||
      field.contains('\r')) {
    return '"${field.replaceAll('"', '""')}"';
  }
  return field;
}

/// dd-MM-yyyy (the app-wide display format).
String csvDateLabel(DateTime time) {
  final d = time.day.toString().padLeft(2, '0');
  final m = time.month.toString().padLeft(2, '0');
  return '$d-$m-${time.year}';
}
