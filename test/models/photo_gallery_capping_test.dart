import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/models/doctor_model.dart';
import '../helpers/test_data.dart';

void main() {
  group('Photo gallery capping logic', () {
    DoctorModel doctorWithPhotoCount(int count) {
      final photos = List<String>.generate(
        count,
        (i) => 'photo_ref_${i + 1}',
      );
      return doctorBasic(placeId: 'gallery_test', name: 'Test Doctor')
          .copyWith(photos: photos);
    }

    /// The capping logic used by _PhotoGalleryCard:
    /// - Display at most `cap` items in the grid
    /// - Show "+N more" overlay when count > cap
    const int displayCap = 9;

    test('doctor with 0 photos has empty list', () {
      final doctor = doctorWithPhotoCount(0);
      expect(doctor.photos, isEmpty);
    });

    test('doctor with 5 photos shows all (under cap)', () {
      final doctor = doctorWithPhotoCount(5);
      expect(doctor.photos.length, 5);
      expect(doctor.photos.length > displayCap, isFalse);
    });

    test('doctor with 8 photos shows all (under cap)', () {
      final doctor = doctorWithPhotoCount(8);
      expect(doctor.photos.length, 8);
      expect(doctor.photos.length > displayCap, isFalse);
    });

    test('doctor with exactly 9 photos shows all (at cap)', () {
      final doctor = doctorWithPhotoCount(9);
      expect(doctor.photos.length, 9);
      expect(doctor.photos.length > displayCap, isFalse);
      // At cap: no overflow
      expect(doctor.photos.length - displayCap, 0);
    });

    test('doctor with 10 photos caps at 9 with +1 overflow', () {
      final doctor = doctorWithPhotoCount(10);
      expect(doctor.photos.length, 10);

      // Capping: only first 9 shown in grid
      final itemsToShow = doctor.photos.length > displayCap
          ? displayCap
          : doctor.photos.length;
      expect(itemsToShow, 9);

      // Badge: excess count
      final overflow = doctor.photos.length - displayCap;
      expect(overflow, 1);
      expect('+$overflow more', '+1 more');
    });

    test('doctor with 12 photos caps at 9 with +3 overflow', () {
      final doctor = doctorWithPhotoCount(12);
      expect(doctor.photos.length, 12);

      final itemsToShow = doctor.photos.length > displayCap
          ? displayCap
          : doctor.photos.length;
      expect(itemsToShow, 9);

      final overflow = doctor.photos.length - displayCap;
      expect(overflow, 3);
      expect('+$overflow more', '+3 more');
    });

    test('doctor with 25 photos caps at 9 with +16 overflow', () {
      final doctor = doctorWithPhotoCount(25);
      expect(doctor.photos.length, 25);

      final itemsToShow = doctor.photos.length > displayCap
          ? displayCap
          : doctor.photos.length;
      expect(itemsToShow, 9);

      final overflow = doctor.photos.length - displayCap;
      expect(overflow, 16);
      expect('+$overflow more', '+16 more');
    });

    test('copyWith preserves photos', () {
      final photos = ['a', 'b', 'c'];
      final doctor = doctorBasic().copyWith(photos: photos);
      expect(doctor.photos, photos);
    });

    test('copyWith does not mutate original photos', () {
      final original = doctorBasic();
      expect(original.photos, isEmpty);

      final modified = original.copyWith(photos: ['x', 'y', 'z']);
      expect(original.photos, isEmpty);
      expect(modified.photos, ['x', 'y', 'z']);
    });
  });
}
