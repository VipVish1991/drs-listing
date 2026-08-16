import 'package:flutter/widgets.dart';

import '../models/appointment_model.dart';
import '../utils/snackbar_helpers.dart';
import 'launch_service.dart';
import 'meet_consult_service.dart';

/// Web implementation of the Meet consultation flow.
///
/// The vendored `google_meet_sdk` cannot run on web (Google Sign-In needs
/// Firebase web config / native platform channels), so the web build:
///   * opens a STORED meeting link when one exists on the appointment
///     (the room the mobile side created — both sides join the same one);
///   * otherwise reports that the meeting must be started from the mobile
///     app — there is no fixed fallback room and no in-app WebView.
Future<MeetJoinResult> joinConsultation(
  BuildContext context,
  AppointmentModel appointment,
) async {
  // A stored link means the meeting already exists — open that exact room.
  final stored = appointment.meetLink;
  if (stored != null && stored.isNotEmpty) {
    return _openLink(stored);
  }
  showErrorSnackbar(
    'Start the meeting from the mobile app — '
    'the web build cannot create video consultations.',
  );
  return const MeetJoinResult.failure(
    'Meeting creation is only available on the mobile app.',
  );
}

Future<MeetJoinResult> startConsultation(
  BuildContext context, {
  required String title,
}) async {
  showErrorSnackbar(
    'Start the meeting from the mobile app — '
    'the web build cannot create video consultations.',
  );
  return const MeetJoinResult.failure(
    'Meeting creation is only available on the mobile app.',
  );
}

Future<MeetJoinResult> _openLink(String link) async {
  await LaunchService.url(link);
  return MeetJoinResult.success(link);
}
