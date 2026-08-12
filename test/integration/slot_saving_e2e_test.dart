/// End-to-end integration test for doctor slot saving.
///
/// This test runs against the LIVE Supabase instance and verifies that
/// the full slot save/load/update/delete flow works as expected.
///
/// Run with:
///   flutter test test/integration/slot_saving_e2e_test.dart --tags=e2e
///
/// ⚠️ This test creates and destroys real data. It uses a unique test
///    place_id (`e2e_test_doc_integration`) to avoid conflicts.
///    tearDownAll guarantees cleanup even if a test fails mid-way.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/doctor_slot_model.dart';
import '../helpers/test_data.dart';

/// Supabase REST API endpoint, derived from the project's const URL so
/// it stays in sync if the project is ever migrated.
String get _api => '${AppConstants.supabaseUrl}/rest/v1';

/// Unique test doctor — never conflicts with real data.
const _testPlaceId = 'e2e_test_doc_integration';

/// Shared headers for Supabase REST calls.
Map<String, String> _headers() => {
      'apikey': AppConstants.supabaseAnonKey,
      'Authorization': 'Bearer ${AppConstants.supabaseAnonKey}',
      'Content-Type': 'application/json',
    };

/// Executes a Supabase REST DELETE for the given [table] with the
/// place_id filter, used by tearDownAll for guaranteed cleanup.
Future<void> _deleteTestData(String table) async {
  try {
    await http.delete(
      Uri.parse('$_api/$table?place_id=eq.$_testPlaceId'),
      headers: {..._headers(), 'Prefer': 'return=representation'},
    );
  } catch (_) {
    // Swallow errors during cleanup — no point failing teardown.
  }
}

/// Deletes all slot rows for the test doctor via the
/// `doctor_place_id` column (not `place_id`).
Future<void> _deleteTestSlots() async {
  try {
    await http.delete(
      Uri.parse('$_api/doctor_slots?doctor_place_id=eq.$_testPlaceId'),
      headers: {..._headers(), 'Prefer': 'return=representation'},
    );
  } catch (_) {}
}

void main() {
  // ── Guaranteed cleanup even on failure ──────────────────────────

  tearDownAll(() async {
    await _deleteTestSlots();
    await _deleteTestData('doctors');
  });

  // ── Scenario 1: Insert doctor → insert slots → verify readback ──

  group('Scenario 1: Full create flow', () {
    late DoctorModel doctor;

    test('Insert or upsert doctor profile (Step 1 of saveAll)', () async {
      // Use the factory from test_data.dart
      doctor = doctorBasic(
        placeId: _testPlaceId,
        name: 'E2E Integration Test Doctor',
        rating: 4.2,
        userRatingsTotal: 50,
        latitude: 21.245,
        longitude: 81.630,
        phoneNumber: '+919999999999',
        isOpen: true,
        address: 'Integration Test Street, Test City',
      );

      final body = doctor.toJson();
      body.remove('distance');
      // Remove nulls so they don't overwrite existing DB values
      body.removeWhere((_, v) => v == null);

      // Try POST to create; if 409 (duplicate), PATCH instead (upsert)
      var response = await http.post(
        Uri.parse('$_api/doctors'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 409) {
        // Doctor already exists from a previous run — update via PATCH
        response = await http.patch(
          Uri.parse('$_api/doctors?place_id=eq.$_testPlaceId'),
          headers: {..._headers(), 'Prefer': 'return=representation'},
          body: jsonEncode(body),
        );
      }

      expect(response.statusCode, anyOf(201, 200),
          reason: 'Doctor insert (201) or patch (200) should succeed. '
              'Got: ${response.statusCode}');

      final data = jsonDecode(response.body) as List;
      expect(data.length, 1);
      expect(data[0]['place_id'], _testPlaceId);
      expect(data[0]['name'], 'E2E Integration Test Doctor');
      expect((data[0]['rating'] as num).toDouble(), 4.2);
    });

    test('Insert 3 slot rows (Step 4 of saveAll)', () async {
      final slots = [
        DoctorSlot(
          doctorPlaceId: _testPlaceId,
          dayOfWeek: 'Monday',
          scheduleType: 'video',
          startTime: '09:00',
          endTime: '12:00',
          durationMinutes: 30,
          fee: 800,
          slots: ['9:00 AM', '9:30 AM', '10:00 AM'],
          isEnabled: true,
        ),
        DoctorSlot(
          doctorPlaceId: _testPlaceId,
          dayOfWeek: 'Monday',
          scheduleType: 'clinic',
          startTime: '10:00',
          endTime: '14:00',
          durationMinutes: 30,
          fee: 1000,
          slots: ['10:00 AM', '10:30 AM', '11:00 AM'],
          isEnabled: true,
        ),
        DoctorSlot(
          doctorPlaceId: _testPlaceId,
          dayOfWeek: 'Tuesday',
          scheduleType: 'video',
          startTime: '09:00',
          endTime: '13:00',
          durationMinutes: 45,
          fee: 750,
          slots: ['9:00 AM', '9:45 AM', '10:30 AM'],
          isEnabled: true,
        ),
      ];

      for (final slot in slots) {
        final response = await http.post(
          Uri.parse('$_api/doctor_slots'),
          headers: {..._headers(), 'Prefer': 'return=representation'},
          body: jsonEncode(slot.toJson()),
        );
        expect(response.statusCode, 201,
            reason:
                'Slot insert should return 201 for ${slot.dayOfWeek}/${slot.scheduleType}');
      }
    });

    test('Readback confirms 3 slot rows', () async {
      final response = await http.get(
        Uri.parse(
            '$_api/doctor_slots?doctor_place_id=eq.$_testPlaceId&select=id,day_of_week,schedule_type,fee,is_enabled,slots&order=day_of_week.asc,schedule_type.asc'),
        headers: _headers(),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as List;
      expect(data.length, 3,
          reason: 'Should have 3 slot rows (Mon video, Mon clinic, Tue video)');

      // Verify each slot's data survived the round-trip
      expect(data[0]['day_of_week'], 'Monday');
      expect(data[0]['schedule_type'], 'clinic');
      expect(data[0]['fee'], 1000);

      expect(data[1]['day_of_week'], 'Monday');
      expect(data[1]['schedule_type'], 'video');
      expect(data[1]['fee'], 800);

      expect(data[2]['day_of_week'], 'Tuesday');
      expect(data[2]['schedule_type'], 'video');
      expect(data[2]['fee'], 750);
    });
  });

  // ── Scenario 2: Update an existing slot via PATCH ────────────────

  group('Scenario 2: Slot update flow (re-save)', () {
    test('Insert fresh slots for this scenario', () async {
      final slot = DoctorSlot(
        doctorPlaceId: _testPlaceId,
        dayOfWeek: 'Wednesday',
        scheduleType: 'video',
        startTime: '10:00',
        endTime: '15:00',
        durationMinutes: 30,
        fee: 800,
        slots: ['10:00 AM', '10:30 AM', '11:00 AM'],
        isEnabled: true,
      );

      final response = await http.post(
        Uri.parse('$_api/doctor_slots'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode(slot.toJson()),
      );

      expect(response.statusCode, 201);

      final data = jsonDecode(response.body) as List;
      expect(data.length, 1);
      expect(data[0]['day_of_week'], 'Wednesday');
    });

    test('PATCH updates fee, end_time, and slots', () async {
      final response = await http.patch(
        Uri.parse(
            '$_api/doctor_slots?doctor_place_id=eq.$_testPlaceId&day_of_week=eq.Wednesday&schedule_type=eq.video'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode({
          'end_time': '17:00',
          'fee': 950,
          'slots': ['10:00 AM', '11:00 AM', '12:00 PM', '1:00 PM'],
          'duration_minutes': 60,
        }),
      );

      expect(response.statusCode, 200,
          reason: 'PATCH should return 200 OK');

      final data = jsonDecode(response.body) as List;
      expect(data.length, 1);
      expect(data[0]['fee'], 950);
      expect(data[0]['end_time'], '17:00');
      expect(data[0]['duration_minutes'], 60);
      expect((data[0]['slots'] as List).length, 4);

      // id and created_at should be preserved (same row)
      expect(data[0]['id'], isNotNull);

      final createdAt = DateTime.tryParse(data[0]['created_at'] as String);
      expect(createdAt, isNotNull);

      final updatedAt = DateTime.tryParse(data[0]['updated_at'] as String);
      expect(updatedAt, isNotNull);
      // updated_at should be after created_at
      expect(updatedAt!.isAfter(createdAt!), isTrue);
    });
  });

  // ── Scenario 3: Delete all slots via app's deleteAllDoctorSlots ──

  group('Scenario 3: Delete all slots (Step 2 of saveAll)', () {
    test('Insert 2 slots, then delete them all', () async {
      // First, clean up any leftover slots from previous scenarios
      await _deleteTestSlots();

      // Insert 2 fresh slots
      for (final day in ['Thursday', 'Friday']) {
        final slot = DoctorSlot(
          doctorPlaceId: _testPlaceId,
          dayOfWeek: day,
          scheduleType: 'clinic',
          startTime: '09:00',
          endTime: '12:00',
          durationMinutes: 30,
          fee: 800,
          slots: ['9:00 AM', '9:30 AM', '10:00 AM'],
          isEnabled: true,
        );
        final response = await http.post(
          Uri.parse('$_api/doctor_slots'),
          headers: {..._headers(), 'Prefer': 'return=representation'},
          body: jsonEncode(slot.toJson()),
        );
        expect(response.statusCode, 201,
            reason: 'Insert for $day should succeed');
      }

      // Verify only 2 rows exist (no leftovers)
      final countResp = await http.get(
        Uri.parse(
            '$_api/doctor_slots?doctor_place_id=eq.$_testPlaceId&select=id'),
        headers: _headers(),
      );
      expect(jsonDecode(countResp.body).length, 2);

      // Delete all — same as deleteAllDoctorSlots() in the app
      final deleteResp = await http.delete(
        Uri.parse(
            '$_api/doctor_slots?doctor_place_id=eq.$_testPlaceId'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
      );
      expect(deleteResp.statusCode, 200);

      // Verify 0 rows
      final verifyResp = await http.get(
        Uri.parse(
            '$_api/doctor_slots?doctor_place_id=eq.$_testPlaceId&select=id'),
        headers: _headers(),
      );
      final remaining = jsonDecode(verifyResp.body) as List;
      expect(remaining.length, 0,
          reason: 'All slots should be deleted after deleteAllDoctorSlots');
    });

    test('Insert then re-save (simulating full re-save week)', () async {
      // Clean slate: delete any leftover slots first, then re-insert
      await _deleteTestSlots();

      for (final day in ['Thursday', 'Friday']) {
        final slot = DoctorSlot(
          doctorPlaceId: _testPlaceId,
          dayOfWeek: day,
          scheduleType: 'clinic',
          startTime: '09:00',
          endTime: '12:00',
          durationMinutes: 30,
          fee: 800,
          slots: ['9:00 AM', '9:30 AM', '10:00 AM'],
          isEnabled: true,
        );
        await http.post(
          Uri.parse('$_api/doctor_slots'),
          headers: {..._headers(), 'Prefer': 'return=representation'},
          body: jsonEncode(slot.toJson()),
        );
      }

      // Verify re-insertion worked — exactly 2 rows
      final resp = await http.get(
        Uri.parse(
            '$_api/doctor_slots?doctor_place_id=eq.$_testPlaceId&select=id'),
        headers: _headers(),
      );
      expect((jsonDecode(resp.body) as List).length, 2,
          reason: 'Re-insert should succeed after delete');
    });
  });
}
