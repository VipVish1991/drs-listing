import 'package:flutter/material.dart';

import '../models/appointment_model.dart';
import '../utils/snackbar_helpers.dart';
import 'launch_service.dart';
import 'meet_consult_service.dart';

/// Mobile implementation of the Meet consultation flow.
///
/// Every consultation in the app uses ONE fixed static room —
/// [kStaticMeetLink] — instead of creating a fresh Google Calendar event
/// per meeting. Joining always opens that room externally (browser / Meet
/// app): the link stored on the appointment when one exists (new
/// appointments are created with it pre-filled), the static link
/// otherwise (legacy rows). No Google Sign-In or Calendar API is involved
/// anymore.
Future<MeetJoinResult> joinConsultation(
  BuildContext context,
  AppointmentModel appointment,
) {
  // A stored link means the meeting already exists — JOIN that same room
  // (new appointments carry the static link from creation). Fall back to
  // the static room for legacy rows with no stored link, so EVERY meeting
  // still lands in the same place.
  final stored = appointment.meetLink;
  if (stored != null && stored.isNotEmpty) {
    return _openStoredLink(stored);
  }
  return _openStoredLink(kStaticMeetLink);
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
/// appointment (e.g. the doctor's own profile screen) — always opens the
/// static meeting room [kStaticMeetLink].
Future<MeetJoinResult> startConsultation(
  BuildContext context, {
  required String title,
}) {
  return _openStoredLink(kStaticMeetLink);
}
