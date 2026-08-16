import 'dart:convert';

import '../utils/text_sanitizer.dart';

class AppointmentModel {
  final String appointmentId;
  final String? userId;
  final String? doctorName;
  final String? appointmentDate;
  final String? appointmentTime;
  final Map<String, dynamic>? doctorDetails;

  /// The doctor's Google Place ID for this appointment: the top-level
  /// `doctor_place_id` column when present, falling back to the
  /// `doctor_details` JSONB snapshot for legacy rows written before the
  /// column existed. Used by the per-doctor booking gate to decide
  /// whether this appointment blocks a new booking for a given doctor.
  final String? doctorPlaceId;
  final String? callNumber;

  /// The patient's own mobile number, stored on the appointment at booking
  /// time so the doctor side can call the patient without touching the
  /// (RLS-locked) users table. Null for legacy rows created before the
  /// `patient_phone` column existed.
  final String? patientPhone;
  final Map<String, dynamic>? mapLocation;
  final String? symptoms;
  final String? patientName;

  /// Shared Google Meet URL for this video/tele consultation. Null until
  /// either side starts the meeting (the SDK flow saves the created
  /// `meet.google.com/<id>` link here) — afterwards BOTH sides join the
  /// same room from the details sheet.
  final String? meetLink;
  final String status;
  final DateTime? createdAt;

  /// Booking schedule type: 'tele' | 'video' | 'clinic'. Null for legacy
  /// rows created before the column existed. The doctor side offers the
  /// prescription upload only for tele/video consultations.
  final String? consultationType;

  /// Public Supabase Storage URLs of uploaded prescription photos.
  /// Empty for appointments without a prescription yet.
  final List<String> prescriptionUrls;

  /// Appointment date formatted for display as `dd-MM-yyyy` (e.g.
  /// "08-08-2026"), the format used across the app's UI. The raw
  /// [appointmentDate] stays `yyyy-MM-dd` for sorting/filtering.
  /// Falls back to the raw value if it isn't a parseable `yyyy-MM-dd`.
  String? get displayDate {
    final raw = appointmentDate;
    if (raw == null || raw.isEmpty) return raw;
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return raw;
    return '${d.toString().padLeft(2, '0')}-${m.toString().padLeft(2, '0')}-$y';
  }

  /// Whether this appointment was a remote (Tele or Video) consultation —
  /// the only types where the doctor can attach a prescription.
  bool get isRemoteConsultation =>
      consultationType == 'tele' || consultationType == 'video';

  /// Human-readable label for [consultationType] (matches the booking
  /// screen's labels): 'Tele Consultation' | 'Video Consultation' |
  /// 'In-Clinic Visit'. Null for legacy rows without a stored type.
  String? get consultationTypeLabel {
    switch (consultationType) {
      case 'tele':
        return 'Tele Consultation';
      case 'video':
        return 'Video Consultation';
      case 'clinic':
        return 'In-Clinic Visit';
      default:
        return null;
    }
  }

  String? get doctorSpecialization =>
      TextSanitizer.sanitize(doctorDetails?['specialization']?.toString());

  AppointmentModel({
    required this.appointmentId,
    this.userId,
    this.doctorName,
    this.appointmentDate,
    this.appointmentTime,
    this.doctorDetails,
    this.doctorPlaceId,
    this.callNumber,
    this.patientPhone,
    this.mapLocation,
    this.symptoms,
    this.patientName,
    this.meetLink,
    this.status = 'Upcoming',
    this.createdAt,
    this.consultationType,
    this.prescriptionUrls = const [],
  });

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    final doctorDetails = json['doctor_details'] is Map
        ? Map<String, dynamic>.from(json['doctor_details'])
        : null;
    // Sanitize free-text fields so a bad-UTF-16 payload from the DB
    // can never crash the text engine when the card is painted.
    if (doctorDetails != null) {
      for (final key in doctorDetails.keys.toList()) {
        final v = doctorDetails[key];
        if (v is String) doctorDetails[key] = TextSanitizer.sanitize(v);
      }
    }
    // Prefer the top-level column; legacy rows fall back to the JSONB
    // snapshot (both could be empty strings for very old data).
    final rawDoctorPlaceId = json['doctor_place_id']?.toString() ?? '';
    final doctorPlaceId = rawDoctorPlaceId.isNotEmpty
        ? rawDoctorPlaceId
        : (doctorDetails?['place_id']?.toString() ?? '');
    return AppointmentModel(
      appointmentId: json['appointment_id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      doctorName: TextSanitizer.sanitize(json['doctor_name']?.toString()),
      appointmentDate: TextSanitizer.sanitize(
        json['appointment_date']?.toString(),
      ),
      appointmentTime: TextSanitizer.sanitize(
        json['appointment_time']?.toString(),
      ),
      doctorDetails: doctorDetails,
      doctorPlaceId: doctorPlaceId,
      callNumber: TextSanitizer.sanitize(json['call_number']?.toString()),
      patientPhone: TextSanitizer.sanitize(json['patient_phone']?.toString()),
      mapLocation: json['map_location'] is Map
          ? Map<String, dynamic>.from(json['map_location'])
          : null,
      symptoms: TextSanitizer.sanitize(json['symptoms']?.toString()),
      patientName: TextSanitizer.sanitize(json['patient_name']?.toString()),
      // Sanitize, then collapse an empty value to null so "no room set"
      // reads consistently (the sheet/service check isNotEmpty on this).
      meetLink: () {
        final raw = TextSanitizer.sanitize(json['meet_link']?.toString());
        return raw.isEmpty ? null : raw;
      }(),
      status: json['status']?.toString() ?? 'Upcoming',
      consultationType: json['consultation_type']?.toString().isNotEmpty == true
          ? json['consultation_type'].toString()
          : null,
      prescriptionUrls: _parsePrescriptionUrls(json['upload_prescription']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  /// Parses the `upload_prescription` DB value (TEXT[]) into a list of
  /// URL strings. PostgREST returns arrays as JSON lists, but a defensive
  /// string fallback (e.g. a single URL stored as TEXT) is also handled.
  static List<String> _parsePrescriptionUrls(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final str = raw.toString().trim();
    if (str.isEmpty || str == '{}') return const [];
    // Very defensive: a single plain URL (not JSON-array) → one element.
    if (!str.startsWith('[')) return [str];
    try {
      final list = (jsonDecode(str) as List)
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return list;
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'appointment_id': appointmentId,
      'user_id': userId,
      'doctor_name': doctorName,
      'appointment_date': appointmentDate,
      'appointment_time': appointmentTime,
      'doctor_details': doctorDetails,
      'call_number': callNumber,
      'patient_phone': patientPhone,
      'map_location': mapLocation,
      'symptoms': symptoms,
      'patient_name': patientName,
      if (meetLink != null && meetLink!.isNotEmpty) 'meet_link': meetLink,
      'status': status,
      'consultation_type': consultationType,
      if (prescriptionUrls.isNotEmpty) 'upload_prescription': prescriptionUrls,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  AppointmentModel copyWith({
    String? status,
    List<String>? prescriptionUrls,
    String? meetLink,
  }) {
    return AppointmentModel(
      appointmentId: appointmentId,
      userId: userId,
      doctorName: doctorName,
      appointmentDate: appointmentDate,
      appointmentTime: appointmentTime,
      doctorDetails: doctorDetails,
      callNumber: callNumber,
      patientPhone: patientPhone,
      mapLocation: mapLocation,
      symptoms: symptoms,
      patientName: patientName,
      meetLink: meetLink ?? this.meetLink,
      status: status ?? this.status,
      consultationType: consultationType,
      prescriptionUrls: prescriptionUrls ?? this.prescriptionUrls,
      createdAt: createdAt,
    );
  }
}

class AppointmentStatus {
  static const String pending = 'Pending';
  static const String upcoming = 'Upcoming';
  static const String completed = 'Completed';
  static const String cancelled = 'Cancelled';

  /// Whether an appointment with [status] still occupies (disables) its
  /// booked time slot. Every appointment status keeps the slot locked —
  /// only a Cancelled appointment frees it again. This is the single
  /// shared rule used by the patient booking screen (slot chips) and the
  /// doctor dashboard (booked-slot counts), so both sides always agree.
  static bool occupiesSlot(String status) => status != cancelled;

  /// Whether an appointment with [status] can be moved to a different
  /// slot — the patient reschedule chip + details-sheet action and the
  /// doctor's patient-history Reschedule action all use this ONE rule so
  /// the entry points can never drift apart. Only Pending/Upcoming rows
  /// can be moved; Completed / Cancelled cannot.
  ///
  /// Callers pass the EFFECTIVE status
  /// ([AppointmentController.effectiveStatus]) so an Upcoming appointment
  /// whose time has passed (rendered as Completed) is never reschedulable.
  static bool isReschedulable(String status) =>
      status == upcoming || status == pending;
}
