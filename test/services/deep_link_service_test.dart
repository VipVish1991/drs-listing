import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/services/deep_link_service.dart';

void main() {
  group('parseDeepLink', () {
    test('parses drslisting://book/<placeId>', () {
      final uri = Uri.parse('drslisting://book/ChIJN1t_tDeuEmsRUsoyG83frY4');
      final target = parseDeepLink(uri);

      expect(target, isA<BookingDeepLinkTarget>());
      expect((target as BookingDeepLinkTarget).placeId,
          'ChIJN1t_tDeuEmsRUsoyG83frY4');
    });

    test('parses drslisting://manage-slots/<placeId>', () {
      final uri = Uri.parse('drslisting://manage-slots/ChIJN1t_tDeuEmsRUsoyG83frY4');
      final target = parseDeepLink(uri);

      expect(target, isA<ManageSlotsDeepLinkTarget>());
      expect((target as ManageSlotsDeepLinkTarget).placeId,
          'ChIJN1t_tDeuEmsRUsoyG83frY4');
    });

    test('decodes URL-encoded place ids', () {
      final uri = Uri.parse('drslisting://book/ChIJ%20N1t%2Bt');
      final target = parseDeepLink(uri);

      expect(target, isA<BookingDeepLinkTarget>());
      expect((target as BookingDeepLinkTarget).placeId, 'ChIJ N1t+t');
    });

    test('parses https://drslisting.ai/book/<placeId> universal link', () {
      final uri = Uri.parse(
          'https://drslisting.ai/book/ChIJN1t_tDeuEmsRUsoyG83frY4');
      final target = parseDeepLink(uri);

      expect(target, isA<BookingDeepLinkTarget>());
      expect((target as BookingDeepLinkTarget).placeId,
          'ChIJN1t_tDeuEmsRUsoyG83frY4');
    });

    test('parses https://drslisting.ai/manage-slots/<placeId> universal link',
        () {
      final uri = Uri.parse(
          'https://drslisting.ai/manage-slots/ChIJN1t_tDeuEmsRUsoyG83frY4');
      final target = parseDeepLink(uri);

      expect(target, isA<ManageSlotsDeepLinkTarget>());
      expect((target as ManageSlotsDeepLinkTarget).placeId,
          'ChIJN1t_tDeuEmsRUsoyG83frY4');
    });

    test('parses www.drslisting.ai universal links too', () {
      final uri = Uri.parse(
          'https://www.drslisting.ai/book/ChIJN1t_tDeuEmsRUsoyG83frY4');
      final target = parseDeepLink(uri);

      expect(target, isA<BookingDeepLinkTarget>());
      expect((target as BookingDeepLinkTarget).placeId,
          'ChIJN1t_tDeuEmsRUsoyG83frY4');
    });

    test('rejects https links on other hosts', () {
      final uri = Uri.parse('https://qxukzqdsmlurollltrjp.supabase.co/book/x');
      expect(parseDeepLink(uri), isNull);
    });

    test('rejects non-https www links (scheme must be https)', () {
      // The www. host is only valid as an HTTPS universal link — a custom
      // scheme or plain-http link with that host must not be accepted.
      final customScheme =
          Uri.parse('drslisting://www.drslisting.ai/book/ChIJ123');
      final plainHttp =
          Uri.parse('http://www.drslisting.ai/book/ChIJ123');
      expect(parseDeepLink(customScheme), isNull);
      expect(parseDeepLink(plainHttp), isNull);
    });

    test('rejects non-drslisting, non-applink schemes', () {
      final uri = Uri.parse('mailto:test@example.com');
      expect(parseDeepLink(uri), isNull);
    });

    test('rejects unknown hosts', () {
      final uri = Uri.parse('drslisting://unknown/ChIJ123');
      expect(parseDeepLink(uri), isNull);
    });

    test('rejects links without a place id path segment', () {
      final uri = Uri.parse('drslisting://book');
      expect(parseDeepLink(uri), isNull);
    });

    test('rejects empty place ids', () {
      final uri = Uri.parse('drslisting://book/');
      expect(parseDeepLink(uri), isNull);
    });
  });

  group('deep link constants', () {
    test('bookingDeepLink uses the drslisting scheme with book host', () {
      const placeId = 'ChIJN1t_tDeuEmsRUsoyG83frY4';
      final link = AppConstants.bookingDeepLink(placeId);

      expect(link, startsWith('drslisting://book/'));
      expect(link, contains(Uri.encodeComponent(placeId)));
      expect(link, isNot(contains(AppConstants.supabaseUrl)));
    });

    test('manageSlotsDeepLink uses the drslisting scheme with manage-slots host',
        () {
      const placeId = 'ChIJN1t_tDeuEmsRUsoyG83frY4';
      final link = AppConstants.manageSlotsDeepLink(placeId);

      expect(link, startsWith('drslisting://manage-slots/'));
      expect(link, contains(Uri.encodeComponent(placeId)));
    });

    test('bookingDeepLink round-trips through parseDeepLink', () {
      const placeId = 'ChIJN1t_tDeuEmsRUsoyG83frY4';
      final link = AppConstants.bookingDeepLink(placeId);

      final target = parseDeepLink(Uri.parse(link));
      expect(target, isA<BookingDeepLinkTarget>());
      expect((target as BookingDeepLinkTarget).placeId, placeId);
    });

    test('manageSlotsDeepLink round-trips through parseDeepLink', () {
      const placeId = 'ChIJN1t_tDeuEmsRUsoyG83frY4';
      final link = AppConstants.manageSlotsDeepLink(placeId);

      final target = parseDeepLink(Uri.parse(link));
      expect(target, isA<ManageSlotsDeepLinkTarget>());
      expect((target as ManageSlotsDeepLinkTarget).placeId, placeId);
    });

    test('bookingPageUrl stays an HTTPS URL with the shared token', () {
      const placeId = 'ChIJN1t_tDeuEmsRUsoyG83frY4';
      final url = AppConstants.bookingPageUrl(placeId);

      expect(url, startsWith('https://'));
      expect(url, contains('booking.html?doctor=${Uri.encodeComponent(placeId)}'));
      expect(url, contains('token=${AppConstants.bookingSharedSecret}'));
    });

    test('bookingPageUrl optionally includes the doctor name', () {
      const placeId = 'ChIJN1t_tDeuEmsRUsoyG83frY4';
      final url = AppConstants.bookingPageUrl(placeId, doctorName: 'Dr. Q');

      expect(url, contains('name=${Uri.encodeComponent('Dr. Q')}'));
    });
  });
}
