class UserModel {
  final String? id;
  final String? name;
  final String? mobile;
  final String role;
  final DateTime? createdAt;
  /// The Google Place ID of the clinic/doctor this user is connected to,
  /// if they are a doctor.  Used on app relaunch to load the correct
  /// doctor profile into DoctorController.
  final String? doctorPlaceId;
  /// Account status: FALSE = admin-deactivated, login is blocked and the
  /// app shows "Your account is inactive" instead of letting the user in.
  /// Defaults to TRUE so legacy/local rows never lock a user out.
  final bool isActive;

  static const String rolePatient = 'patient';
  static const String roleDoctor = 'doctor';

  UserModel({
    this.id,
    this.name,
    this.mobile,
    this.role = rolePatient,
    this.createdAt,
    this.doctorPlaceId,
    this.isActive = true,
  });

  bool get isDoctor => role == roleDoctor;
  bool get isPatient => role == rolePatient;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString(),
      name: json['name']?.toString(),
      mobile: json['mobile']?.toString(),
      role: json['role']?.toString() ?? rolePatient,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      doctorPlaceId: json['doctor_place_id']?.toString(),
      // A missing column (pre-migration rows) must read as ACTIVE, never
      // lock a user out.
      isActive: json['is_active'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'mobile': mobile,
      'role': role,
      'created_at': createdAt?.toIso8601String(),
      if (doctorPlaceId != null) 'doctor_place_id': doctorPlaceId,
      'is_active': isActive,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? mobile,
    String? role,
    DateTime? createdAt,
    String? doctorPlaceId,
    bool? isActive,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      doctorPlaceId: doctorPlaceId ?? this.doctorPlaceId,
      isActive: isActive ?? this.isActive,
    );
  }
}
