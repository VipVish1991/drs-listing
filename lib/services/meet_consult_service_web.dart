import 'package:flutter/widgets.dart';

import '../models/appointment_model.dart';
import 'launch_service.dart';
import 'meet_consult_service.dart';
import 'room_allocation_service.dart';

/// Web implementation of the Meet consultation flow.
///
/// Before opening a room, the service checks the meeting_rooms pool in
/// Supabase to ensure only 2 people (doctor + patient) join the same room
/// at a time. Falls back to the stored link or the static room if the pool
/// is exhausted.
Future<MeetJoinResult> joinConsultation(
  BuildContext context,
  AppointmentModel appointment,
) async {
  final roomUrl = await RoomAllocationService.instance.allocateRoom(
    appointmentId: appointment.appointmentId,
    existingMeetLink: appointment.meetLink,
  );

  return _openLink(roomUrl);
}

Future<MeetJoinResult> startConsultation(
  BuildContext context, {
  required String title,
}) async {
  final roomUrl = await RoomAllocationService.instance.allocateRoom(
    appointmentId: 'adhoc_${DateTime.now().millisecondsSinceEpoch}',
    existingMeetLink: kStaticMeetLink,
  );
  return _openLink(roomUrl);
}

Future<MeetJoinResult> _openLink(String link) async {
  await LaunchService.url(link);
  return MeetJoinResult.success(link);
}
