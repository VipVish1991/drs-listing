import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/screens/profile/notification_settings_screen.dart';
import 'package:DrsListing/controllers/notification_settings_controller.dart';
import '../helpers/test_data.dart';

/// Test-only AuthController that skips the secure-storage platform channel.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  setUp(() {
    Get.reset();
    final auth = Get.put<AuthController>(_TestAuthController(), permanent: true);
    // A logged-in user is required for a toggle's save to be attempted (and
    // then fail against unavailable Supabase → revert).
    auth.currentUser.value = userPatient(id: 'user_1', mobile: '9876543210');
  });

  tearDown(() {
    Get.reset();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const NotificationSettingsScreen(),
      ),
    );
    // Let the async loadPrefs settle (Supabase unavailable → defaults stay).
    await tester.pumpAndSettle();
  }

  testWidgets('renders the header, master switch and all six alert toggles',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Push Alerts'), findsOneWidget);
    expect(find.text('All Notifications'), findsOneWidget);
    expect(find.text('New Bookings'), findsOneWidget);
    expect(find.text('Cancellations'), findsOneWidget);
    expect(find.text('Reschedules'), findsOneWidget);
    expect(find.text('Clinic Reschedules'), findsOneWidget);
    expect(find.text('Status Updates'), findsOneWidget);
    expect(find.text('Payment Updates'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(7));
  });

  testWidgets('all toggles start ON by default', (tester) async {
    await pumpScreen(tester);

    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches, hasLength(7));
    expect(switches.every((s) => s.value), isTrue);
  });

  testWidgets('turning the master switch off disables and dims the event toggles',
      (tester) async {
    // Pre-seed a controller with the master OFF (individual keys preserved).
    final controller = Get.put<NotificationSettingsController>(
      NotificationSettingsController(),
      permanent: true,
    );
    controller.prefs.assignAll({
      NotificationSettingsController.eventAll: false,
      NotificationSettingsController.eventBooked: true,
      NotificationSettingsController.eventCancelled: true,
      NotificationSettingsController.eventRescheduled: true,
      NotificationSettingsController.eventStatusChanged: true,
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const NotificationSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Master switch is off; the six event switches are disabled (null
    // onChanged) and visually off even though their saved values are true.
    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches, hasLength(7));
    expect(switches[0].value, isFalse); // All Notifications (master)
    expect(switches[0].onChanged, isNotNull); // master itself stays tappable
    expect(switches[1].value, isFalse); // New Bookings — shown off
    expect(switches[1].onChanged, isNull); // …and disabled
    expect(switches[2].value, isFalse); // Cancellations
    expect(switches[2].onChanged, isNull);
    expect(switches[3].value, isFalse); // Reschedules
    expect(switches[3].onChanged, isNull);
    expect(switches[4].value, isFalse); // Clinic Reschedules
    expect(switches[4].onChanged, isNull);
    expect(switches[5].value, isFalse); // Status Updates
    expect(switches[5].onChanged, isNull);
    expect(switches[6].value, isFalse); // Payment Updates
    expect(switches[6].onChanged, isNull);

    // The granular choices are preserved underneath.
    expect(
      controller.prefs[NotificationSettingsController.eventBooked],
      isTrue,
    );
  });

  testWidgets('turning the master back on restores the enabled toggles',
      (tester) async {
    final controller = Get.put<NotificationSettingsController>(
      NotificationSettingsController(),
      permanent: true,
    );
    controller.prefs.assignAll({
      NotificationSettingsController.eventAll: true,
      NotificationSettingsController.eventBooked: false,
      NotificationSettingsController.eventCancelled: true,
      NotificationSettingsController.eventRescheduled: true,
      NotificationSettingsController.eventStatusChanged: true,
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const NotificationSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches[0].value, isTrue); // master ON
    expect(switches[1].value, isFalse); // Bookings — restored off
    expect(switches[1].onChanged, isNotNull); // …and enabled again
    expect(switches[2].value, isTrue);
    expect(switches[3].value, isTrue); // Reschedules
    expect(switches[4].value, isTrue); // Clinic Reschedules
    expect(switches[5].value, isTrue); // Status Updates
  });

  testWidgets('tapping a toggle reverts when the server save fails',
      (tester) async {
    await pumpScreen(tester);

    // Supabase is unavailable in tests → setPref's save throws → the switch
    // flips optimistically, then reverts so the UI stays truthful.
    await tester.tap(find.text('Cancellations'));
    await tester.pumpAndSettle();

    final controller = Get.find<NotificationSettingsController>();
    expect(
      controller.prefs[NotificationSettingsController.eventCancelled],
      isTrue,
    );

    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches.every((s) => s.value), isTrue);
  });

  testWidgets('shows a loading spinner while preferences are loading',
      (tester) async {
    // Pre-register a controller stuck in the loading state. No logged-in
    // user → loadPrefs early-returns without resetting isLoading, so the
    // spinner stays up for the whole test.
    final auth = Get.find<AuthController>();
    auth.currentUser.value = null;
    final controller = Get.put<NotificationSettingsController>(
      NotificationSettingsController(),
      permanent: true,
    );
    controller.isLoading.value = true;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const NotificationSettingsScreen(),
      ),
    );
    // Pump past the fadeIn delay (100ms) + duration (400ms) so its one-shot
    // timer is flushed (pumpAndSettle can't be used — the spinner animates
    // forever). The spinner's own ticker is harmless at teardown.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('a user who disabled an alert renders that toggle off',
      (tester) async {
    // Pre-seed a controller with an already-saved preference: bookings off.
    final controller = Get.put<NotificationSettingsController>(
      NotificationSettingsController(),
      permanent: true,
    );
    controller.prefs.assignAll({
      NotificationSettingsController.eventAll: true,
      NotificationSettingsController.eventBooked: false,
      NotificationSettingsController.eventCancelled: true,
      NotificationSettingsController.eventRescheduled: true,
      NotificationSettingsController.eventStatusChanged: true,
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const NotificationSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches, hasLength(7));
    expect(switches[0].value, isTrue); // Master — on
    expect(switches[1].value, isFalse); // New Bookings — off
    expect(switches[2].value, isTrue); // Cancellations — on
    expect(switches[3].value, isTrue); // Reschedules — on
    expect(switches[4].value, isTrue); // Clinic Reschedules — on
    expect(switches[5].value, isTrue); // Status Updates — on
    expect(switches[6].value, isTrue); // Payment Updates — on
  });
}
