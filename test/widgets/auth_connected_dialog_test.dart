import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';

import '../helpers/test_data.dart';

/// Test-only AuthController that skips platform-channel usage in onInit.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus to avoid
    // MissingPluginException for flutter_secure_storage in test env.
  }
}

/// Regression test for the `autoDisposeControllers: false` fix in
/// AuthController.showConnectedDialog.
///
/// pin_code_fields 8.0.1's internal State.dispose() disposes the passed
/// `controller`/`focusNode` when `autoDisposeControllers` is true (default).
/// The dialog ALSO disposes them in its `.then()` cleanup after the dialog
/// closes → double-dispose assertion ("A TextEditingController was used
/// after being disposed") whenever the dialog is closed in debug builds.
void main() {
  late _TestAuthController controller;

  setUp(() {
    Get.reset();
    controller = _TestAuthController();
    Get.put<AuthController>(controller, permanent: true);
    // Simulate a logged-in user so the dialog can render (it shows the
    // doctor name + OTP entry, not requiring any backend call).
    controller.currentUser.value = userPatient();
    controller.isLoggedIn.value = true;
    controller.errorMessage.value = '';
    controller.isLoading.value = false;
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets(
      'showConnectedDialog opens and closes without double-dispose',
      (tester) async {
    final doctor = doctorBasic(placeId: 'dialog_place', name: 'City Clinic');

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Center(child: Text('launch'))),
      ),
    );
    await tester.pump();

    // Fire the dialog (don't await — it resolves when the dialog closes).
    final dialogFuture = controller.showConnectedDialog(doctor);

    // Let the dialog route + OTP field animations build.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Verify Connection'), findsOneWidget);
    expect(find.text('City Clinic'), findsOneWidget);

    // The dialog auto-shows the demo-OTP toast (top snackbar): the code
    // is "sent" after a 3s delay, then the snackbar displays for 6s. Pump
    // past the whole window and force-close any remainder BEFORE tapping
    // Cancel so the toast can't intercept the hit-test on the dialog's
    // Cancel button.
    await tester.pump(const Duration(seconds: 4)); // 3s send delay fires
    await tester.pump(const Duration(seconds: 7)); // 6s display expires
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    Get.closeAllSnackbars();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // ── Close via Cancel → runs the .then() cleanup that disposes
    //    otpController/focusNode. The double-dispose bug would throw here. ──
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // dialog pop

    await dialogFuture;

    // Dialog is gone and no exception escaped teardown.
    expect(find.text('Verify Connection'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
