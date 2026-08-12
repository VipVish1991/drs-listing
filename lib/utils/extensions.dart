/// Extension methods for common formatting patterns.
extension RatingFormat on double {
  /// Formats a rating value as a single-decimal string (e.g. `4.5`).
  String get ratingString => toStringAsFixed(1);
}
