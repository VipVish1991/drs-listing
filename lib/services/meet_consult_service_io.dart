import 'package:flutter/material.dart';
import 'package:google_meet_sdk/google_meet_sdk.dart';
import 'package:intl/intl.dart';

import '../models/appointment_model.dart';
import '../utils/snackbar_helpers.dart';
import 'launch_service.dart';
import 'meet_consult_service.dart';

/// GCP OAuth web client ID (from android/app/google-services.json,
/// `oauth_client` with client_type 3). google_sign_in on Android uses this
/// web client ID; the SDK reads it from [GoogleAuthentication.clientId]
/// (the vendored copy patches out the upstream manifest read).
const String kMeetConsultClientId =
    '450216527653-nptvtf6lkspa65sgmh358qm7mjq3ccog.apps.googleusercontent.com';

/// The Google API surface the Meet flow depends on, abstracted so the flow
/// can be unit-tested without the real Firebase / Google Sign-In /
/// Calendar plugins (which need platform channels a VM test can't provide).
///
/// The default [SdkMeetFlowGateway] wraps the vendored `google_meet_sdk`;
/// tests swap [meetFlowGateway] for a fake.
abstract class MeetFlowGateway {
  /// Signs the user in with Google. Returns `true` on success, `false` on
  /// cancel/failure (the SDK shows its own snackbar in that case).
  Future<bool> signIn(BuildContext context);

  /// Creates a Meet-backed calendar event. Returns an id + link map
  /// (`'id'` and `'link'` keys, link like
  /// `https://meet.google.com/confId`) on success, `null` on failure.
  Future<Map<String, String>?> createEvent({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
  });
}

/// The active gateway — production uses the SDK implementation, tests
/// replace it with a fake. (Top-level mutable so the flow functions stay
/// plain; the facade [MeetConsultService] picks this file on mobile.)
MeetFlowGateway meetFlowGateway = SdkMeetFlowGateway();

/// Default gateway backed by the vendored `google_meet_sdk`.
class SdkMeetFlowGateway implements MeetFlowGateway {
  @override
  Future<bool> signIn(BuildContext context) async {
    // Configure the OAuth client once (idempotent).
    GoogleAuthentication.clientId = kMeetConsultClientId;
    final user = await GoogleAuthentication.signInWithGoogle(
      context: context,
    );
    return user != null;
  }

  @override
  Future<Map<String, String>?> createEvent({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
  }) {
    return CalendarClient().insert(
      title: title,
      description: description,
      location: 'Online consultation',
      attendeeEmailList: const [],
      shouldNotifyAttendees: false,
      hasConferenceSupport: true,
      startTime: startTime,
      endTime: endTime,
    );
  }
}

/// Mobile implementation of the Meet consultation flow backed by the
/// vendored `google_meet_sdk`:
///
///   1. Google Sign-In (requesting the Calendar scopes the SDK needs).
///   2. Create a calendar event with a Meet conference on the user's
///      primary calendar.
///   3. Open the returned `meet.google.com/<conferenceId>` link in the
///      browser / Google Meet app (`LaunchMode.externalApplication`).
///
/// The SDK provides no in-app meeting view, so joining always leaves the
/// app — same as the confirmed flow.
Future<MeetJoinResult> joinConsultation(
  BuildContext context,
  AppointmentModel appointment,
) {
  // A stored link means the meeting already exists — JOIN the same room
  // (no new event) so both the patient and the clinic end up together.
  final stored = appointment.meetLink;
  if (stored != null && stored.isNotEmpty) {
    return _openStoredLink(stored);
  }
  return _runFlow(
    context,
    title: '${appointment.consultationTypeLabel ?? 'Consultation'}'
        '${appointment.doctorName != null && appointment.doctorName!.isNotEmpty ? ' — ${appointment.doctorName}' : ''}',
    description: appointment.symptoms ?? '',
    window: _consultationWindow(appointment),
  );
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

Future<MeetJoinResult> startConsultation(
  BuildContext context, {
  required String title,
}) {
  final now = DateTime.now();
  return _runFlow(
    context,
    title: title,
    description: '',
    window: (now, now.add(const Duration(minutes: 30))),
  );
}

/// Shared Google Sign-In → calendar event → open link flow used by both
/// entry points ([joinConsultation] with an appointment, [startConsultation]
/// without one). All Google API calls go through [meetFlowGateway] so tests
/// can substitute a fake.
Future<MeetJoinResult> _runFlow(
  BuildContext context, {
  required String title,
  required String description,
  required (DateTime, DateTime) window,
}) async {
  try {
    final signedIn = await meetFlowGateway.signIn(context);
    if (!signedIn) {
      // Canceled or failed — the SDK shows its own snackbar.
      return const MeetJoinResult.failure('Google Sign-In was cancelled.');
    }

    final (start, end) = window;
    final Map<String, String>? result;
    try {
      result = await meetFlowGateway.createEvent(
        title: title,
        description: description,
        startTime: start,
        endTime: end,
      );
    } catch (e) {
      // The SDK rethrows creation failures (patched — upstream swallowed
      // them), so the REAL cause surfaces here instead of a generic
      // "could not create" message.
      final message = _createEventErrorMessage(e);
      showErrorSnackbar(message);
      return MeetJoinResult.failure(message);
    }

    final link = result?['link'];
    if (link == null || link.isEmpty || link == 'null') {
      showErrorSnackbar('Could not create the meeting. Try again.');
      return const MeetJoinResult.failure('Meeting creation failed.');
    }
    await LaunchService.url(link);
    return MeetJoinResult.success(link);
  } catch (e) {
    debugPrint('Meet consultation error: $e');
    showErrorSnackbar('Could not start the video consultation.');
    return const MeetJoinResult.failure('Unexpected error.');
  }
}

/// One-click fix URL for the most common creation failure: the Google
/// Calendar API is not enabled on the GCP project (HTTP 403, message
/// "Google Calendar API has not been used in project … before or it is
/// disabled"). Surfaced verbatim in the error snackbar so the user can
/// enable it in one tap.
const String kCalendarApiEnableUrl =
    'https://console.developers.google.com/apis/api/calendar-json.googleapis.com/overview?project=450216527653';

/// Maps a calendar-event-creation exception to a user-facing message.
/// The Calendar-API-disabled 403 gets its own actionable hint (with the
/// exact enable link); everything else falls back to the generic retry
/// message.
String _createEventErrorMessage(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('has not been used') ||
      text.contains('is disabled') ||
      text.contains('403')) {
    return 'Google Calendar API is disabled in your Google Cloud project. '
        'Enable it to create meetings, then try again:\n'
        '$kCalendarApiEnableUrl';
  }
  debugPrint('Meet event-creation error: $error');
  return 'Could not create the meeting. Try again.';
}

/// The appointment's booked window (start → end), or a sane default (now
/// → +30 min) when the stored date/time can't be parsed.
(DateTime, DateTime) _consultationWindow(AppointmentModel appointment) {
  final date = appointment.appointmentDate; // yyyy-MM-dd
  final time = appointment.appointmentTime; // e.g. "10:00 AM"
  if (date != null && time != null) {
    for (final format in ['yyyy-MM-dd h:mm a', 'yyyy-MM-dd hh:mm a']) {
      try {
        final start = DateFormat(format).parse('$date $time');
        return (start, start.add(const Duration(minutes: 30)));
      } catch (_) {}
    }
  }
  final now = DateTime.now();
  return (now, now.add(const Duration(minutes: 30)));
}
