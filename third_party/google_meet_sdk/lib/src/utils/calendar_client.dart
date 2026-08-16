import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart';

/// Wrapper around the Google Calendar API used to create the
/// Meet-backed consultation event. A successful [insert] returns
/// `{'id': <eventId>, 'link': 'https://meet.google.com/<conferenceId>'}`.
class CalendarClient {
  static CalendarApi? calendar;

  /// Creates a calendar event, optionally with a Google Meet conference.
  /// Returns `{'id': ..., 'link': ...}` when the event lands as
  /// `confirmed`, null otherwise.
  Future<Map<String, String>?> insert({
    required String title,
    required String description,
    required String location,
    required List<String> attendeeEmailList,
    required bool shouldNotifyAttendees,
    required bool hasConferenceSupport,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    Map<String, String>? eventData;
    final List<EventAttendee> attendeeList = [];
    const String calendarId = 'primary';
    final Event event = Event();
    for (final element in attendeeEmailList) {
      final EventAttendee eventAttendee = EventAttendee();
      eventAttendee.email = element;
      attendeeList.add(eventAttendee);
    }
    event.summary = title;
    event.description = description;
    event.attendees = attendeeList;
    event.location = location;
    if (hasConferenceSupport) {
      final ConferenceData conferenceData = ConferenceData();
      final CreateConferenceRequest conferenceRequest =
          CreateConferenceRequest();
      conferenceRequest.requestId =
          '${startTime.millisecondsSinceEpoch}-${endTime.millisecondsSinceEpoch}';
      conferenceData.createRequest = conferenceRequest;
      event.conferenceData = conferenceData;
    }
    final EventDateTime start = EventDateTime();
    start.dateTime = startTime;
    start.timeZone = 'GMT+05:30';
    event.start = start;
    final EventDateTime end = EventDateTime();
    end.timeZone = 'GMT+05:30';
    end.dateTime = endTime;
    event.end = end;
    try {
      await calendar?.events
          .insert(
            event,
            calendarId,
            conferenceDataVersion: hasConferenceSupport ? 1 : 0,
            sendUpdates: shouldNotifyAttendees ? 'all' : 'none',
          )
          .then((value) {
        debugPrint('Event Status: ${value.status}');
        debugPrint('conferenceId: ${value.conferenceData?.conferenceId}');
        if (value.status == 'confirmed') {
          String? joiningLink;
          String? eventId;
          eventId = value.id;
          if (hasConferenceSupport) {
            joiningLink =
                'https://meet.google.com/${value.conferenceData?.conferenceId}';
          }
          eventData = {'id': eventId ?? '', 'link': '$joiningLink'};
          debugPrint('Event added to Google Calendar $joiningLink');
        } else {
          debugPrint('Unable to add event to Google Calendar');
        }
      });
    } catch (e) {
      debugPrint('Error creating event $e');
      // PATCHED vs upstream: upstream swallowed the error and returned
      // null, so callers could never tell WHY creation failed (e.g. the
      // Calendar API being disabled in the GCP project returns a 403 with
      // a message that was only ever debug-printed). Rethrow so the host
      // app can surface the real cause to the user.
      rethrow;
    }
    return eventData;
  }

  /// Modifies an existing event (used to update the Meet link / times).
  Future<Map<String, String>?> modify({
    required String id,
    required String title,
    required String description,
    required String location,
    required List<String> attendeeEmailList,
    required bool shouldNotifyAttendees,
    required bool hasConferenceSupport,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    Map<String, String>? eventData;
    const String calendarId = 'primary';
    final Event event = Event();
    final List<EventAttendee> attendeeList = [];
    for (final element in attendeeEmailList) {
      final EventAttendee eventAttendee = EventAttendee();
      eventAttendee.email = element;
      attendeeList.add(eventAttendee);
    }
    event.summary = title;
    event.description = description;
    event.attendees = attendeeList;
    event.location = location;
    final EventDateTime start = EventDateTime();
    start.dateTime = startTime;
    start.timeZone = 'GMT+05:30';
    event.start = start;
    final EventDateTime end = EventDateTime();
    end.timeZone = 'GMT+05:30';
    end.dateTime = endTime;
    event.end = end;
    try {
      await calendar?.events
          .patch(
            event,
            calendarId,
            id,
            conferenceDataVersion: hasConferenceSupport ? 1 : 0,
            sendUpdates: shouldNotifyAttendees ? 'all' : 'none',
          )
          .then((value) {
        debugPrint('Event Status: ${value.status}');
        if (value.status == 'confirmed') {
          String? joiningLink;
          final String eventId;
          eventId = value.id ?? '';
          if (hasConferenceSupport) {
            joiningLink =
                'https://meet.google.com/${value.conferenceData?.conferenceId}';
          }
          eventData = {'id': eventId, 'link': '$joiningLink'};
          debugPrint('Event added to Google Calendar $joiningLink');
        } else {
          debugPrint('Unable to update event in google calendar');
        }
      });
    } catch (e) {
      debugPrint('Error updating event $e');
    }
    return eventData;
  }

  /// Deletes an event from the user's calendar.
  Future<void> delete(String eventId, bool shouldNotify) async {
    const String calendarId = 'primary';
    try {
      await calendar?.events
          .delete(calendarId, eventId, sendUpdates: shouldNotify ? 'all' : 'none')
          .then((value) {
        debugPrint('Event deleted from Google Calendar');
      });
    } catch (e) {
      debugPrint('Error deleting event: $e');
    }
  }
}
