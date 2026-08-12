import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/widgets/in_app_notification_banner.dart';

void main() {
  testWidgets('banner appears and only the card triggers the tap callback',
      (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(home: const Scaffold(body: Text('underlying'))),
    );
    // Let GetX set Get.overlayContext.
    await tester.pump();

    var tapped = false;
    InAppNotificationBanner.instance.show(
      title: 'New Appointment Request',
      body: 'A patient booked for 2099-01-01 at 10:00 AM.',
      type: 'appointment_booked',
      onTap: () => tapped = true,
    );
    await tester.pump(); // insert the overlay entry
    await tester.pump(const Duration(milliseconds: 350)); // slide-in finishes

    expect(find.text('New Appointment Request'), findsOneWidget);
    expect(find.text('A patient booked for 2099-01-01 at 10:00 AM.'),
        findsOneWidget);

    // A tap well outside the card must NOT trigger the callback.
    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(tapped, isFalse);

    // Tapping the banner itself triggers the callback.
    await tester.tap(find.text('New Appointment Request'));
    await tester.pump();
    expect(tapped, isTrue);

    // The banner was dismissed by the tap.
    expect(InAppNotificationBanner.instance.isShowing, isFalse);
  });

  testWidgets('banner auto-dismisses after 5 seconds', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(home: const Scaffold(body: Text('underlying'))),
    );
    await tester.pump();

    InAppNotificationBanner.instance.show(
      title: 'Appointment Confirmed',
      body: 'Your doctor confirmed the appointment.',
      type: 'appointment_status_changed',
      onTap: () {},
    );
    await tester.pump();

    expect(find.text('Appointment Confirmed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('Appointment Confirmed'), findsNothing);
    expect(InAppNotificationBanner.instance.isShowing, isFalse);
  });

  testWidgets('close button dismisses the banner immediately', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(home: const Scaffold(body: Text('underlying'))),
    );
    await tester.pump();

    InAppNotificationBanner.instance.show(
      title: 'Appointment Cancelled',
      body: 'The patient cancelled their booking.',
      type: 'appointment_cancelled',
      onTap: () {},
    );
    await tester.pump();
    // Let the slide-in animation finish so the card is on screen.
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(InAppNotificationBanner.instance.isShowing, isFalse);
    expect(find.text('Appointment Cancelled'), findsNothing);
  });
}
