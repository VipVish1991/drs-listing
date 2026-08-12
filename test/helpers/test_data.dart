import 'package:DrsListing/models/ai_response_model.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/models/doctor_slot_model.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/models/unavailable_range.dart';
import 'package:DrsListing/utils/time_slot_generator.dart';
import 'package:DrsListing/models/user_model.dart';

/// Factory helpers that return minimal, predictable instances of domain
/// models so tests stay concise and DRY.

// ── ChatMessage factories ────────────────────────────────────────────

ChatMessage chatMessageUser({
  String text = 'I have a fever',
  DateTime? timestamp,
}) {
  return ChatMessage(text: text, isUser: true, timestamp: timestamp);
}

ChatMessage chatMessageAi({
  String text = 'You may have a common cold. Consult a General Physician.',
  AiResponseModel? analysis,
  DateTime? timestamp,
}) {
  return ChatMessage(
    text: text,
    isUser: false,
    analysis: analysis,
    timestamp: timestamp,
  );
}

// ── AiResponseModel factories ────────────────────────────────────────

AiResponseModel analysisCardiologist() {
  return AiResponseModel(
    specialist: 'Cardiologist',
    symptoms: ['chest pain', 'shortness of breath'],
    explanation: 'Your symptoms suggest a possible heart condition.',
    severity: 'moderate',
    recommendation: 'Please consult a Cardiologist soon.',
  );
}

AiResponseModel analysisNeurologist() {
  return AiResponseModel(
    specialist: 'Neurologist',
    symptoms: ['headache', 'dizziness'],
    explanation: 'You may be experiencing migraines.',
    severity: 'mild',
    recommendation: 'A Neurologist can help diagnose your condition.',
  );
}

AiResponseModel analysisGeneralPhysician() {
  return AiResponseModel(
    specialist: 'General Physician',
    symptoms: ['fever', 'cough'],
    explanation: 'You likely have a common viral infection.',
    severity: 'mild',
    recommendation: 'Rest and stay hydrated. Consult a GP if symptoms persist.',
  );
}

// ── DoctorModel factories ────────────────────────────────────────────

DoctorModel doctorBasic({
  String placeId = 'place_test_1',
  String name = 'Dr. Smith',
  double rating = 4.5,
  int userRatingsTotal = 100,
  double? latitude = 12.34,
  double? longitude = 56.78,
  String? phoneNumber = '+9876543210',
  bool? isOpen = true,
  List<String> types = const [],
  String? address = '123 Main St, City',
  List<UnavailableRange> unavailableRanges = const [],
}) {
  return DoctorModel(
    placeId: placeId,
    name: name,
    rating: rating,
    userRatingsTotal: userRatingsTotal,
    latitude: latitude,
    longitude: longitude,
    phoneNumber: phoneNumber,
    isOpen: isOpen,
    address: address,
    types: types,
    unavailableRanges: unavailableRanges,
  );
}

/// Minimal doctor — only has placeId and name (edge case).
DoctorModel doctorMinimal() {
  return DoctorModel(placeId: 'minimal', name: 'Dr. Minimal');
}

// ── DoctorSlot factories ─────────────────────────────────────────────

DoctorSlot doctorSlotBasic({
  String? id,
  String doctorPlaceId = 'place_test_1',
  String dayOfWeek = 'Monday',
  String scheduleType = 'video',
  String startTime = '09:00',
  String endTime = '12:00',
  int durationMinutes = 30,
  int fee = 800,
  bool isEnabled = true,
  List<String> slots = const [
    '9:00 AM',
    '9:30 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '11:30 AM',
  ],
}) {
  return DoctorSlot(
    id: id,
    doctorPlaceId: doctorPlaceId,
    dayOfWeek: dayOfWeek,
    scheduleType: scheduleType,
    startTime: startTime,
    endTime: endTime,
    durationMinutes: durationMinutes,
    fee: fee,
    slots: slots,
    isEnabled: isEnabled,
  );
}

/// Creates a full set of 7 days x 3 schedule types for integration-style tests.
List<DoctorSlot> doctorWeeklySlots(String doctorPlaceId) {
  final days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final types = ['tele', 'video', 'clinic'];
  final slots = <DoctorSlot>[];
  for (final day in days) {
    for (final type in types) {
      slots.add(
        DoctorSlot(
          doctorPlaceId: doctorPlaceId,
          dayOfWeek: day,
          scheduleType: type,
          startTime: '09:00',
          endTime: '17:00',
          durationMinutes: 30,
          fee: type == 'tele'
              ? 500
              : type == 'video'
              ? 800
              : 1000,
          slots: generateTimeSlots('09:00', '17:00', 30),
          isEnabled: true,
        ),
      );
    }
  }
  return slots;
}

// ── AppointmentModel factories ───────────────────────────────────────

AppointmentModel appointmentBasic({
  String appointmentId = 'APT1001',
  String? patientName = 'John Doe',
  String? doctorName = 'Dr. Smith',
  String? appointmentDate = '2026-07-25',
  String? appointmentTime = '10:00 AM',
  String status = 'Upcoming',
  String? doctorPlaceId = 'place_test_1',
  String? symptoms,
  String? callNumber,
  String? patientPhone,
  String? consultationType,
  List<String> prescriptionUrls = const [],
  DateTime? createdAt,
}) {
  return AppointmentModel(
    appointmentId: appointmentId,
    patientName: patientName,
    doctorName: doctorName,
    appointmentDate: appointmentDate,
    appointmentTime: appointmentTime,
    status: status,
    symptoms: symptoms,
    callNumber: callNumber,
    patientPhone: patientPhone,
    consultationType: consultationType,
    prescriptionUrls: prescriptionUrls,
    doctorDetails: doctorPlaceId != null
        ? {'place_id': doctorPlaceId, 'name': doctorName}
        : null,
    createdAt: createdAt,
  );
}

// ── User factories ───────────────────────────────────────────────────

UserModel userPatient({
  String? id = 'user_123',
  String? name = 'John Patient',
  String? mobile = '9876543210',
}) {
  return UserModel(
    id: id,
    name: name,
    mobile: mobile,
    role: UserModel.rolePatient,
  );
}

UserModel userDoctor({
  String? id = 'user_456',
  String? name = 'Dr. Jane',
  String? mobile = '9876543211',
}) {
  return UserModel(
    id: id,
    name: name,
    mobile: mobile,
    role: UserModel.roleDoctor,
  );
}

// ── Google Places API JSON factories (legacy) ─────────────────────────

/// Minimal "result" object as returned by the Google Places Text Search
/// API. Kept for testing the legacy [DoctorModel.fromGooglePlaces] factory
/// which is still used to parse data stored in Supabase.
Map<String, dynamic> placesResultJson({
  String placeId = 'gplaces_1',
  String name = 'City Hospital',
  double lat = 12.34,
  double lng = 56.78,
  double rating = 4.2,
  int userRatingsTotal = 200,
}) {
  return {
    'place_id': placeId,
    'name': name,
    'geometry': {
      'location': {'lat': lat, 'lng': lng},
    },
    'rating': rating,
    'user_ratings_total': userRatingsTotal,
    'types': ['hospital', 'health'],
    'formatted_address': '456 Health Ave, City',
    'vicinity': '456 Health Ave',
    'business_status': 'OPERATIONAL',
    'opening_hours': {'open_now': true},
    'photos': [
      {
        'photo_reference': 'ref1',
        'height': 200,
        'width': 400,
        'html_attributions': [],
      },
    ],
  };
}

/// Minimal "result" object for a doctor place (types contains "doctor").
Map<String, dynamic> placesDoctorJson({String name = 'Dr. Jane'}) {
  return {
    ...placesResultJson(name: name),
    'types': ['doctor', 'health'],
    'formatted_phone_number': '+1122334455',
  };
}
