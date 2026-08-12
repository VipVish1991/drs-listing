import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/doctor_search_controller.dart';
import 'package:DrsListing/controllers/profile_controller.dart';
import 'package:DrsListing/controllers/voice_controller.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/auth/login_screen.dart';
import 'package:DrsListing/screens/auth/register_screen.dart';
import 'package:DrsListing/screens/doctor/doctor_register_screen.dart';
import 'package:DrsListing/screens/doctor_search/doctor_search_screen.dart';

/// Test doubles that skip the network/storage work their real counterparts
/// start in onInit (mirrors the pattern in pending_doctor_flow_test.dart and
/// profile_screen_test.dart).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}

  /// No-op login: these tests only assert keyboard dismissal, so the real
  /// AuthService (network/platform) must never be touched.
  @override
  Future<bool> login(
    String mobile, {
    DoctorModel? pendingDoctor,
    bool redirect = true,
  }) async {
    errorMessage.value = 'Test login (not attempted)';
    return false;
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

/// Skips the Places API call so submitting the search field doesn't hit the
/// network in tests.
class _TestDoctorSearchController extends DoctorSearchController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> searchDoctors({String? specialization, String? query}) async {
    searchQuery.value = query ?? searchQuery.value;
    isLoading.value = false;
  }
}

/// Pumps [DoctorSearchScreen] with its controllers registered.
Future<void> _pumpSearchScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.lightTheme, home: const DoctorSearchScreen()),
  );
  await tester.pump();
}

/// Pumps [RegisterScreen] with the auth controller registered.
Future<void> _pumpRegisterScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(theme: AppTheme.lightTheme, home: const RegisterScreen()),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

/// Pumps [DoctorRegisterScreen] with the auth controller registered.
Future<void> _pumpDoctorRegisterScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: const DoctorRegisterScreen(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

/// The name field is the first TextField on both register screens; the
/// mobile field is the second (and last). Each TextField contains exactly
/// one EditableText, so targeting EditableText avoids the wrapper cast.
Finder _nameField() => find.byType(EditableText).first;
Finder _mobileField() => find.byType(EditableText).last;

void main() {
  setUp(() {
    Get.reset();
    Get.put<VoiceController>(_TestVoiceController(), permanent: true);
    Get.put<AuthController>(_TestAuthController(), permanent: true);
    Get.put<ProfileController>(_TestProfileController(), permanent: true);
    Get.put<DoctorSearchController>(
      _TestDoctorSearchController(),
      permanent: true,
    );
  });

  tearDown(() {
    Get.reset();
  });

  group('LoginScreen dismisses the keyboard on submit', () {
    testWidgets("pressing 'Continue' hides the keyboard", (tester) async {
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          getPages: [
            GetPage(name: AppRoutes.login, page: () => const LoginScreen()),
          ],
          home: const LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final mobileField = find.widgetWithText(TextField, 'Mobile Number');
      expect(mobileField, findsOneWidget);

      // Focus the field → the test keyboard connects.
      await tester.enterText(mobileField, '9876543210');
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // The Continue button sits below the fold of the test viewport.
      final continueButton = find.widgetWithText(ElevatedButton, 'Continue');
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // _handleLogin unfocuses first → keyboard dismissed.
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('pressing the keyboard Done action hides the keyboard', (
      tester,
    ) async {
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          getPages: [
            GetPage(name: AppRoutes.login, page: () => const LoginScreen()),
          ],
          home: const LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final mobileField = find.widgetWithText(TextField, 'Mobile Number');
      await tester.enterText(mobileField, '9876543210');
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // Simulate tapping the keyboard's action button (Done).
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    });
  });

  group('Register screens: name \'next\' key moves focus to mobile', () {
    testWidgets('patient register: next key focuses the mobile field', (
      tester,
    ) async {
      await _pumpRegisterScreen(tester);

      // Exactly two fields: name first, mobile second.
      expect(find.byType(TextField), findsNWidgets(2));
      final nameField = _nameField();

      await tester.enterText(nameField, 'Jane Doe');
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // Press the keyboard's "next" action → focus moves to the mobile
      // field (previously a visual no-op).
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      final editable = tester.widget<EditableText>(_mobileField());
      expect(editable.focusNode.hasFocus, isTrue);
      // The keyboard stays up (focus simply advanced fields).
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('doctor register: next key focuses the mobile field', (
      tester,
    ) async {
      await _pumpDoctorRegisterScreen(tester);

      expect(find.byType(TextField), findsNWidgets(2));
      final nameField = _nameField();

      await tester.enterText(nameField, 'Dr. House');
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      final editable = tester.widget<EditableText>(_mobileField());
      expect(editable.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  });

  group('DoctorSearchScreen dismisses the keyboard on submit', () {
    testWidgets('pressing the keyboard search action hides the keyboard', (
      tester,
    ) async {
      await _pumpSearchScreen(tester);

      // Single TextField on the screen (hint: 'Search doctors, hospitals…').
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'Dr. Alice');
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // Simulate tapping the keyboard's search button → onSubmitted runs
      // the search and unfocuses.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('tapping the in-field search icon hides the keyboard', (
      tester,
    ) async {
      await _pumpSearchScreen(tester);

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Clinic');
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // The suffix search icon only renders once the controller holds a
      // non-empty query (the suffix watches searchQuery, not the field text).
      Get.find<DoctorSearchController>().searchQuery.value = 'Clinic';
      await tester.pumpAndSettle();

      // Both the prefix decoration icon and the suffix search button render
      // the same glyph — assert both are present, then tap the LAST one
      // (the suffix action button, which comes after the prefix icon).
      expect(find.byIcon(Icons.search_rounded), findsNWidgets(2));
      final searchIcon = find.byIcon(Icons.search_rounded).last;
      await tester.tap(searchIcon);
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isFalse);
    });
  });
}
