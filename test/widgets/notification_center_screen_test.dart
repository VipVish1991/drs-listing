import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/notification_center_controller.dart';
import 'package:DrsListing/models/notification_item.dart';
import 'package:DrsListing/screens/profile/notification_center_screen.dart';
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
    auth.currentUser.value = userPatient(id: 'user_1', mobile: '9876543210');
  });

  tearDown(() {
    Get.reset();
  });

  NotificationItem makeItem(String id, {bool read = false}) => NotificationItem(
        id: id,
        type: read ? 'appointment_booked' : 'appointment_status_changed',
        title: read ? 'New Appointment Request' : 'Appointment Confirmed',
        // Bodies use the app-wide dd-MM-yyyy display format (the Edge
        // Function formats them server-side); data payload stays ISO.
        body: read
            ? 'Rahul booked for 10-08-2026 at 10:00 AM.'
            : 'Dr. Test confirmed your appointment on 10-08-2026 at 10:00 AM.',
        data: const {
          'appointment_id': 'APT999',
          'doctor_place_id': 'place-1',
          'doctor_name': 'Dr. Test Clinic',
          'patient_name': 'Rahul Sharma',
          'appointment_date': '2026-08-10',
          'appointment_time': '10:00 AM',
        },
        read: read,
        createdAt: DateTime(2026, 8, 6, 10),
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    NotificationCenterController? controller,
  }) async {
    if (controller != null) {
      Get.put(controller, permanent: true);
    }
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        getPages: [
          GetPage(name: '/appointment-history', page: () => const Scaffold()),
          GetPage(name: '/doctor-dashboard', page: () => const Scaffold()),
        ],
        home: const NotificationCenterScreen(),
      ),
    );
    // Let the async refresh() settle (Supabase unavailable → non-fatal) and
    // the fadeIn animations finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('shows an empty state when there are no notifications',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('shows a loading spinner while the list loads', (tester) async {
    // No logged-in user → refresh() early-returns without resetting
    // isLoading, so the spinner stays up for the whole test.
    Get.find<AuthController>().currentUser.value = null;
    final controller = NotificationCenterController();
    controller.isLoading.value = true;
    await pumpScreen(tester, controller: controller);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders notification rows with unread styling', (tester) async {
    final controller = NotificationCenterController();
    controller.items.value = [makeItem('n1'), makeItem('n2', read: true)];
    await pumpScreen(tester, controller: controller);

    expect(find.text('New Appointment Request'), findsOneWidget);
    expect(find.text('Appointment Confirmed'), findsOneWidget);
    // One unread → badge chip in the header shows "Mark all read".
    expect(find.text('Mark all read'), findsOneWidget);
  });

  testWidgets('shows the doctor name and destination hint on each card',
      (tester) async {
    final controller = NotificationCenterController();
    // n1 = unread → status_changed (patient alert → appointment history);
    // n2 = read → appointment_booked (doctor alert → doctor dashboard).
    controller.items.value = [makeItem('n1'), makeItem('n2', read: true)];
    await pumpScreen(tester, controller: controller);

    // Doctor name chip on both cards.
    expect(find.text('Dr. Test Clinic'), findsNWidgets(2));

    // Destination hints reflect each event's target screen.
    expect(find.text('Opens Appointment History'), findsOneWidget);
    expect(find.text('Opens Doctor Dashboard'), findsOneWidget);
  });

  testWidgets('doctor events hint at the doctor dashboard, status at history',
      (tester) async {
    final controller = NotificationCenterController();
    controller.items.value = [makeItem('n1', read: true)]; // booked → dashboard
    await pumpScreen(tester, controller: controller);

    expect(find.text('Opens Doctor Dashboard'), findsOneWidget);
    expect(find.text('Dr. Test Clinic'), findsOneWidget);
  });

  testWidgets('tapping a row marks it read and navigates', (tester) async {
    final controller = NotificationCenterController();
    controller.items.value = [makeItem('n1')];
    await pumpScreen(tester, controller: controller);

    expect(controller.unreadCount.value, 1);

    // n1 is unread → type status_changed → appointment history route.
    await tester.tap(find.text('Appointment Confirmed'));
    await tester.pumpAndSettle();

    expect(controller.items.first.read, isTrue);
    expect(controller.unreadCount.value, 0);
  });

  testWidgets('mark all read clears every unread badge', (tester) async {
    final controller = NotificationCenterController();
    controller.items.value = [makeItem('n1'), makeItem('n2')];
    await pumpScreen(tester, controller: controller);

    expect(controller.unreadCount.value, 2);
    await tester.tap(find.text('Mark all read'));
    await tester.pump();

    expect(controller.unreadCount.value, 0);
    expect(controller.items.every((n) => n.read), isTrue);
  });

  testWidgets('hides the mark-all-read action when nothing is unread',
      (tester) async {
    final controller = NotificationCenterController();
    controller.items.value = [makeItem('n1', read: true)];
    await pumpScreen(tester, controller: controller);

    expect(find.text('Mark all read'), findsNothing);
  });
}
