import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/utils/upi_qr_parser.dart';

void main() {
  group('extractVpaFromQr', () {
    test('extracts the pa= VPA from a standard upi://pay deep link', () {
      expect(
        extractVpaFromQr(
          'upi://pay?pa=patient@okhdfcbank&pn=Patient&am=500&cu=INR',
        ),
        'patient@okhdfcbank',
      );
    });

    test('extracts the VPA from other UPI app deep links', () {
      expect(
        extractVpaFromQr('phonepe://pay?pa=ravi@ybl&pn=Ravi'),
        'ravi@ybl',
      );
      expect(
        extractVpaFromQr('paytm://pay?pa=pay@paytm&pn=Pay'),
        'pay@paytm',
      );
      expect(
        extractVpaFromQr('gpay://pay?pa=me@oksbi&pn=Me'),
        'me@oksbi',
      );
    });

    test('handles a bare VPA string (no scheme)', () {
      expect(extractVpaFromQr('patient@okhdfcbank'), 'patient@okhdfcbank');
      expect(extractVpaFromQr('  ravi@ybl  '), 'ravi@ybl');
    });

    test('falls back to a case-insensitive pa= regex on malformed URIs', () {
      expect(extractVpaFromQr('upi://pay?PA=patient@okhdfcbank&am=1'),
          'patient@okhdfcbank');
      expect(extractVpaFromQr('upi://pay?pa=pat%40okaxis&pn=X'),
          'pat@okaxis');
    });

    test('returns null when nothing looks like a VPA', () {
      expect(extractVpaFromQr(''), isNull);
      expect(extractVpaFromQr('not a qr code'), isNull);
      expect(extractVpaFromQr('upi://pay?pn=NoAddress&am=1'), isNull);
    });
  });

  group('isValidVpa', () {
    test('accepts a VPA containing @', () {
      expect(isValidVpa('patient@okhdfcbank'), isTrue);
    });

    test('rejects blanks / missing @', () {
      expect(isValidVpa(null), isFalse);
      expect(isValidVpa(''), isFalse);
      expect(isValidVpa('   '), isFalse);
      expect(isValidVpa('notavpa'), isFalse);
    });
  });
}
