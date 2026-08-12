/// A single entry in the in-app notification center — one row from the
/// `notifications` table, written by the notifications Edge Function
/// whenever it sends a push, read by the app to show the history.
class NotificationItem {
  final String id;
  // appointment_booked | appointment_cancelled | appointment_rescheduled |
  // appointment_rescheduled_by_doctor | appointment_status_changed
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic> data; // deep-link payload
  final bool read;
  final DateTime createdAt;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.data = const {},
    this.read = false,
    required this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString(),
      data: json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : const {},
      read: json['read'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String? get appointmentId => data['appointment_id']?.toString();
  String? get doctorPlaceId => data['doctor_place_id']?.toString();
  String? get status => data['status']?.toString();

  /// The doctor/clinic this alert is about — written by the Edge Function
  /// into the payload so the card can show it without a DB lookup.
  String? get doctorName {
    final v = data['doctor_name']?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// True for events that belong on the DOCTOR's dashboard (new booking /
  /// patient cancel / patient reschedule) rather than the patient's
  /// appointment history.
  bool get isDoctorEvent =>
      type == 'appointment_booked' ||
      type == 'appointment_cancelled' ||
      type == 'appointment_rescheduled';

  /// Human label of the screen a tap on this notification opens.
  String get destinationLabel =>
      isDoctorEvent ? 'Opens Doctor Dashboard' : 'Opens Appointment History';
}
