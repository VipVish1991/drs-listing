import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/doctor_controller.dart';
import 'package:DrsListing/controllers/profile_controller.dart';
import 'package:DrsListing/controllers/voice_controller.dart';
import 'package:DrsListing/screens/doctor_search/doctor_detail_screen.dart';
import 'package:DrsListing/routes/app_routes.dart';
import '../helpers/test_data.dart';

/// A mock [HttpOverrides] that makes every HTTP request fail immediately.
class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw Exception('HTTP blocked in test environment');
  }
}

void ensureTestSetup() {
  if (!dotenv.isInitialized) {
    dotenv.loadFromString(
      envString: '''
GOOGLE_MAPS_API_KEY=test_key
GROQ_API_KEY=test_groq_key
''',
    );
  }
  if (!Get.isRegistered<VoiceController>()) {
    Get.put<VoiceController>(_TestVoiceController(), permanent: true);
  }
  if (!Get.isRegistered<AuthController>()) {
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  }
  if (!Get.isRegistered<ProfileController>()) {
    Get.put<ProfileController>(_TestProfileController(), permanent: true);
  }
  if (!Get.isRegistered<DoctorController>()) {
    Get.put<DoctorController>(_TestDoctorController(), permanent: true);
  }
}

class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestProfileController extends ProfileController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestDoctorController extends DoctorController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestVoiceController extends VoiceController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  setUpAll(() {
    ensureTestSetup();
    HttpOverrides.global = _FakeHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  setUp(() {
    final auth = Get.find<AuthController>();
    auth.currentUser.value = userPatient();
    auth.isLoggedIn.value = false;
    auth.errorMessage.value = '';
    auth.isLoading.value = false;
  });

  testWidgets('DoctorDetailScreen renders without crash when navigated to',
      (tester) async {
    final doctor = doctorBasic(
      placeId: 'render_test',
      name: 'Render Test Doctor',
      latitude: null,
      longitude: null,
    );

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const SizedBox(),
        getPages: [
          GetPage(
            name: AppRoutes.doctorDetail,
            page: () => const DoctorDetailScreen(),
          ),
        ],
      ),
    );

    // Navigate
    await tester.runAsync(() async {
      Get.toNamed(AppRoutes.doctorDetail, arguments: {'doctor': doctor});
      await Future.delayed(const Duration(milliseconds: 50));
    });

    // Pump to build the screen
    await tester.pump();
    await tester.pump();

    // Verify the screen rendered (doctor name visible)
    expect(find.textContaining('Render Test'), findsAtLeastNWidgets(1));
  });

  testWidgets(
      'DoctorDetailScreen renders from minimal placeId+doctorName args '
      '(regression: Null DoctorModel cast crash from appointment history)',
      (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const SizedBox(),
        getPages: [
          GetPage(
            name: AppRoutes.doctorDetail,
            page: () => const DoctorDetailScreen(),
          ),
        ],
      ),
    );

    // Navigate with the appointment-history arg shape: no DoctorModel,
    // only placeId + doctorName. This used to crash with
    // "type 'Null' is not a subtype of type 'DoctorModel' in type cast".
    await tester.runAsync(() async {
      Get.toNamed(AppRoutes.doctorDetail, arguments: {
        'placeId': 'history_place_1',
        'doctorName': 'History Doctor',
      });
      await Future.delayed(const Duration(milliseconds: 50));
    });

    await tester.pump();
    await tester.pump();

    // No crash — the screen bootstraps from the minimal args and shows
    // the doctor name (it fetches full details by placeId on load).
    expect(find.textContaining('History Doctor'), findsAtLeastNWidgets(1));
  });

}

