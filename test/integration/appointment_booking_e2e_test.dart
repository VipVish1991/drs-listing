/// End-to-end integration test for the full appointment booking flow.
///
/// This test runs against the LIVE Supabase instance and verifies that
/// the complete appointment lifecycle works:
///   create user → create doctor → book appointment →
///   read appointment → cancel → verify status change
///
/// Run with:
///   flutter test test/integration/appointment_booking_e2e_test.dart
///     --tags=e2e
///
/// ⚠️ This test creates and destroys real data. It uses unique test
///    identifiers (mobile number, place_id) to avoid conflicts.
///    tearDownAll guarantees best-effort cleanup even if a test fails
///    mid-way. Note: tables without DELETE RLS policies (users, doctors,
///    appointments) will persist — the test handles re-runs gracefully
///    via 409→PATCH/SELECT fallbacks.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:DrsListing/config/constants.dart';
import '../helpers/test_data.dart';

/// Supabase REST API endpoint.
String get _api => '${AppConstants.supabaseUrl}/rest/v1';

/// Unique test identifiers — never conflict with real data.
const _testMobile = '9999999900';
const _testPlaceId = 'e2e_apt_test_doc';
const _testDoctorName = 'E2E Appointment Test Doctor';

/// Shared headers for Supabase REST calls.
///
/// Includes `x-user-mobile` — required since the tightened RLS policies
/// (supabase/migrations/20260801000001_tighten_users_rls.sql) scope the
/// `users` table's SELECT/INSERT to the caller's own mobile via this
/// header. Without it the user-creation step (and therefore every
/// subsequent scenario) fails with a 401/RLS violation.
Map<String, String> _headers() => {
      'apikey': AppConstants.supabaseAnonKey,
      'Authorization': 'Bearer ${AppConstants.supabaseAnonKey}',
      'Content-Type': 'application/json',
      'x-user-mobile': _testMobile,
    };

/// The test user ID, set once during user creation.
String? _testUserId;

/// The current test appointment ID, updated when re-booking.
String? _testAppointmentId;

/// Best-effort cleanup of test data.
///
/// ⚠️ Tables without DELETE RLS policies (users, doctors, appointments)
///    will not be cleaned up via the anon key. This is acceptable because
///    all test flows handle re-runs gracefully with 409→PATCH fallbacks.
Future<void> _cleanupAll() async {
  // doctor_slots table HAS a DELETE policy — this works
  try {
    await http.delete(
      Uri.parse('$_api/doctor_slots?doctor_place_id=eq.$_testPlaceId'),
      headers: _headers(),
    );
  } catch (_) {}

  // doctors table has NO DELETE policy — best-effort only
  try {
    await http.delete(
      Uri.parse('$_api/doctors?place_id=eq.$_testPlaceId'),
      headers: _headers(),
    );
  } catch (_) {}

  // appointments table has NO DELETE policy — best-effort only
  try {
    await http.delete(
      Uri.parse('$_api/appointments?user_id=eq.$_testUserId'),
      headers: _headers(),
    );
  } catch (_) {}
}

void main() {
  // ── Guaranteed best-effort cleanup even on failure ─────────
  tearDownAll(() async {
    await _cleanupAll();
  });

  // ── Scenario 1: Create user ───────────────────────────────

  group('Scenario 1: Create user', () {
    test('Create a test patient user', () async {
      final body = {
        'name': 'E2E Test Patient',
        'mobile': _testMobile,
      };

      // Try POST to create; if 409 (duplicate from a previous run),
      // SELECT the existing user instead.
      var response = await http.post(
        Uri.parse('$_api/users'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode(body),
      );

      List<dynamic> data;
      if (response.statusCode == 409) {
        response = await http.get(
          Uri.parse('$_api/users?mobile=eq.$_testMobile'),
          headers: _headers(),
        );
        data = jsonDecode(response.body) as List;
      } else {
        expect(response.statusCode, 201);
        data = jsonDecode(response.body) is List
            ? jsonDecode(response.body) as List
            : [jsonDecode(response.body)];
      }

      expect(response.statusCode, anyOf(201, 200),
          reason: 'User create (201) or select (200) should succeed. '
              'Got: ${response.statusCode}');

      expect(data.length, greaterThanOrEqualTo(1));
      _testUserId = data[0]['id']?.toString();
      expect(_testUserId, isNotNull);

      expect(data[0]['name'], 'E2E Test Patient');
      expect(data[0]['mobile'], _testMobile);
    });
  });

  // ── Scenario 2: Create doctor and slot ────────────────────

  group('Scenario 2: Create doctor and slot', () {
    test('Create a test doctor profile', () async {
      final doctor = doctorBasic(
        placeId: _testPlaceId,
        name: _testDoctorName,
        rating: 4.5,
        userRatingsTotal: 80,
        latitude: 21.245,
        longitude: 81.630,
        phoneNumber: '+919999999991',
        isOpen: true,
        address: 'Appointment Test Street, Test City',
      );

      final body = doctor.toJson();
      body.remove('distance');
      body.removeWhere((_, v) => v == null);

      var response = await http.post(
        Uri.parse('$_api/doctors'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 409) {
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
      expect(data[0]['name'], _testDoctorName);
    });

    test('Create a test slot for booking', () async {
      final slotBody = {
        'doctor_place_id': _testPlaceId,
        'day_of_week': 'Monday',
        'schedule_type': 'video',
        'start_time': '09:00',
        'end_time': '12:00',
        'duration_minutes': 30,
        'fee': 800,
        'slots': ['9:00 AM', '9:30 AM', '10:00 AM'],
        'is_enabled': true,
      };

      var response = await http.post(
        Uri.parse('$_api/doctor_slots'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode(slotBody),
      );

      if (response.statusCode == 409) {
        response = await http.patch(
          Uri.parse(
              '$_api/doctor_slots?doctor_place_id=eq.$_testPlaceId&day_of_week=eq.Monday&schedule_type=eq.video'),
          headers: {..._headers(), 'Prefer': 'return=representation'},
          body: jsonEncode(slotBody),
        );
      }

      expect(response.statusCode, anyOf(201, 200),
          reason: 'Slot create (201) or update (200) should succeed. '
              'Got: ${response.statusCode}');

      final data = jsonDecode(response.body) as List;
      expect(data.length, 1);
      expect(data[0]['doctor_place_id'], _testPlaceId);
      expect(data[0]['day_of_week'], 'Monday');
      expect(data[0]['schedule_type'], 'video');
      expect(data[0]['fee'], 800);
    });
  });

  // ── Scenario 3: Book appointment ──────────────────────────

  group('Scenario 3: Book appointment', () {
    test('Create an appointment booking (handles duplicate on re-run)',
        () async {
      expect(_testUserId, isNotNull,
          reason: 'User must exist before booking an appointment');

      const aptId = 'E2E_APT_001';
      _testAppointmentId = aptId;

      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final body = {
        'appointment_id': aptId,
        'user_id': _testUserId,
        'patient_name': 'E2E Test Patient',
        'doctor_name': _testDoctorName,
        'doctor_place_id': _testPlaceId,
        'doctor_details': {
          'place_id': _testPlaceId,
          'name': _testDoctorName,
          'rating': 4.5,
          'phone_number': '+919999999991',
        },
        'appointment_date': dateKey,
        'appointment_time': '10:00 AM',
        'symptoms': 'Chest Pain, Shortness of Breath',
        'call_number': '+919999999991',
        'map_location': {
          'latitude': 21.245,
          'longitude': 81.630,
        },
        'status': 'Upcoming',
      };

      // Try POST to create; if 409 (duplicate from a previous run),
      // PATCH to update (keep status as Upcoming).
      var response = await http.post(
        Uri.parse('$_api/appointments'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode(body),
      );

      List<dynamic> data;
      if (response.statusCode == 409) {
        response = await http.patch(
          Uri.parse(
              '$_api/appointments?appointment_id=eq.$aptId'),
          headers: {..._headers(), 'Prefer': 'return=representation'},
          body: jsonEncode({
            'patient_name': 'E2E Test Patient',
            'doctor_name': _testDoctorName,
            'symptoms': 'Chest Pain, Shortness of Breath',
            'status': 'Upcoming',
          }),
        );
        data = jsonDecode(response.body) as List;
      } else {
        expect(response.statusCode, 201,
            reason:
                'Appointment insert should return 201. Got: ${response.statusCode}');
        data = jsonDecode(response.body) as List;
      }

      expect(response.statusCode, anyOf(201, 200),
          reason: 'Appointment create (201) or patch (200) should succeed. '
              'Got: ${response.statusCode}');

      expect(data.length, 1);
      expect(data[0]['appointment_id'], aptId);
      expect(data[0]['patient_name'], 'E2E Test Patient');
      expect(data[0]['doctor_name'], _testDoctorName);
      expect(data[0]['status'], 'Upcoming');
      expect(data[0]['symptoms'], contains('Chest Pain'));
      expect(data[0]['call_number'], '+919999999991');
      expect(data[0]['map_location']['latitude'], 21.245);
      expect(data[0]['doctor_details']['place_id'], _testPlaceId);
    });

    test('Read the appointment back from the database', () async {
      expect(_testUserId, isNotNull);
      expect(_testAppointmentId, isNotNull);

      final response = await http.get(
        Uri.parse(
            '$_api/appointments?appointment_id=eq.$_testAppointmentId'),
        headers: _headers(),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as List;
      expect(data.length, 1);

      final apt = data[0];
      expect(apt['appointment_id'], _testAppointmentId);
      expect(apt['doctor_name'], _testDoctorName);
      expect(apt['patient_name'], 'E2E Test Patient');
      expect(apt['status'], 'Upcoming');
      expect(apt['symptoms'], 'Chest Pain, Shortness of Breath');

      // Verify the created_at timestamp is set
      expect(apt['created_at'], isNotNull);
      final createdAt = DateTime.tryParse(apt['created_at'] as String);
      expect(createdAt, isNotNull,
          reason: 'created_at should be a valid timestamp');
    });

    test('Verify user has the test appointment', () async {
      expect(_testUserId, isNotNull);

      final response = await http.get(
        Uri.parse(
            '$_api/appointments?user_id=eq.$_testUserId&select=appointment_id,status'),
        headers: _headers(),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as List;

      // Find our test appointment among any existing ones
      final testApts =
          data.where((a) => a['appointment_id'] == _testAppointmentId);
      expect(testApts.length, 1,
          reason: 'Test appointment should be present in user appointments');
      expect(testApts.first['status'], 'Upcoming');
    });
  });

  // ── Scenario 4: Cancel appointment ────────────────────────

  group('Scenario 4: Cancel appointment', () {
    test('Cancel the appointment (status → Cancelled)', () async {
      expect(_testAppointmentId, isNotNull);

      final response = await http.patch(
        Uri.parse(
            '$_api/appointments?appointment_id=eq.$_testAppointmentId'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode({'status': 'Cancelled'}),
      );

      expect(response.statusCode, 200,
          reason: 'PATCH should return 200. Got: ${response.statusCode}');

      final data = jsonDecode(response.body) as List;
      expect(data.length, 1);
      expect(data[0]['status'], 'Cancelled');

      // Verify created_at is still preserved
      expect(data[0]['created_at'], isNotNull);
    });

    test('Verify the cancelled status persisted', () async {
      expect(_testAppointmentId, isNotNull);

      final response = await http.get(
        Uri.parse(
            '$_api/appointments?appointment_id=eq.$_testAppointmentId&select=appointment_id,status'),
        headers: _headers(),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as List;
      expect(data.length, 1);
      expect(data[0]['status'], 'Cancelled',
          reason: 'Status should remain Cancelled after persistence');
    });

    test('Verify patching a non-existent ID returns empty result', () async {
      final response = await http.patch(
        Uri.parse(
            '$_api/appointments?appointment_id=eq.NONEXISTENT_APT'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode({'status': 'Cancelled'}),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as List;
      expect(data.length, 0,
          reason: 'No rows should be affected for non-existent ID');
    });
  });

  // ── Scenario 5: Cancel then re-book ───────────────────────

  group('Scenario 5: Cancel then re-book a fresh appointment', () {
    test('Create a second appointment with a new ID', () async {
      expect(_testUserId, isNotNull);

      const aptId2 = 'E2E_APT_002';
      _testAppointmentId = aptId2; // Track the new one for cleanup

      final body = {
        'appointment_id': aptId2,
        'user_id': _testUserId,
        'patient_name': 'E2E Test Patient',
        'doctor_name': _testDoctorName,
        'doctor_place_id': _testPlaceId,
        'doctor_details': {
          'place_id': _testPlaceId,
          'name': _testDoctorName,
        },
        'appointment_date': '2026-08-15',
        'appointment_time': '11:00 AM',
        'symptoms': 'Follow-up Checkup',
        'status': 'Upcoming',
      };

      var response = await http.post(
        Uri.parse('$_api/appointments'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode(body),
      );

      // Handle duplicate on re-run (409 → PATCH)
      if (response.statusCode == 409) {
        response = await http.patch(
          Uri.parse(
              '$_api/appointments?appointment_id=eq.$aptId2'),
          headers: {..._headers(), 'Prefer': 'return=representation'},
          body: jsonEncode({
            'status': 'Upcoming',
            'symptoms': 'Follow-up Checkup',
          }),
        );
      }

      expect(response.statusCode, anyOf(201, 200),
          reason: 'Re-book (201) or patch (200) should succeed. '
              'Got: ${response.statusCode}');

      final data = jsonDecode(response.body) as List;
      expect(data.length, 1);
      expect(data[0]['appointment_id'], aptId2);
      expect(data[0]['status'], 'Upcoming');
      expect(data[0]['symptoms'], 'Follow-up Checkup');
    });

    test('Cancel the second appointment', () async {
      expect(_testAppointmentId, 'E2E_APT_002');

      final response = await http.patch(
        Uri.parse(
            '$_api/appointments?appointment_id=eq.E2E_APT_002'),
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode({'status': 'Cancelled'}),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as List;
      expect(data.length, 1);
      expect(data[0]['status'], 'Cancelled');
    });
  });
}
