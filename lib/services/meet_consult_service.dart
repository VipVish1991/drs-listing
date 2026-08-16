import 'package:flutter/widgets.dart';

import '../models/appointment_model.dart';
import 'meet_consult_service_web.dart'
    if (dart.library.io) 'meet_consult_service_io.dart' as impl;

/// Result of a join-meeting attempt.
class MeetJoinResult {
  final bool success;
  final String? meetingLink;
  final String? error;

  const MeetJoinResult.success(this.meetingLink)
      : success = true,
        error = null;

  const MeetJoinResult.failure(this.error)
      : success = false,
        meetingLink = null;
}

/// Facade over the platform-specific Google Meet consultation flow.
///
/// On mobile ([meet_consult_service_io]) the flow uses the vendored
/// `google_meet_sdk`: Google Sign-In → create a Meet-backed calendar event
/// → open the returned `meet.google.com/<id>` link in the browser/Meet app
/// (the SDK has no in-app meeting view). On web the SDK can't run (Google
/// Sign-In needs Firebase web config), so the web implementation only
/// opens a meeting link that was already stored on the appointment — the
/// meeting itself must be created from the mobile app.
class MeetConsultService {
  MeetConsultService._();

  /// Joins the consultation for [appointment] (video/tele only — callers
  /// gate on [AppointmentModel.isRemoteConsultation]).
  ///
  /// Returns a [MeetJoinResult]: success carries the meeting link that was
  /// opened, failure carries a user-facing message (a snackbar is also
  /// shown by the implementation).
  static Future<MeetJoinResult> joinConsultation(
    BuildContext context,
    AppointmentModel appointment,
  ) {
    return impl.joinConsultation(context, appointment);
  }

  /// Starts a fresh consultation from an entry point that has no
  /// appointment (e.g. the doctor's own profile screen) — same Google
  /// Sign-In → calendar event → external link flow, with a now→+30 min
  /// window and [title] as the calendar event title.
  static Future<MeetJoinResult> startConsultation(
    BuildContext context, {
    required String title,
  }) {
    return impl.startConsultation(context, title: title);
  }
}
