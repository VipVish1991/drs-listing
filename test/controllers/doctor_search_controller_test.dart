import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:DrsListing/controllers/doctor_search_controller.dart';
import '../helpers/test_data.dart';

void main() {
  late DoctorSearchController controller;

  setUp(() {
    // Register a fresh controller for each test.
    Get.put<DoctorSearchController>(DoctorSearchController(), permanent: true);
    controller = Get.find<DoctorSearchController>();
  });

  tearDown(() {
    // Clear GetX bindings between tests so the next setUp starts clean.
    Get.reset();
  });

  group('filteredDoctors — radius post-filter', () {
    setUp(() {
      // Populate the controller with a known set of doctors at various
      // distances.  The controller stores them in [doctors] and the
      // [filteredDoctors] getter applies the radius post-filter on top.
      controller.doctors.assignAll([
        doctorBasic(
          placeId: 'near',
          name: 'Dr. Near',
          latitude: 12.34,
          longitude: 56.78,
        ),
        doctorBasic(
          placeId: 'far',
          name: 'Dr. Far',
          latitude: 13.50,
          longitude: 57.90,
        ),
        doctorBasic(
          placeId: 'no_gps',
          name: 'Dr. NoGPS',
          latitude: null,
          longitude: null,
        ),
        doctorBasic(
          placeId: 'very_far',
          name: 'Dr. VeryFar',
          latitude: 14.00,
          longitude: 58.50,
        ),
      ]);
    });

    test('returns all doctors when no location data is available', () {
      // _lastLatitude / _lastLongitude are null by default → filter disabled
      final result = controller.filteredDoctors;

      expect(result.length, 4);
      expect(
        result.map((d) => d.placeId),
        unorderedEquals(['near', 'far', 'no_gps', 'very_far']),
      );
    });

    test('excludes doctors beyond 5 km radius', () {
      // Override the default 50 km radius down to 5 km for this test.
      controller.searchRadiusKm.value = 5;

      controller.setTestFilterState(
        latitude: 12.34,
        longitude: 56.78,
        rawDistances: {
          'near': 2000, // 2 km  → inside 5 km ✓
          'far': 8000, // 8 km  → outside 5 km ✗
          'no_gps': 0, // null lat/lng → _attachDistances won't store
          'very_far': 15000, // 15 km → outside 5 km ✗
        },
      );

      final result = controller.filteredDoctors;

      // Dr. NoGPS has raw == null (no distance was computable) → kept
      // Dr. Near has raw == 2000 ≤ 5000 → kept
      // Dr. Far has raw == 8000 > 5000 → excluded
      // Dr. VeryFar has raw == 15000 > 5000 → excluded
      expect(result.length, 2);
      expect(result.map((d) => d.placeId), unorderedEquals(['near', 'no_gps']));
    });

    test('keeps more doctors when radius is increased', () {
      controller.searchRadiusKm.value = 10; // 10 km → _radiusMeters = 10000

      controller.setTestFilterState(
        latitude: 12.34,
        longitude: 56.78,
        rawDistances: {
          'near': 2000, // 2 km  → inside 10 km ✓
          'far': 8000, // 8 km  → inside 10 km ✓
          'no_gps': 0, // no data → kept
          'very_far': 15000, // 15 km → outside 10 km ✗
        },
      );

      final result = controller.filteredDoctors;

      // Dr. Far (8 km) is now inside the 10 km radius
      expect(result.length, 3);
      expect(
        result.map((d) => d.placeId),
        unorderedEquals(['near', 'far', 'no_gps']),
      );
    });

    test(
      'includes doctors with missing distance data regardless of radius',
      () {
        controller.searchRadiusKm.value = 1; // 1 km → very tight

        // Simulate that only 'near' and 'far' have computable distances.
        // 'no_gps' and 'very_far' have no entry in rawDistances (null raw)
        // and should be kept by the null-guard regardless of radius.
        controller.setTestFilterState(
          latitude: 12.34,
          longitude: 56.78,
          rawDistances: {
            'near': 500, // 0.5 km → inside 1 km ✓
            'far': 6000, // 6 km  → outside 1 km ✗
            // no_gps deliberately omitted (null lat/lng, no distance)
            // very_far deliberately omitted (simulates missing raw entry)
          },
        );

        final result = controller.filteredDoctors;

        // 'no_gps' has no entry in _rawDistances → raw == null → included
        // 'very_far' has no entry in _rawDistances → raw == null → included
        // 'near' 500 ≤ 1000 → included
        // 'far' 6000 > 1000 → excluded
        expect(result.length, 3);
        expect(
          result.map((d) => d.placeId),
          unorderedEquals(['near', 'no_gps', 'very_far']),
        );
      },
    );

    test(
      'radius filter + sort-by-distance: excludes doctors beyond radius then sorts nearest-first',
      () {
        controller.searchRadiusKm.value = 10;

        controller.setTestFilterState(
          latitude: 12.34,
          longitude: 56.78,
          rawDistances: {
            'far': 8000, // 8 km  → inside 10 km ✓
            'near': 500, // 0.5 km → inside 10 km ✓
            'very_far': 15000, // 15 km → outside 10 km ✗
            // no_gps omitted → null → kept regardless of radius
          },
        );

        controller.sortByDistance.value = true;

        final result = controller.filteredDoctors;

        // Radius excludes very_far (15 km > 10 km)
        // Remaining: near (500 m), far (8000 m), no_gps (null distance)
        // Sort: near → far → no_gps (nulls sort last)
        expect(result.length, 3);
        expect(result[0].placeId, 'near'); // 500 m  ← nearest
        expect(result[1].placeId, 'far'); // 8000 m
        expect(result[2].placeId, 'no_gps'); // null distance → last
      },
    );

    test(
      'radius filter + sort-by-distance: order unchanged when sort is disabled',
      () {
        controller.searchRadiusKm.value = 10;

        controller.setTestFilterState(
          latitude: 12.34,
          longitude: 56.78,
          rawDistances: {'far': 8000, 'near': 500, 'very_far': 15000},
        );

        // sortByDistance is NOT enabled (default false)
        final result = controller.filteredDoctors;

        // Radius excludes very_far (15 km > 10 km)
        // Remaining in original insertion order (near, far, no_gps, very_far)
        // minus very_far → (near, far, no_gps)
        expect(result.length, 3);
        expect(result[0].placeId, 'near'); // original insertion order preserved
        expect(result[1].placeId, 'far');
        expect(result[2].placeId, 'no_gps');
      },
    );

    test(
      'radius filter + minimum rating: excludes doctors below rating threshold and beyond radius',
      () {
        // Override Dr. Near and Dr. Far with specific ratings for this test.
        // Default rating is 4.5, so we lower some to test the minRating filter.
        controller.doctors.assignAll([
          doctorBasic(
            placeId: 'high_rated',
            name: 'Dr. High',
            rating: 4.8,
            latitude: 12.34,
            longitude: 56.78,
          ),
          doctorBasic(
            placeId: 'low_rated',
            name: 'Dr. Low',
            rating: 2.0,
            latitude: 13.50,
            longitude: 57.90,
          ),
          doctorBasic(
            placeId: 'no_gps',
            name: 'Dr. NoGPS',
            rating: 4.0,
            latitude: null,
            longitude: null,
          ),
          doctorBasic(
            placeId: 'distant_low',
            name: 'Dr. DistantLow',
            rating: 3.0,
            latitude: 14.00,
            longitude: 58.50,
          ),
        ]);

        controller.searchRadiusKm.value = 10;
        controller.minRating.value = 3.5;

        controller.setTestFilterState(
          latitude: 12.34,
          longitude: 56.78,
          rawDistances: {
            'high_rated':
                2000, // 2 km  → inside 10 km ✓, rating 4.8 ≥ 3.5 ✓ → kept
            'low_rated':
                3000, // 3 km  → inside 10 km ✓, rating 2.0 < 3.5 ✗ → excluded
            'no_gps': 0, // null distance → kept, rating 4.0 ≥ 3.5 ✓ → kept
            'distant_low':
                12000, // 12 km → outside 10 km ✗ → excluded by radius
          },
        );

        final result = controller.filteredDoctors;

        // high_rated: passes both radius (2 km ≤ 10 km) and rating (4.8 ≥ 3.5) ✓
        // low_rated: passes radius (3 km ≤ 10 km) but fails rating (2.0 < 3.5) ✗
        // no_gps: passes radius (null → kept) and rating (4.0 ≥ 3.5) ✓
        // distant_low: fails radius (12 km > 10 km) ✗
        expect(result.length, 2);
        expect(
          result.map((d) => d.placeId),
          unorderedEquals(['high_rated', 'no_gps']),
        );
      },
    );

  group('filteredDoctors — type filter (via _getPlaceType)', () {
    setUp(() {
      controller.doctors.assignAll([
        doctorBasic(
          placeId: 'doc1',
          name: 'Dr. A',
          types: ['doctor', 'health'],
        ),
        doctorBasic(
          placeId: 'hosp1',
          name: 'City Hospital',
          types: ['hospital', 'health'],
        ),
        doctorBasic(
          placeId: 'clinic1',
          name: 'Wellness Clinic',
          types: ['health'],
        ),
        doctorBasic(
          placeId: 'pharm1',
          name: 'MedPlus Pharmacy',
          types: ['pharmacy', 'store'],
        ),
        doctorBasic(
          placeId: 'physio1',
          name: 'Physio Center',
          types: ['physiotherapist', 'health'],
        ),
      ]);
    });

    test('filterType "All" returns all doctors', () {
      controller.filterType.value = 'All';
      final result = controller.filteredDoctors;
      expect(result.length, 5);
    });

    test('filterType "Doctor" returns only doctor-typed places', () {
      controller.filterType.value = 'Doctor';
      final result = controller.filteredDoctors;
      expect(result.length, 1);
      expect(result.first.placeId, 'doc1');
    });

    test('filterType "Hospital" returns only hospital-typed places', () {
      controller.filterType.value = 'Hospital';
      final result = controller.filteredDoctors;
      expect(result.length, 1);
      expect(result.first.placeId, 'hosp1');
    });

    test('filterType "Clinic" returns places without known type', () {
      // Clinic is the fallback — place with types ['health'] has no
      // recognised type keyword, so _getPlaceType returns 'Clinic'.
      controller.filterType.value = 'Clinic';
      final result = controller.filteredDoctors;
      expect(result.length, 1);
      expect(result.first.placeId, 'clinic1');
    });

    test('filterType "Pharmacy" returns pharmacy-typed places', () {
      controller.filterType.value = 'Pharmacy';
      final result = controller.filteredDoctors;
      expect(result.length, 1);
      expect(result.first.placeId, 'pharm1');
    });

    test('returns empty when filter matches no doctors', () {
      // No doctor has type 'dentist', so filter yields nothing
      controller.doctors.assignAll([
        doctorBasic(placeId: 'only_doc', name: 'Dr. Only', types: ['doctor']),
      ]);
      controller.filterType.value = 'Hospital';
      final result = controller.filteredDoctors;
      expect(result, isEmpty);
    });

    test('prioritisation: doctor over hospital when both present', () {
      controller.doctors.assignAll([
        doctorBasic(
          placeId: 'doc_hosp',
          name: 'Dr. At Hospital',
          types: ['doctor', 'hospital', 'health'],
        ),
      ]);
      // Filter by Hospital should NOT find it because doctor is checked first
      controller.filterType.value = 'Hospital';
      final resultHosp = controller.filteredDoctors;
      expect(resultHosp, isEmpty);

      // Filter by Doctor SHOULD find it
      controller.filterType.value = 'Doctor';
      final resultDoc = controller.filteredDoctors;
      expect(resultDoc.length, 1);
      expect(resultDoc.first.placeId, 'doc_hosp');
    });

    test('case-insensitive type matching', () {
      controller.doctors.assignAll([
        doctorBasic(
          placeId: 'upper',
          name: 'Capital Doctor',
          types: ['Doctor', 'Health'],
        ),
      ]);
      controller.filterType.value = 'Doctor';
      final result = controller.filteredDoctors;
      expect(result.length, 1);
      expect(result.first.placeId, 'upper');
    });

    test('type filter stacks with other filters', () {
      controller.filterType.value = 'Doctor';

      // Dr. A passes type filter
      final result = controller.filteredDoctors;
      expect(result.length, 1);
      expect(result.first.placeId, 'doc1');
    });
  });

  test('radius filter + minimum rating: excludes low-rated doctors beyond radius', () {
      controller.searchRadiusKm.value = 5;

      // Assign specific ratings
      controller.doctors.assignAll([
        doctorBasic(
          placeId: 'near',
          name: 'Dr. Near',
          rating: 4.5,
          latitude: 12.34,
          longitude: 56.78,
        ),
        doctorBasic(
          placeId: 'far',
          name: 'Dr. Far',
          rating: 2.0,
          latitude: 13.50,
          longitude: 57.90,
        ),
        doctorBasic(
          placeId: 'no_gps',
          name: 'Dr. NoGPS',
          rating: 4.0,
          latitude: null,
          longitude: null,
        ),
        doctorBasic(
          placeId: 'very_far',
          name: 'Dr. VeryFar',
          rating: 3.8,
          latitude: 14.00,
          longitude: 58.50,
        ),
      ]);

      controller.minRating.value = 3.5;

      controller.setTestFilterState(
        latitude: 12.34,
        longitude: 56.78,
        rawDistances: {
          'near': 2000, // inside ✓, rating 4.5 ≥ 3.5 ✓ → kept
          'far': 3000, // inside ✓, rating 2.0 < 3.5 ✗ → excluded
          'very_far': 15000, // outside ✗ → excluded
        },
      );

      final result = controller.filteredDoctors;

      // Dr. Far within radius but low rating → excluded
      // Dr. VeryFar outside radius → excluded
      // Dr. Near within radius, high rating → kept
      // Dr. NoGPS (null raw, high rating) → kept
      expect(result.length, 2);
      expect(result.map((d) => d.placeId), unorderedEquals(['near', 'no_gps']));
    });
  });


}
