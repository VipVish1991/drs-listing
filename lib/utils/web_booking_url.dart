/// Pure URL-parsing helpers for detecting web-booking routes.
///
/// Extracted from `app.dart` (`_initialRoute`) and
/// `splash_screen.dart` (`_isWebBookingUrl`) so the logic can be
/// unit-tested without depending on `kIsWeb` or `Uri.base`.
library;

/// Returns `true` when [fragment] (the part after `#` in a URL)
/// represents a `/web-booking` route.
///
/// Accepts fragments with or without a leading `/` and with or
/// without query parameters:
///   - `web-booking?doctor=X` → true
///   - `/web-booking?doctor=X&token=Y` → true
///   - `home` → false
///   - `` (empty) → false
bool isWebBookingFragment(String fragment) {
  if (fragment.isEmpty) return false;
  try {
    final hashUri = Uri.parse(
      fragment.startsWith('/') ? fragment : '/$fragment',
    );
    return hashUri.pathSegments.isNotEmpty &&
        hashUri.pathSegments.first == 'web-booking';
  } catch (_) {
    return false;
  }
}

/// Returns `true` when [fragment] looks like any recognized app route
/// (i.e. it has at least one path segment that starts with a letter).
bool hasRouteFragment(String fragment) {
  if (fragment.isEmpty) return false;
  try {
    final hashUri = Uri.parse(
      fragment.startsWith('/') ? fragment : '/$fragment',
    );
    return hashUri.pathSegments.isNotEmpty &&
        hashUri.pathSegments.first.isNotEmpty;
  } catch (_) {
    return false;
  }
}
