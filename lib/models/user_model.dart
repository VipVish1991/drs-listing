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

  static const String rolePatient = 'patient';
  static const String roleDoctor = 'doctor';

  UserModel({
    this.id,
    this.name,
    this.mobile,
    this.role = rolePatient,
    this.createdAt,
    this.doctorPlaceId,
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
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? mobile,
    String? role,
    DateTime? createdAt,
    String? doctorPlaceId,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      doctorPlaceId: doctorPlaceId ?? this.doctorPlaceId,
    );
  }
}
