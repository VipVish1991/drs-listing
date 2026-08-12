/// Mirrors a row in the `doctor_slots` Supabase table — one consultation
/// type (tele / video / clinic) on one day of the week for one doctor.
class DoctorSlot {
  final String? id;
  final String? userId;
  final String doctorPlaceId;
  final String dayOfWeek;
  final String scheduleType; // 'tele' | 'video' | 'clinic'
  final String startTime; // 24h "HH:MM"
  final String endTime; // 24h "HH:MM"
  final int durationMinutes;
  final int fee;
  final List<String> slots;
  final bool isEnabled;

  /// Standard Supabase row timestamps (ISO 8601 strings parsed to DateTime).
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DoctorSlot({
    this.id,
    this.userId,
    required this.doctorPlaceId,
    required this.dayOfWeek,
    required this.scheduleType,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.fee,
    required this.slots,
    this.isEnabled = true,
    this.createdAt,
    this.updatedAt,
  });

  // ── Type info lookup (emoji / label / subtitle per schedule type) ──

  static const Map<String, Map<String, String>> _typeInfo = {
    'tele': {
      'emoji': '📞',
      'label': 'Tele Consultation',
      'sub': 'Phone Consultation',
    },
    'video': {
      'emoji': '🎥',
      'label': 'Video Consultation',
      'sub': 'Online Video Call',
    },
    'clinic': {
      'emoji': '🏥',
      'label': 'In-Clinic Consultation',
      'sub': 'Physical Appointments',
    },
  };

  /// Human-readable label including emoji, e.g. "📞 Tele Consultation".
  String get typeLabel {
    final info = _typeInfo[scheduleType];
    if (info == null) return scheduleType;
    return '${info['emoji']} ${info['label']}';
  }

  /// Subtitle / short description, e.g. "Phone Consultation".
  String get typeSubtitle => _typeInfo[scheduleType]?['sub'] ?? '';

  /// Just the emoji character, e.g. "📞".
  String get typeEmoji => _typeInfo[scheduleType]?['emoji'] ?? '🩺';

  // ── JSON ──

  factory DoctorSlot.fromJson(Map<String, dynamic> json) {
    return DoctorSlot(
      id: json['id'] as String?,
      userId: json['user_id'] as String?,
      doctorPlaceId: (json['doctor_place_id'] as String?) ?? '',
      dayOfWeek: (json['day_of_week'] as String?) ?? '',
      scheduleType: (json['schedule_type'] as String?) ?? '',
      startTime: (json['start_time'] as String?) ?? '09:00',
      endTime: (json['end_time'] as String?) ?? '12:00',
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 30,
      fee: (json['fee'] as num?)?.toInt() ?? 0,
      slots: (json['slots'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      isEnabled: json['is_enabled'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  /// NOTE: `user_id` is included when non-null so the `user_id` column
  /// (added by migration 20240802000001) gets populated.  When null it is
  /// omitted so the upsert does not send a null value unnecessarily.
  /// `id` is also included when non-null for round-trip fidelity.
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      'doctor_place_id': doctorPlaceId,
      'day_of_week': dayOfWeek,
      'schedule_type': scheduleType,
      'start_time': startTime,
      'end_time': endTime,
      'duration_minutes': durationMinutes,
      'fee': fee,
      'slots': slots,
      'is_enabled': isEnabled,
    };
  }

  // ── copyWith ──

  DoctorSlot copyWith({
    String? id,
    String? userId,
    String? dayOfWeek,
    String? scheduleType,
    String? startTime,
    String? endTime,
    int? durationMinutes,
    int? fee,
    List<String>? slots,
    bool? isEnabled,
  }) {
    return DoctorSlot(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      doctorPlaceId: doctorPlaceId,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      scheduleType: scheduleType ?? this.scheduleType,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      fee: fee ?? this.fee,
      slots: slots ?? this.slots,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
