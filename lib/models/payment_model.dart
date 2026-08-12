/// Mirrors a row in the `payments` Supabase table — one consultation fee
/// payment per appointment (UPI online or offline pay-at-clinic).
class PaymentModel {
  final String? id;
  final String appointmentId;
  final String patientId;
  /// The patient's display name — NOT a payments column. Populated from
  /// the embedded `appointments(patient_name)` join on doctor-side reads
  /// ([SupabaseService.getPaymentsForDoctor]) so the clinic's payment list
  /// can lead with the patient. Never sent to the DB ([toJson] omits it).
  final String? patientName;
  final String? doctorPlaceId;
  final String? doctorName;
  final String? consultationType; // 'tele' | 'video' | 'clinic'
  final String paymentType; // 'consultation'
  final String paymentStatus; // 'Pending' | 'Paid' | 'Failed' | 'Refunded'
  final String paymentMethod; // 'online' | 'offline'
  final double amount;
  final String currency;
  final String? transactionId; // UPI txnId / approval ref (online only)
  final String? upiId; // receiver (merchant) UPI VPA
  final DateTime? paidAt;
  final DateTime? createdAt;

  const PaymentModel({
    this.id,
    // Filled by the booking controller once the appointment id exists.
    this.appointmentId = '',
    required this.patientId,
    this.patientName,
    this.doctorPlaceId,
    this.doctorName,
    this.consultationType,
    this.paymentType = 'consultation',
    this.paymentStatus = 'Pending',
    this.paymentMethod = 'offline',
    this.amount = 0,
    this.currency = 'INR',
    this.transactionId,
    this.upiId,
    this.paidAt,
    this.createdAt,
  });

  // ── Readable helpers ─────────────────────────────────────────

  /// Whether the payment was settled (Paid) or is still outstanding.
  bool get isPaid => paymentStatus == 'Paid';

  /// Human-readable payment method: 'Online (UPI)' / 'Offline (Clinic)'.
  String get paymentMethodLabel =>
      paymentMethod == 'online' ? 'Online (UPI)' : 'Offline (Clinic)';

  /// Human-readable consultation type (matches the booking screen's
  /// labels): 'Tele Consultation' | 'Video Consultation' |
  /// 'In-Clinic Visit'. Null for unknown/legacy rows.
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

  /// '₹500' formatted amount.
  String get amountLabel => '₹${formatAmount(amount)}';

  /// Formats a money amount as a plain ₹-less number: 800 → "800",
  /// 800.5 → "800.50" (whole amounts drop the decimals, like the app's
  /// other money surfaces). Public so the doctor dashboard can reuse the
  /// exact same formatting for the summed income figure.
  static String formatAmount(double amount) {
    final isWhole = amount == amount.roundToDouble();
    return isWhole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  }

  // ── JSON ─────────────────────────────────────────────────────

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id']?.toString(),
      appointmentId: json['appointment_id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      patientName: _patientNameFrom(json),
      doctorPlaceId: json['doctor_place_id']?.toString(),
      doctorName: json['doctor_name']?.toString(),
      consultationType: json['consultation_type']?.toString(),
      paymentType: json['payment_type']?.toString() ?? 'consultation',
      paymentStatus: json['payment_status']?.toString() ?? 'Pending',
      paymentMethod: json['payment_method']?.toString() ?? 'offline',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency']?.toString() ?? 'INR',
      transactionId: json['transaction_id']?.toString(),
      upiId: json['upi_id']?.toString(),
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  /// Reads `patient_name` from the embedded `appointments` join. PostgREST
  /// returns many-to-one embeds (payments.appointment_id → appointments)
  /// as a SINGLE object — `appointments: { patient_name }` — verified
  /// against the live project. The list form (`[{ patient_name }]`) is
  /// handled defensively too. Null when the row was fetched without the
  /// join (patient-side reads) or the appointment is missing.
  static String? _patientNameFrom(Map<String, dynamic> json) {
    final apts = json['appointments'];
    if (apts is Map) return apts['patient_name']?.toString();
    if (apts is List && apts.isNotEmpty) {
      final first = apts.first;
      if (first is Map) return first['patient_name']?.toString();
    }
    return null;
  }

  /// Snake_case payload for the Supabase `payments` table. `id` is omitted
  /// (generated by the DB); `created_at`/`updated_at` default server-side.
  /// `patientName` is a join-only field and deliberately never sent.
  Map<String, dynamic> toJson() {
    return {
      'appointment_id': appointmentId,
      'patient_id': patientId,
      if (doctorPlaceId != null) 'doctor_place_id': doctorPlaceId,
      if (doctorName != null) 'doctor_name': doctorName,
      if (consultationType != null) 'consultation_type': consultationType,
      'payment_type': paymentType,
      'payment_status': paymentStatus,
      'payment_method': paymentMethod,
      'amount': amount,
      'currency': currency,
      if (transactionId != null) 'transaction_id': transactionId,
      if (upiId != null) 'upi_id': upiId,
      if (paidAt != null) 'paid_at': paidAt!.toUtc().toIso8601String(),
    };
  }

  PaymentModel copyWith({
    String? appointmentId,
    String? paymentStatus,
    String? transactionId,
    DateTime? paidAt,
  }) {
    return PaymentModel(
      id: id,
      appointmentId: appointmentId ?? this.appointmentId,
      patientId: patientId,
      doctorPlaceId: doctorPlaceId,
      doctorName: doctorName,
      consultationType: consultationType,
      paymentType: paymentType,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod,
      amount: amount,
      currency: currency,
      transactionId: transactionId ?? this.transactionId,
      upiId: upiId,
      paidAt: paidAt ?? this.paidAt,
      createdAt: createdAt,
    );
  }
}
