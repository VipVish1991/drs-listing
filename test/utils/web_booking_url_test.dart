import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/utils/web_booking_url.dart';

void main() {
  group('isWebBookingFragment', () {
    test('returns true for bare web-booking fragment', () {
      expect(isWebBookingFragment('web-booking'), isTrue);
    });

    test('returns true for leading-slash fragment', () {
      expect(isWebBookingFragment('/web-booking'), isTrue);
    });

    test('returns true with query parameters', () {
      expect(
        isWebBookingFragment('web-booking?doctor=place_123&token=abc'),
        isTrue,
      );
    });

    test('returns true with leading slash and query parameters', () {
      expect(
        isWebBookingFragment('/web-booking?doctor=place_123&token=abc'),
        isTrue,
      );
    });

    test('returns false for empty string', () {
      expect(isWebBookingFragment(''), isFalse);
    });

    test('returns false for unrelated route', () {
      expect(isWebBookingFragment('home'), isFalse);
    });

    test('returns false for unrelated route with leading slash', () {
      expect(isWebBookingFragment('/home'), isFalse);
    });

    test('returns false for login route', () {
      expect(isWebBookingFragment('/login'), isFalse);
    });

    test('returns false for a sub-path under web-booking', () {
      // "web-booking" must be the FIRST path segment, not a deeper path.
      expect(isWebBookingFragment('other/web-booking'), isFalse);
    });

    test('returns true when web-booking is first segment with sub-path', () {
      expect(isWebBookingFragment('/web-booking/something'), isTrue);
    });

    test('handles malformed URI gracefully', () {
      // %ZZ is not a valid percent-encoding — Uri.parse may throw.
      expect(isWebBookingFragment('/%ZZweb-booking'), isFalse);
    });
  });

  group('hasRouteFragment', () {
    test('returns true for any non-empty path', () {
      expect(hasRouteFragment('web-booking'), isTrue);
      expect(hasRouteFragment('home'), isTrue);
      expect(hasRouteFragment('/login'), isTrue);
    });

    test('returns false for empty string', () {
      expect(hasRouteFragment(''), isFalse);
    });

    test('returns true for route with query params', () {
      expect(hasRouteFragment('web-booking?doctor=X'), isTrue);
    });

    test('handles malformed URI gracefully', () {
      // Uri.parse is lenient — it keeps %ZZ in the path rather than
      // throwing, so the function still detects a route segment.
      expect(hasRouteFragment('/%ZZbad'), isTrue);
    });
  });
}
