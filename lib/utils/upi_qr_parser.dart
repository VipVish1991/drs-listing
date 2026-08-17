/// Parses the raw text a UPI QR-code scan produces into a payee VPA
/// (Virtual Payment Address, e.g. `patient@okhdfcbank`).
///
/// Real-world UPI QR codes come in a few shapes:
///   * `upi://pay?pa=name@upi&pn=…&am=…` (the standard UPI deep link —
///     also `phonepe://pay`, `paytm://pay`, `gpay://pay` …)
///   * a bare `name@bank` string
///
/// Returns the VPA, or null when the scan contains nothing that looks
/// like a UPI address (so the caller can tell the doctor to try again
/// instead of paying a bogus address).
String? extractVpaFromQr(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  if (text.toLowerCase().contains('://')) {
    // Deep-link QR: prefer the `pa` query parameter (the payee address).
    try {
      final uri = Uri.parse(text);
      final pa = uri.queryParameters['pa'];
      if (pa != null && pa.trim().isNotEmpty) return pa.trim();
    } catch (_) {
      // Malformed URI — fall through to the regex below.
    }
    // Some scanners/printers emit broken URIs (unescaped, missing scheme
    // before `upi://pay?`). Match the `pa=` value case-insensitively.
    final paMatch =
        RegExp(r'[?&]pa=([^&\s]+)', caseSensitive: false).firstMatch(text);
    if (paMatch != null) {
      final value = paMatch.group(1)!;
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        return value;
      }
    }
    return null;
  }

  // Plain-text QR: a bare VPA like `name@upi`.
  return RegExp(r'[A-Za-z0-9._\-]{2,}@[A-Za-z0-9.\-]{2,}').firstMatch(text)?.group(0);
}

/// Whether [vpa] looks like a usable UPI address (must contain an `@` —
/// the sending UPI app validates the rest).
bool isValidVpa(String? vpa) => vpa != null && vpa.trim().contains('@');
