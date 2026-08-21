import 'package:flutter/material.dart';

import '../models/appointment_model.dart';
import '../utils/snackbar_helpers.dart';
import 'launch_service.dart';
import 'meet_consult_service.dart';
import 'room_allocation_service.dart';

/// Mobile implementation of the Meet consultation flow.
///
/// Before opening a room, the service checks the meeting_rooms pool in
/// Supabase to ensure only 2 people (doctor + patient) join the same room
/// at a time. If the allocated room is already occupied by another
/// consultation, a free room is assigned. Rooms are auto-freed after
/// [kRoomAllocationTtl] or when the doctor marks the appointment Complete.
Future<MeetJoinResult> joinConsultation(
  BuildContext context,
  AppointmentModel appointment,
) async {
  // Allocate a room from the pool (or reuse the one already assigned to
  // this appointment). Falls back to the stored link or the static room
  // if the pool is exhausted.
  final roomUrl = await RoomAllocationService.instance.allocateRoom(
    appointmentId: appointment.appointmentId,
    existingMeetLink: appointment.meetLink,
  );

  return _openStoredLink(roomUrl);
}

/// Opens a previously saved meeting link (no sign-in, no event creation).
Future<MeetJoinResult> _openStoredLink(String link) async {
  try {
    await LaunchService.url(link);
    return MeetJoinResult.success(link);
  } catch (e) {
    debugPrint('Meet stored-link open error: $e');
    showErrorSnackbar('Could not open the meeting link.');
    return const MeetJoinResult.failure('Could not open the meeting link.');
  }
}

/// Starts a fresh consultation from an entry point that has no
/// appointment (e.g. the doctor's own profile screen) — always opens a
/// room from the pool (or the static fallback).
Future<MeetJoinResult> startConsultation(
  BuildContext context, {
  required String title,
}) async {
  final roomUrl = await RoomAllocationService.instance.allocateRoom(
    appointmentId: 'adhoc_${DateTime.now().millisecondsSinceEpoch}',
    existingMeetLink: kStaticMeetLink,
  );
  return _openStoredLink(roomUrl);
}
