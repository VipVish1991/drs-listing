import 'package:flutter/widgets.dart';

import '../models/appointment_model.dart';
import 'launch_service.dart';
import 'meet_consult_service.dart';

/// Web implementation of the Meet consultation flow.
///
/// The vendored `google_meet_sdk` cannot run on web, but every
/// consultation uses the same fixed static room — [kStaticMeetLink] —
/// pre-filled on new appointments, so the web build simply opens that
/// room (the stored link when one exists, the static link otherwise).
Future<MeetJoinResult> joinConsultation(
  BuildContext context,
  AppointmentModel appointment,
) async {
  // A stored link means the meeting already exists — open that exact room.
  // Legacy rows without one fall back to the static room so every meeting
  // still lands in the same place.
  final stored = appointment.meetLink;
  if (stored != null && stored.isNotEmpty) {
    return _openLink(stored);
  }
  return _openLink(kStaticMeetLink);
}

Future<MeetJoinResult> startConsultation(
  BuildContext context, {
  required String title,
}) async {
  return _openLink(kStaticMeetLink);
}

Future<MeetJoinResult> _openLink(String link) async {
  await LaunchService.url(link);
  return MeetJoinResult.success(link);
}
