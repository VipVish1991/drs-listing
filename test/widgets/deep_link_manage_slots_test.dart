import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/controllers/doctor_controller.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/services/deep_link_service.dart';

import '../helpers/test_data.dart';

/// Test double that mocks [DoctorController.loadDoctorFromDb] — records the
/// placeId it was asked to load and sets [currentDoctor] to a canned value,
/// so no Supabase/Places network work happens during the test.
class _TestDoctorController extends DoctorController {
  @override
  // ignore: must_call_super
  void onInit() {}

  /// The placeId passed to [loadDoctorFromDb] (null if never called).
  String? loadedPlaceId;

  /// What [loadDoctorFromDb] should set as the current doctor.
  DoctorModel? doctorToLoad;

  @override
  Future<void> loadDoctorFromDb(String placeId) async {
    loadedPlaceId = placeId;
    currentDoctor.value = doctorToLoad;
  }
}

/// Registers the mock controller and pumps a [GetMaterialApp] whose routes
/// include the doctor dashboard, so navigation from the deep link can be
/// observed. Returns the mock controller for assertions.
Future<_TestDoctorController> _pumpApp(
  WidgetTester tester, {
  required DoctorModel? doctorToLoad,
}) async {
  Get.reset();
  final controller = _TestDoctorController()..doctorToLoad = doctorToLoad;
  Get.put<DoctorController>(controller, permanent: true);

  await tester.pumpWidget(
    GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(
          name: '/',
          page: () =>
              const Scaffold(body: Center(child: Text('Landing page'))),
        ),
        GetPage(
          name: AppRoutes.doctorDashboard,
          page: () =>
              const Scaffold(body: Center(child: Text('DASHBOARD'))),
        ),
      ],
    ),
  );
  await tester.pump();
  return controller;
}

/// Lets the route transition and any snackbar animations run to completion
/// (Get.toNamed pushes a Material page transition; Get.snackbar runs an
/// entrance animation). Without this, the test ends with active tickers or
/// the old route still in the tree.
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
    'manage-slots deep link loads the doctor and opens the dashboard',
    (tester) async {
      final doctor = doctorBasic(placeId: 'manage_test', name: 'Dr. Manage');
      final controller = await _pumpApp(tester, doctorToLoad: doctor);

      // Drive routing directly (no app_links plugin in widget tests).
      await DeepLinkService.instance.handleUri(
        Uri.parse('drslisting://manage-slots/${doctor.placeId}'),
      );
      await tester.pump();
      await _settleAnimations(tester);

      // The doctor was loaded via the mocked lookup.
      expect(controller.loadedPlaceId, doctor.placeId);

      // Navigation reached the doctor dashboard route.
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.text('Landing page'), findsNothing);
    },
  );

  testWidgets(
    'https manage-slots universal link also loads the doctor and navigates',
    (tester) async {
      final doctor = doctorBasic(placeId: 'https_test', name: 'Dr. Https');
      final controller = await _pumpApp(tester, doctorToLoad: doctor);

      await DeepLinkService.instance.handleUri(
        Uri.parse('https://drslisting.ai/manage-slots/${doctor.placeId}'),
      );
      await tester.pump();
      await _settleAnimations(tester);

      expect(controller.loadedPlaceId, doctor.placeId);
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.text('Landing page'), findsNothing);
    },
  );

  testWidgets(
    'manage-slots deep link shows an error and stays put when doctor not found',
    (tester) async {
      // loadDoctorFromDb resolves to null → not found.
      final controller = await _pumpApp(tester, doctorToLoad: null);

      await DeepLinkService.instance.handleUri(
        Uri.parse('drslisting://manage-slots/unknown_place'),
      );
      await tester.pump();
      await _settleAnimations(tester);

      // The lookup was attempted with the placeId from the link.
      expect(controller.loadedPlaceId, 'unknown_place');

      // No navigation happened...
      expect(find.text('DASHBOARD'), findsNothing);
      expect(find.text('Landing page'), findsOneWidget);

      // ...and an error snackbar explains why.
      expect(find.text('Doctor not found for this link'), findsOneWidget);

      // Dismiss the snackbar so its auto-hide timer doesn't leak.
      Get.closeCurrentSnackbar();
      await tester.pump(const Duration(milliseconds: 500));
      await _settleAnimations(tester);
    },
  );
}
