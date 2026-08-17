import 'package:flutter/widgets.dart';

import '../models/appointment_model.dart';
import 'meet_consult_service_web.dart'
    if (dart.library.io) 'meet_consult_service_io.dart' as impl;

/// The single static Google Meet room shared by every consultation in the
/// app. New appointments are created with this link pre-filled in their
/// `meet_link` column (Flutter app + booking-page Edge Function), and both
/// the Join and Start flows open exactly this room — no per-meeting Google
/// Calendar event is created anymore.
const String kStaticMeetLink = 'https://meet.google.com/rnz-wivx-yze';

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
/// Every consultation uses ONE fixed static room — [kStaticMeetLink] — so
/// the patient and the clinic always end up in the same meeting. On mobile
/// ([meet_consult_service_io]) and web the flow simply opens that room
/// (the link stored on the appointment when one exists, the static link
/// otherwise). No Google Sign-In or calendar-event creation is involved.
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
