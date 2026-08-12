import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/controllers/doctor_controller.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/screens/doctor/doctor_profile_screen.dart';

import '../helpers/test_data.dart';

/// Test double that skips any work the real controller would start in
/// onInit (mirrors the pattern in doctor_detail_screen_test.dart).
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TestDoctorController extends DoctorController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> updateDoctorUpiId(String upiId) async {
    final doctor = currentDoctor.value;
    if (doctor == null) return;
    final trimmed = upiId.trim();
    currentDoctor.value = doctor.copyWith(
      upiId: trimmed.isEmpty ? null : trimmed,
    );
  }
}

/// Lets every flutter_animate effect on the profile screen run to
/// completion (the header, sections and bottom actions use fadeIn/slideY
/// backed by Future.delayed timers, which would otherwise trip the
/// "Timer is still pending" guard at the end of the test).
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// Registers a fresh [_TestDoctorController] already holding [doctor] and
/// pumps a [DoctorProfileScreen] inside a [GetMaterialApp] (required for
/// Get.dialog/Get.snackbar to render).
///
/// Uses a tall viewport (1600px) so the Book button at the bottom of the
/// profile's scroll view and the buttons inside the QR dialog are all
/// visible and hit-testable — the default 800×600 test surface would put
/// them off-screen.
Future<_TestDoctorController> _pumpProfile(
  WidgetTester tester,
  DoctorModel doctor,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Get.reset();
  Get.put<AuthController>(_TestAuthController(), permanent: true);
  final controller = _TestDoctorController()..currentDoctor.value = doctor;
  Get.put<DoctorController>(controller, permanent: true);

  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: const DoctorProfileScreen(),
    ),
  );
  await tester.pump();
  await _settleAnimations(tester);
  return controller;
}

/// Opens the QR booking dialog from the profile's Book button.
Future<void> _openBookingDialog(WidgetTester tester) async {
  await tester.tap(find.text('Book'));
  await tester.pump();
}

/// Intercepts the clipboard platform channel so the test can assert exactly
/// what was copied (and so Clipboard.setData completes deterministically
/// without a real platform).
void _mockClipboard(WidgetTester tester, List<String> copied) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>;
        copied.add(args['text'] as String);
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}

void main() {
  testWidgets('Book button opens the QR booking dialog with the booking URL', (
    tester,
  ) async {
    final doctor = doctorBasic(placeId: 'qr_test', name: 'Dr. QR');
    await _pumpProfile(tester, doctor);

    // The Book action button is visible on the profile.
    expect(find.text('Book'), findsOneWidget);

    await _openBookingDialog(tester);      // Dialog content renders.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Scan to Book'), findsOneWidget);
      // The dialog's Share button (the profile page also has a 'Share'
      // bottom action, so scope to the dialog).
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Share'),
        ),
        findsOneWidget,
      );
      expect(find.text('Open Page'), findsOneWidget);
      // The in-app deep-link copy button was removed.
      expect(find.text('Copy App Deep Link'), findsNothing);

    // A QR code widget is rendered.
    expect(find.byType(QrImageView), findsOneWidget);

    // The QR encodes the booking page URL for this doctor —
    // qr_flutter's QrImageView keeps its data private, so we assert the
    // URL that both the QR code and the tappable URL text below it are
    // built from.
    final expectedUrl = AppConstants.bookingPageUrl(
      doctor.placeId,
      doctorName: doctor.name,
    );
    expect(expectedUrl, startsWith('https://'));
    expect(expectedUrl, contains('/book/${doctor.placeId}'));
    expect(expectedUrl, contains('token=')); // shared secret in URL
    expect(find.text(expectedUrl), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets(
    'QR code encodes the static-host bookingPageUrl (not the Supabase URL)',
    (tester) async {
      final doctor = doctorBasic(placeId: 'qr_shape', name: 'Dr. Shape');
      await _pumpProfile(tester, doctor);

      await _openBookingDialog(tester);
      expect(find.byType(Dialog), findsOneWidget);

      // The QR widget is rendered — qr_flutter 4.x stores its data in a
      // private field with no public accessor, so we assert the exact URL
      // the dialog builds (DoctorProfileScreen feeds this same string to
      // QrImageView(data:)) plus the tappable URL text it renders.
      expect(find.byType(QrImageView), findsOneWidget);

      final bookingUrl = AppConstants.bookingPageUrl(
        doctor.placeId,
        doctorName: doctor.name,
      );
      expect(find.text(bookingUrl), findsOneWidget);

      // Static-host shape: HTTPS on the bookingHost domain — and NOT the
      // *.supabase.co Edge Function URL (which serves text/plain and made
      // browsers show raw HTML instead of rendering the page).
      expect(bookingUrl, startsWith('https://'));
      expect(bookingUrl, contains(AppConstants.bookingHost));
      expect(bookingUrl, isNot(contains(AppConstants.supabaseUrl)));

      // Path + query shape: /book/<placeId>?token=...&name=...
      expect(bookingUrl, contains('/book/${doctor.placeId}'));
      expect(bookingUrl, contains('token=${AppConstants.bookingSharedSecret}'));
      expect(bookingUrl, contains('name=${Uri.encodeComponent(doctor.name)}'));

      await _settleAnimations(tester);
    },
  );

  testWidgets('Share opens the system share sheet with the booking URL', (
    tester,
  ) async {
    final doctor = doctorBasic(placeId: 'share_test', name: 'Dr. Share');
    await _pumpProfile(tester, doctor);

    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        null,
      );
    });

    await _openBookingDialog(tester);
    expect(find.byType(Dialog), findsOneWidget);

    // The dialog's Share button (the profile also has a 'Share' action
    // button, so scope the finder to the dialog).
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Share')),
    );
    await tester.pump();

    // The system share sheet was invoked with the booking URL in the
    // shared text.
    expect(calls, isNotEmpty, reason: 'Share.share must be invoked');
    final args = calls.last.arguments as Map<dynamic, dynamic>;
    final sharedText = args['text'].toString();
    expect(
      sharedText,
      contains(
        AppConstants.bookingPageUrl(doctor.placeId, doctorName: doctor.name),
      ),
    );

    await _settleAnimations(tester);
  });

  testWidgets('close button dismisses the QR dialog without copying', (
    tester,
  ) async {
    final doctor = doctorBasic(placeId: 'close_test', name: 'Dr. Close');
    await _pumpProfile(tester, doctor);

    final copied = <String>[];
    _mockClipboard(tester, copied);

    await _openBookingDialog(tester);
    expect(find.byType(Dialog), findsOneWidget);

    // Tap the close (X) icon button in the dialog header.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Scan to Book'), findsNothing);
    expect(copied, isEmpty); // nothing copied
    expect(find.text('Booking link copied'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('UPI Payment ID card shows the fallback and saves the doctor '
      'UPI ID', (tester) async {
    final doctor = doctorBasic(placeId: 'upi_test', name: 'Dr. UPI');
    final controller = await _pumpProfile(tester, doctor);

    // The card renders with the unset fallback + an Add affordance.
    await tester.scrollUntilVisible(
      find.text('UPI Payment ID'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(
      find.text('Not set — patients pay the default clinic VPA.'),
      findsOneWidget,
    );
    expect(find.text('Add'), findsOneWidget);

    // Open the edit dialog, type a UPI ID and save.
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Dialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'clinic@okhdfcbank');
    await tester.tap(find.text('Save'));
    await tester.pump();
    // Let the dialog's exit transition fully finish (the fading TextField
    // still shows the value while the route animates out).
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // The controller (and card) reflect the saved value in-place.
    expect(controller.currentDoctor.value!.upiId, 'clinic@okhdfcbank');
    expect(find.text('clinic@okhdfcbank'), findsOneWidget);
    expect(find.text('Add'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('UPI Payment ID updated'), findsOneWidget);

    // Let the success snackbar's auto-dismiss timer fire.
    await tester.pump(const Duration(seconds: 5));
    await _settleAnimations(tester);
  });
}
