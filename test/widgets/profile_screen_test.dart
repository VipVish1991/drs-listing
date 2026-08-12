import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/profile_controller.dart';
import 'package:DrsListing/controllers/voice_controller.dart';
import 'package:DrsListing/models/user_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/profile/profile_screen.dart';
import 'package:DrsListing/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test doubles that skip the network/speech work their real counterparts
/// start in onInit (mirrors the pattern in doctor_detail_screen_test.dart and
/// about_screen_test.dart).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}

  /// Skip the Supabase round-trip in tests — just update the in-memory user
  /// the same way the real controller does after a successful save.
  @override
  Future<void> updateUserName(String name) async {
    final u = currentUser.value;
    if (u == null) return;
    currentUser.value = u.copyWith(name: name);
  }
}

class _TestVoiceController extends VoiceController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestProfileController extends ProfileController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Pumps a [ProfileScreen] with test controllers registered.
Future<void> _pumpProfile(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: const ProfileScreen(),
    ),
  );
  await tester.pump();
}

/// Lets every flutter_animate effect on the Profile screen run to completion.
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<VoiceController>(_TestVoiceController(), permanent: true);
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<ProfileController>(_TestProfileController(), permanent: true);
  });

  testWidgets('Profile screen renders its menu items', (tester) async {
    await _pumpProfile(tester);

    expect(find.text('Saved Doctors'), findsOneWidget);
    expect(find.text('Appointment History'), findsOneWidget);
    expect(find.text('Payment History'), findsOneWidget);
    expect(find.text('Language Settings'), findsOneWidget);
    expect(find.text('Search Radius'), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets('Payment History row navigates to the payment history screen', (
    tester,
  ) async {
    // GetMaterialApp + a stubbed payment-history route so Get.toNamed works.
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        getPages: [
          GetPage(
            name: AppRoutes.paymentHistory,
            page: () => const Scaffold(
              body: Center(child: Text('PAYMENTS_STUB')),
            ),
          ),
        ],
        home: const ProfileScreen(),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);

    await tester.ensureVisible(find.text('Payment History'));
    await tester.pump();
    await tester.tap(find.text('Payment History'));
    await tester.pumpAndSettle();

    expect(find.text('PAYMENTS_STUB'), findsOneWidget);
  });

  testWidgets('Auto-Play Welcome row opens the toggle sheet and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService().init();

    // GetMaterialApp so Get.bottomSheet can show.
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const ProfileScreen(),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);

    // The settings row shows the current (default On) state.
    expect(find.text('Auto-Play Welcome'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('welcome_auto_play_chip')),
          )
          .data,
      'On',
    );

    // Opening the row shows the toggle sheet. (The row sits below the
    // fold on the default test surface, so scroll it into view first.)
    await tester.ensureVisible(find.text('Auto-Play Welcome'));
    await tester.pump();
    await tester.tap(find.text('Auto-Play Welcome'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // sheet slides in
    expect(find.byType(SwitchListTile), findsOneWidget);

    // Flipping the switch persists the choice immediately.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(LocalStorageService().isWelcomeAutoPlayEnabled(), isFalse);

    // Dismiss the sheet (tap the barrier) — the row chip now reads Off.
    await tester.tapAt(const Offset(400, 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // sheet slides out
    expect(find.byType(SwitchListTile), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('welcome_auto_play_chip')),
          )
          .data,
      'Off',
    );

    await _settleAnimations(tester);
  });

  testWidgets('welcome sheet is fixed to "With the video" — no timing '
      'presets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService().init();

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const ProfileScreen(),
      ),
    );
    await _settleAnimations(tester);

    // Default greeting timing is "With the video" (0 ms) — the only preset.
    expect(LocalStorageService().getWelcomeGreetingDelayMs(), 0);

    await tester.ensureVisible(find.text('Auto-Play Welcome'));
    await tester.pump();
    await tester.tap(find.text('Auto-Play Welcome'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // sheet slides in

    // The sheet still offers the auto-play toggle…
    expect(find.byType(SwitchListTile), findsOneWidget);
    // …but the "Greeting timing" chooser and its stagger presets are
    // gone — the greeting always starts together with the video.
    expect(find.text('Greeting timing'), findsNothing);
    expect(find.text('With the video'), findsNothing);
    expect(find.text('After 1 second'), findsNothing);
    expect(find.text('After 2 seconds'), findsNothing);
    expect(find.text('After 3 seconds'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('the removed API Calls Today row no longer renders', (
    tester,
  ) async {
    await _pumpProfile(tester);

    // Regression guard: the Google Places usage counter was removed from the
    // app, so neither the label nor its count chip may appear on the profile.
    expect(find.text('API Calls Today'), findsNothing);
    expect(find.text('—'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('edit icon opens a dialog that saves the updated name', (
    tester,
  ) async {
    Get.find<AuthController>().currentUser.value = UserModel(
      id: 'u1',
      name: 'Rahul',
      mobile: '9999999999',
    );

    // GetMaterialApp so Get.dialog (used by the edit popup) can show.
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const ProfileScreen(),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);

    // Header renders the current name.
    expect(find.text('Rahul'), findsOneWidget);

    // Tap the edit icon in the header → the edit popup appears.
    // (Fixed-duration pumps: the autofocused TextField's blinking cursor
    // never lets pumpAndSettle settle.)
    await tester.tap(
      find.byKey(const ValueKey('profile_edit_name_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Edit Name'), findsOneWidget);

    // Type a new name and save.
    await tester.enterText(find.byType(TextFormField), 'Rahul Sharma');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // dialog close
    await tester.pump(const Duration(milliseconds: 300)); // snackbar in

    // Popup closed and the header reflects the new name in-place.
    expect(find.text('Edit Name'), findsNothing);
    expect(find.text('Rahul Sharma'), findsOneWidget);
    expect(
      Get.find<AuthController>().currentUser.value?.name,
      'Rahul Sharma',
    );

    // Let the success snackbar's auto-dismiss timer fire (2s) and its
    // exit animation run to completion so no timers/tickers are left
    // pending when the test ends.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
