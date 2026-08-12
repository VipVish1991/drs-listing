/// Formats a distance in [meters] into a human-readable string.
///
/// - Distances < 1 km are shown as `"X m"` (e.g. `"800 m"`)
/// - Distances >= 1 km are shown as `"X.X km"` (e.g. `"1.2 km"`)
String formatDistance(double meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  } else {
    final km = (meters / 1000).toStringAsFixed(1);
    return '$km km';
  }
}
