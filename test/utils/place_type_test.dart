import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/utils/place_type.dart';
import 'package:DrsListing/config/theme.dart';
import '../helpers/test_data.dart';

void main() {
  group('getPlaceType', () {
    test('returns Doctor when types contain "doctor"', () {
      final doc = doctorBasic(types: ['doctor', 'health']);
      expect(getPlaceType(doc), 'Doctor');
    });

    test('returns Hospital when types contain "hospital"', () {
      final doc = doctorBasic(types: ['hospital', 'health']);
      expect(getPlaceType(doc), 'Hospital');
    });

    test('returns Pharmacy when types contain "pharmacy"', () {
      final doc = doctorBasic(types: ['pharmacy', 'store']);
      expect(getPlaceType(doc), 'Pharmacy');
    });

    test('returns Physio when types contain "physiotherapist"', () {
      final doc = doctorBasic(types: ['physiotherapist', 'health']);
      expect(getPlaceType(doc), 'Physio');
    });

    test('returns Clinic as default when no matching types', () {
      final doc = doctorBasic(types: ['health', 'establishment']);
      expect(getPlaceType(doc), 'Clinic');
    });

    test('prioritises Doctor over Hospital when both present', () {
      // doctor is checked first in the conditional chain
      final doc = doctorBasic(types: ['doctor', 'hospital', 'health']);
      expect(getPlaceType(doc), 'Doctor');
    });

    test('prioritises Hospital over Pharmacy when both present', () {
      final doc = doctorBasic(types: ['hospital', 'pharmacy', 'health']);
      expect(getPlaceType(doc), 'Hospital');
    });

    test('is case-insensitive', () {
      final doc = doctorBasic(types: ['Doctor', 'Health']);
      expect(getPlaceType(doc), 'Doctor');
    });

    test('returns Clinic for empty types list', () {
      final doc = doctorBasic(types: []);
      expect(getPlaceType(doc), 'Clinic');
    });

    test('returns Clinic for unknown place type', () {
      final doc = doctorBasic(types: ['church', 'park']);
      expect(getPlaceType(doc), 'Clinic');
    });

    test('works with minimal doctor (no extra fields)', () {
      final doc = doctorMinimal(); // types defaults to []
      expect(getPlaceType(doc), 'Clinic');
    });
  });

  group('getPlaceTypeColor', () {
    test('returns primary for Doctor', () {
      expect(getPlaceTypeColor('Doctor'), AppColors.primary);
    });

    test('returns healthHeart for Hospital', () {
      expect(getPlaceTypeColor('Hospital'), AppColors.healthHeart);
    });

    test('returns healthBrain for Pharmacy', () {
      expect(getPlaceTypeColor('Pharmacy'), AppColors.healthBrain);
    });

    test('returns accent for Physio (fallback)', () {
      expect(getPlaceTypeColor('Physio'), AppColors.accent);
    });

    test('returns accent for Clinic (fallback)', () {
      expect(getPlaceTypeColor('Clinic'), AppColors.accent);
    });

    test('returns accent for unknown type', () {
      expect(getPlaceTypeColor('UnknownType'), AppColors.accent);
    });

    test('returns accent for empty string', () {
      expect(getPlaceTypeColor(''), AppColors.accent);
    });

    test('is case-sensitive (lowercase does not match)', () {
      // getPlaceTypeColor does not normalise case internally
      expect(getPlaceTypeColor('doctor'), AppColors.accent);
    });
  });

  group('integration — getPlaceType → getPlaceTypeColor', () {
    test('Doctor type maps to primary colour', () {
      final doc = doctorBasic(types: ['doctor']);
      final type = getPlaceType(doc);
      expect(getPlaceTypeColor(type), AppColors.primary);
    });

    test('Hospital type maps to healthHeart colour', () {
      final doc = doctorBasic(types: ['hospital']);
      final type = getPlaceType(doc);
      expect(getPlaceTypeColor(type), AppColors.healthHeart);
    });

    test('Clinic fallback maps to accent colour', () {
      final doc = doctorBasic(types: ['gym']);
      final type = getPlaceType(doc);
      expect(getPlaceTypeColor(type), AppColors.accent);
    });
  });
}
