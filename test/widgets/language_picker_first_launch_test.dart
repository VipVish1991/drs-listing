import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/profile_controller.dart';
import 'package:DrsListing/controllers/voice_controller.dart';
import 'package:DrsListing/screens/profile/profile_screen.dart';
import 'package:DrsListing/services/local_storage_service.dart';

/// Test doubles that skip network/speech work. Unlike the main profile test,
/// the ProfileController here runs its REAL onInit (storage read) so the
/// first-launch language state is loaded exactly like in the app.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestVoiceController extends VoiceController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestProfileController extends ProfileController {
  // Keep the real onInit (loads language from storage) but skip the
  // network-heavy saved-doctors merge, which would hang the test.
  @override
  Future<void> loadSavedDoctors() async {}
}

/// Pumps a [ProfileScreen] inside a GetMaterialApp so the language picker's
/// Get.bottomSheet works, with the real language-preference read path.
Future<void> _pumpProfile(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(
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

  group('first launch (no stored language preference)', () {
    testWidgets('Hindi chip shows its friendly name, not a bare code', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await LocalStorageService().init();

      await _pumpProfile(tester);

      // The Language Settings chip must render the friendly name of the
      // resolved default locale ('हिन्दी') — the app defaults to Hindi
      // until the patient picks another language.
      expect(find.text('हिन्दी'), findsOneWidget);
      expect(find.text('EN'), findsNothing);
      expect(find.text('EN-IN'), findsNothing);
      expect(find.text('HI-IN'), findsNothing);

      await _settleAnimations(tester);
    });

    testWidgets('Hindi is the selected (highlighted) language in the picker', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await LocalStorageService().init();

      await _pumpProfile(tester);

      // Open the language settings bottom sheet.
      await tester.tap(find.text('Language Settings'));
      await tester.pumpAndSettle();

      // The picker highlights exactly the resolved default ('hi-IN') and no
      // other option — the radio button renders checked for it. The options
      // are located by their stable ValueKey because the profile chip now
      // also shows the selected language name (Hindi on first launch).
      expect(find.text('Preferred Language'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('lang_option_hi-IN')),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      for (final lang in AppConstants.supportedLanguages) {
        if (lang['code'] == 'hi-IN') continue;
        expect(
          find.descendant(
            of: find.byKey(ValueKey('lang_option_${lang['code']}')),
            matching: find.byIcon(Icons.radio_button_checked),
          ),
          findsNothing,
          reason: '${lang['name']} must not be selected on first launch',
        );
      }

      await _settleAnimations(tester);
    });
  });

  group('switching languages', () {
    testWidgets('re-selecting English updates the stored + highlighted state', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await LocalStorageService().init();

      await _pumpProfile(tester);

      // First switch to Hindi. The options are found by their stable
      // ValueKey — the profile chip's trailing text can duplicate a
      // language name (the chip shows the currently selected one).
      await tester.tap(find.text('Language Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lang_option_hi-IN')));
      await tester.pumpAndSettle();

      final profile = Get.find<ProfileController>();
      expect(profile.selectedLanguage.value, 'hi-IN');

      // Then back to English — the sheet closes on selection, so reopen it
      // to verify the picker now highlights English.
      await tester.tap(find.text('Language Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lang_option_en-IN')));
      await tester.pumpAndSettle();

      expect(profile.selectedLanguage.value, 'en-IN');

      await tester.tap(find.text('Language Settings'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('lang_option_en-IN')),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );

      await _settleAnimations(tester);
    });
  });
}
