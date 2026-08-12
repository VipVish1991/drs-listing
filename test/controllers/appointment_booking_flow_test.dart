import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/appointment_model.dart';
import '../helpers/test_data.dart';

void main() {
  group('Appointment Booking Data Flow', () {
    late DoctorModel doctor;

    setUp(() {
      doctor = doctorBasic(
        placeId: 'place_test_1',
        name: 'Dr. Smith',
        rating: 4.5,
        userRatingsTotal: 100,
        latitude: 12.34,
        longitude: 56.78,
        phoneNumber: '+9876543210',
        isOpen: true,
      );
    });

    group('Step 1 — DoctorModel serialization', () {
      test('toJson outputs place_id as snake_case', () {
        final json = doctor.toJson();

        // The doctor dashboard queries use doctor_details->>place_id
        // This MUST be 'place_id' (snake_case), not 'placeId' (camelCase)
        expect(
          json.containsKey('place_id'),
          isTrue,
          reason: 'toJson() must include place_id as snake_case key',
        );
        expect(json['place_id'], 'place_test_1');
      });

      test('toJson does NOT output camelCase placeId', () {
        final json = doctor.toJson();

        // Ensure no accidental camelCase key that would break Supabase queries
        expect(
          json.containsKey('placeId'),
          isFalse,
          reason: 'toJson() must NOT contain camelCase placeId key',
        );
      });
    });

    group('Step 2 — Appointment data construction', () {
      test('doctor_details includes place_id when stored in appointment', () {
        // This simulates what AppointmentController.bookAppointment() does:
        //   'doctor_details': doctor.toJson(),
        //   'doctor_place_id': doctor.placeId,
        final appointmentData = <String, dynamic>{
          'appointment_id': 'APT1001',
          'user_id': 'user_123',
          'patient_name': 'John Doe',
          'doctor_name': doctor.name,
          'doctor_place_id': doctor.placeId,
          'doctor_details': doctor.toJson(),
          'appointment_date': '2026-07-25',
          'appointment_time': '10:00 AM',
          'symptoms': 'Fever and cough',
          'call_number': doctor.phoneNumber,
          'patient_phone': '9876543210',
          'map_location': {
            'latitude': doctor.latitude,
            'longitude': doctor.longitude,
          },
          'status': 'Upcoming',
        };

        // Verify doctor_details is a Map with place_id
        final details =
            appointmentData['doctor_details'] as Map<String, dynamic>;
        expect(
          details['place_id'],
          'place_test_1',
          reason:
              'doctor_details JSON must contain place_id for dashboard queries',
        );

        // Verify doctor_place_id top-level column is present for direct indexed querying
        expect(
          appointmentData['doctor_place_id'],
          'place_test_1',
          reason:
              'doctor_place_id top-level column must be set for efficient dashboard queries',
        );
      });

      test('appointment round-trips through AppointmentModel', () {
        // Simulate storing in Supabase and reading back
        final appointmentData = <String, dynamic>{
          'appointment_id': 'APT1001',
          'user_id': 'user_123',
          'patient_name': 'John Doe',
          'doctor_name': doctor.name,
          'doctor_place_id': doctor.placeId,
          'doctor_details': doctor.toJson(),
          'appointment_date': '2026-07-25',
          'appointment_time': '10:00 AM',
          'symptoms': 'Fever and cough',
          'call_number': doctor.phoneNumber,
          'patient_phone': '9876543210',
          'map_location': {
            'latitude': doctor.latitude,
            'longitude': doctor.longitude,
          },
          'status': 'Upcoming',
          'created_at': '2026-07-20T10:00:00Z',
        };

        // Read back via AppointmentModel.fromJson
        final appointment = AppointmentModel.fromJson(appointmentData);

        expect(appointment.appointmentId, 'APT1001');
        expect(appointment.patientName, 'John Doe');
        expect(appointment.doctorName, 'Dr. Smith');
        expect(appointment.status, 'Upcoming');
        expect(appointment.patientPhone, '9876543210');

        // Verify doctor_details contains place_id
        expect(appointment.doctorDetails, isNotNull);
        expect(appointment.doctorDetails!['place_id'], 'place_test_1');

        // Verify the raw data map includes doctor_place_id for Supabase
        expect(
          appointmentData['doctor_place_id'],
          'place_test_1',
          reason:
              'Top-level doctor_place_id column must be populated in the data sent to Supabase',
        );
      });
    });

    group('Step 3 — Doctor dashboard query compatibility', () {
      test('doctor_details->>place_id can retrieve the doctor place_id', () {
        // Simulate the stored JSON in Supabase (as a Map)
        final appointmentData = <String, dynamic>{
          'appointment_id': 'APT1001',
          'doctor_details': doctor.toJson(),
        };

        // Simulate what Supabase's JSONB ->> operator does:
        // doctor_details->>place_id extracts the value at key 'place_id' as text
        final details =
            appointmentData['doctor_details'] as Map<String, dynamic>;
        final extractedPlaceId = details['place_id']?.toString();

        expect(
          extractedPlaceId,
          'place_test_1',
          reason:
              'Supabase JSONB ->> operator on doctor_details->>place_id must find place_id',
        );
      });

      test(
        'doctor dashboard can construct AppointmentModel from stored data',
        () {
          // Full simulation: create appointment data, store it, read it back
          final storedData = <String, dynamic>{
            'appointment_id': 'APT1001',
            'user_id': 'user_123',
            'patient_name': 'John Doe',
            'doctor_name': 'Dr. Smith',
            'doctor_details': doctor.toJson(),
            'appointment_date': '2026-07-25',
            'appointment_time': '10:00 AM',
            'symptoms': 'Fever',
            'call_number': '+9876543210',
            'map_location': {'latitude': 12.34, 'longitude': 56.78},
            'status': 'Upcoming',
            'created_at': '2026-07-20T10:00:00Z',
          };

          final appointment = AppointmentModel.fromJson(storedData);

          // Verify all fields the doctor dashboard uses
          expect(appointment.patientName, 'John Doe');
          expect(appointment.appointmentDate, '2026-07-25');
          expect(appointment.appointmentTime, '10:00 AM');
          expect(appointment.status, 'Upcoming');
          expect(appointment.symptoms, 'Fever');
          expect(appointment.callNumber, '+9876543210');
          expect(appointment.doctorName, 'Dr. Smith');

          // The doctor dashboard calls getDoctorAppointments() which filters
          // on doctor_details->>place_id. Verify this works:
          final placeIdFromDetails = appointment.doctorDetails?['place_id']
              ?.toString();
          expect(
            placeIdFromDetails,
            'place_test_1',
            reason:
                'Doctor dashboard can filter appointments by doctor_details->>place_id',
          );
        },
      );
    });
  });
}
