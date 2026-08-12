import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/utils/number_formatter.dart';

void main() {
  group('compactCount', () {
    test('small numbers render as-is', () {
      expect(compactCount(0), '0');
      expect(compactCount(5), '5');
      expect(compactCount(99), '99');
      expect(compactCount(999), '999');
    });

    test('thousands render with K suffix', () {
      expect(compactCount(1000), '1K');
      expect(compactCount(1200), '1.2K');
      expect(compactCount(9999), '10K');
      expect(compactCount(10000), '10K');
      expect(compactCount(12300), '12.3K');
      expect(compactCount(999500), '999.5K');
    });

    test('millions render with M suffix', () {
      expect(compactCount(1000000), '1M');
      expect(compactCount(1500000), '1.5M');
      expect(compactCount(10000000), '10M');
      expect(compactCount(12300000), '12.3M');
    });

    test('billions render with B suffix', () {
      expect(compactCount(1000000000), '1B');
      expect(compactCount(2500000000), '2.5B');
    });

    test('negative and fractional inputs do not crash', () {
      expect(compactCount(-5), '-5');
      expect(compactCount(3.7), '4');
      expect(compactCount(1000.0), '1K');
    });
  });
}
