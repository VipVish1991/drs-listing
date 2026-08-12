import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/unavailable_range.dart';
import '../helpers/test_data.dart';

void main() {
  group('DoctorModel', () {
    group('fromGooglePlaces (Text Search / Place Details — legacy)', () {
      test('parses a hospital result correctly', () {
        final json = placesResultJson();
        final doc = DoctorModel.fromGooglePlaces(json);

        expect(doc.placeId, 'gplaces_1');
        expect(doc.name, 'City Hospital');
        expect(doc.latitude, 12.34);
        expect(doc.longitude, 56.78);
        expect(doc.rating, 4.2);
        expect(doc.userRatingsTotal, 200);
        expect(doc.address, '456 Health Ave, City');
        expect(doc.vicinity, '456 Health Ave');
        expect(doc.businessStatus, 'OPERATIONAL');
        expect(doc.isOpen, isTrue);
        expect(doc.types, ['hospital', 'health']);
        expect(doc.photos, ['ref1']);
        expect(doc.photoDetails.length, 1);
      });

      test('parses a doctor result with phone number', () {
        final json = placesDoctorJson(name: 'Dr. Jane');
        final doc = DoctorModel.fromGooglePlaces(json);

        expect(doc.name, 'Dr. Jane');
        expect(doc.phoneNumber, '+1122334455');
        expect(
          doc.specialization,
          'Dr. Jane',
        ); // isDoctor → types contains 'doctor'
        expect(doc.hospitalName, isNull);
      });

      test('handles missing geometry gracefully', () {
        final json = {
          'place_id': 'no_geo',
          'name': 'No Geo Place',
          'types': ['doctor'],
        };
        final doc = DoctorModel.fromGooglePlaces(json);
        expect(doc.latitude, isNull);
        expect(doc.longitude, isNull);
      });

      test('handles null opening_hours', () {
        final json = {
          'place_id': 'no_hours',
          'name': 'No Hours',
          'types': ['health'],
        };
        final doc = DoctorModel.fromGooglePlaces(json);
        expect(doc.isOpen, isNull);
        expect(doc.openingHours, isEmpty);
        expect(doc.openingHoursPeriods, isEmpty);
      });

      test('handles null photos gracefully', () {
        final json = {
          'place_id': 'no_photos',
          'name': 'No Photos',
          'types': ['doctor'],
        };
        final doc = DoctorModel.fromGooglePlaces(json);
        expect(doc.photos, isEmpty);
        expect(doc.photoDetails, isEmpty);
      });

      test('handles null types gracefully', () {
        final json = {'place_id': 'no_types', 'name': 'No Types'};
        final doc = DoctorModel.fromGooglePlaces(json);
        expect(doc.types, isEmpty);
        expect(doc.specialization, isNull);
      });
    });

    group('fromJson (app-local / Supabase)', () {
      test('round-trips through toJson', () {
        final original = doctorBasic();
        final json = original.toJson();
        final restored = DoctorModel.fromJson(json);

        expect(restored.placeId, original.placeId);
        expect(restored.name, original.name);
        expect(restored.rating, original.rating);
        expect(restored.userRatingsTotal, original.userRatingsTotal);
        expect(restored.latitude, original.latitude);
        expect(restored.longitude, original.longitude);
        expect(restored.phoneNumber, original.phoneNumber);
        expect(restored.address, original.address);
        expect(restored.isOpen, original.isOpen);
      });

      test('round-trips unavailable_ranges through toJson/fromJson', () {
        final original = doctorBasic().copyWith(
          unavailableRanges: [
            UnavailableRange(
              start: DateTime(2026, 8, 10),
              end: DateTime(2026, 8, 12),
            ),
          ],
        );
        final json = original.toJson();
        expect(json['unavailable_ranges'], [
          {'start': '2026-08-10', 'end': '2026-08-12'},
        ]);

        final restored = DoctorModel.fromJson(json);
        expect(restored.unavailableRanges.length, 1);
        expect(restored.unavailableRanges.first.start, DateTime(2026, 8, 10));
        expect(restored.unavailableRanges.first.end, DateTime(2026, 8, 12));
      });

      test('round-trips upi_id through toJson/fromJson', () {
        final original = doctorBasic().copyWith(upiId: 'clinic@okhdfcbank');
        final json = original.toJson();
        expect(json['upi_id'], 'clinic@okhdfcbank');

        final restored = DoctorModel.fromJson(json);
        expect(restored.upiId, 'clinic@okhdfcbank');

        // Absent key → null (booking flow falls back to the default VPA).
        final without = DoctorModel.fromJson({'place_id': 'x', 'name': 'Y'});
        expect(without.upiId, isNull);
      });

      test('restores from minimal JSON', () {
        final json = {'place_id': 'min', 'name': 'Dr. X'};
        final doc = DoctorModel.fromJson(json);
        expect(doc.placeId, 'min');
        expect(doc.name, 'Dr. X');
        expect(doc.rating, isNull);
        expect(doc.phoneNumber, isNull);
      });

      test('handles empty JSON gracefully', () {
        final json = <String, dynamic>{};
        final doc = DoctorModel.fromJson(json);
        expect(doc.placeId, '');
        expect(doc.name, '');
        expect(doc.photos, isEmpty);
        expect(doc.types, isEmpty);
      });
    });

    group('copyWith', () {
      test('returns identical copy when no args provided', () {
        final original = doctorBasic();
        final copy = original.copyWith();
        expect(copy.placeId, original.placeId);
        expect(copy.name, original.name);
        expect(copy.rating, original.rating);
      });

      test('overrides specified fields', () {
        final original = doctorBasic();
        final copy = original.copyWith(name: 'Dr. Override', rating: 5.0);
        expect(copy.name, 'Dr. Override');
        expect(copy.rating, 5.0);
        expect(copy.placeId, original.placeId); // unchanged
      });

      test('can set optional fields to non-null', () {
        final original = doctorMinimal();
        final copy = original.copyWith(phoneNumber: '+9999999999');
        expect(copy.phoneNumber, '+9999999999');
      });
    });

    group('serialization', () {
      test('toJson includes all core fields', () {
        final doc = doctorBasic();
        final json = doc.toJson();

        expect(json['place_id'], 'place_test_1');
        expect(json['name'], 'Dr. Smith');
        expect(json['rating'], 4.5);
        expect(json['user_ratings_total'], 100);
        expect(json['latitude'], 12.34);
        expect(json['longitude'], 56.78);
        expect(json['phone_number'], '+9876543210');
        expect(json['address'], '123 Main St, City');
      });

      test('toJson handles minimal model without nulls in lists', () {
        final doc = doctorMinimal();
        final json = doc.toJson();

        expect(json['photos'], isA<List>());
        expect(json['types'], isA<List>());
        expect(json['photo_details'], isA<List>());
        expect(json['reviews'], isA<List>());
        expect(json['opening_hours'], isA<List>());
      });
    });
  });
}
