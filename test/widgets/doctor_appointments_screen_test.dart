import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/doctor_controller.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/services/quantupi_payment_service.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:DrsListing/screens/doctor/doctor_appointments_screen.dart';
import 'package:DrsListing/widgets/appointment_date_filter.dart';

import '../helpers/test_data.dart';

/// Minimal stand-in for the patient-history route so the tap-branch can be
/// asserted without pulling the real screen's network-heavy widgets in.
class _HistoryMarkerScreen extends StatelessWidget {
  const _HistoryMarkerScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('HISTORY_PAGE_MARKER'));
  }
}

/// Fakes the url_launcher platform so [LaunchService.phone] can be asserted
/// without touching the platform channel (see launch_service_test.dart).
class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchCalls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchCalls.add(url);
    return true;
  }
}

/// Fake image_picker platform that returns a real, decodable JPEG from the
/// gallery — so the full pick → process → preview pipeline runs in tests.
class _FakeGalleryPicker extends ImagePickerPlatform {
  final Uint8List imageBytes;

  _FakeGalleryPicker(this.imageBytes);

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    return XFile.fromData(imageBytes, name: 'rx_test.jpg');
  }
}

/// Builds a small, valid JPEG in-memory (no asset files needed) that the
/// PrescriptionImageOptimizer can actually decode.
Uint8List _fakeJpegBytes() {
  final src = img.Image(width: 300, height: 533); // ~9:16 photo
  img.fill(src, color: img.ColorRgb8(245, 245, 245));
  return Uint8List.fromList(img.encodeJpg(src, quality: 90));
}

/// Test double that skips Supabase calls but records status updates so we
/// can assert exactly what the Confirm action requested.
class _TestDoctorController extends DoctorController {
  final List<String> updatedIds = [];
  final List<String> updatedStatuses = [];

  /// (appointmentId, status) pairs from the Mark Paid / Refund actions.
  final List<(String, String)> markedPayments = [];

  /// (appointmentId, refundMethod) pairs from refund actions — records HOW
  /// the refund was given back (online / cash) for assertions.
  final List<(String, String)> refunds = [];

  /// Return value for [markPaymentStatus] — lets the failure path be tested.
  bool markPaymentResult = true;

  /// When set, [markPaymentStatus] waits on this completer before
  /// resolving — lets the confirm dialog's in-flight loading spinner be
  /// observed.
  Completer<bool>? markPaymentGate;

  @override
  Future<void> updateAppointmentStatus(
    String appointmentId,
    String status,
  ) async {
    updatedIds.add(appointmentId);
    updatedStatuses.add(status);
  }

  @override
  Future<bool> markPaymentStatus(
    PaymentModel payment,
    String status, {
    String? refundMethod,
    DateTime? refundedAt,
    String? refundUpiId,
    String? refundTransactionId,
    String? refundRawResponse,
  }) async {
    markedPayments.add((payment.appointmentId, status));
    if (refundMethod != null) {
      refunds.add((payment.appointmentId, refundMethod));
    }
    if (markPaymentGate != null) return markPaymentGate!.future;
    return markPaymentResult;
  }
}

/// Lets the flutter_animate effects on the screen run to completion (the
/// header and cards use fadeIn/slideY backed by Future.delayed timers,
/// which would otherwise trip the "Timer is still pending" guard).
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// A payment row factory for the appointment cards.
PaymentModel paymentFor({
  String appointmentId = 'APT_PAY',
  String paymentStatus = 'Pending',
  String paymentMethod = 'offline',
  double amount = 1000,
}) {
  return PaymentModel(
    id: 'pay_$appointmentId',
    appointmentId: appointmentId,
    patientId: 'user_1',
    doctorPlaceId: 'place_dash_1',
    paymentStatus: paymentStatus,
    paymentMethod: paymentMethod,
    amount: amount,
  );
}

Future<_TestDoctorController> _pumpScreen(
  WidgetTester tester,
  List<AppointmentModel> appointments, {
  List<GetPage>? getPages,
  Map<String, PaymentModel>? payments,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Get.reset();
  final controller = _TestDoctorController();
  controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
  controller.appointments.assignAll(appointments);
  if (payments != null) {
    controller.paymentsByAppointment.value = payments;
  }
  Get.put<DoctorController>(controller, permanent: true);

  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      getPages: getPages,
      home: const DoctorAppointmentsScreen(),
    ),
  );
  await tester.pump();
  await _settleAnimations(tester);
  return controller;
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

/// Finder for the preview's 9:16 portrait frame (AspectRatio 9/16).
Finder aspectRatioFinder() => find.byWidgetPredicate(
  (w) => w is AspectRatio && (w.aspectRatio - (9 / 16)).abs() < 0.001,
);

/// Waits for the optimize `compute` isolate to finish and the preview sheet
/// to replace the processing dialog. The isolate runs on real time (the
/// fake async clock can't advance it), so we poll with short real-time
/// delays instead of one fixed wait — robust on slow CI machines. Bounded
/// to a few seconds so a genuinely broken flow still fails fast.
/// `pumpAndSettle` can't be used here: the processing dialog's
/// indeterminate spinner never settles.
Future<void> _waitForPreviewSheet(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.text('Prescription Preview').evaluate().isNotEmpty) return;
  }
  fail('Prescription Preview sheet never appeared after gallery pick');
}

void main() {
  testWidgets('Pending appointment shows Confirm action, not Mark Completed', (
    tester,
  ) async {
    final controller = await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_PENDING',
        patientName: 'Pending Patient',
        appointmentDate: _todayKey(),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.pending,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    // Patient name renders.
    expect(find.text('Pending Patient'), findsOneWidget);
    // Status badge shows Pending.
    expect(find.text('Pending'), findsOneWidget);
    // Pending gets the Confirm action and no Mark Completed.
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Mark Completed'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);

    await _settleAnimations(tester);
    expect(controller.updatedIds, isEmpty);
  });

  testWidgets('Upcoming appointment shows Mark Completed, not Confirm', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_UPCOMING',
        patientName: 'Upcoming Patient',
        appointmentDate: _todayKey(),
        appointmentTime: '11:00 AM',
        status: AppointmentStatus.upcoming,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    expect(find.text('Upcoming Patient'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Mark Completed'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets(
    'Tapping Confirm opens dialog and accepting calls updateAppointmentStatus with Upcoming',
    (tester) async {
      final controller = await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_CONFIRM_ME',
          patientName: 'Awaits Confirmation',
          appointmentDate: _todayKey(),
          appointmentTime: '09:00 AM',
          status: AppointmentStatus.pending,
          doctorPlaceId: 'place_dash_1',
        ),
      ]);

      // Open the confirm dialog and fully settle its entrance animation.
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Confirm Appointment'), findsOneWidget);
      expect(find.text('Not Now'), findsOneWidget);

      // Accept the booking.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pump();

      // The controller must be asked to move this booking to Upcoming.
      expect(controller.updatedIds, ['APT_CONFIRM_ME']);
      expect(controller.updatedStatuses, [AppointmentStatus.upcoming]);

      // Dialog closes after the pop animation.
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      await _settleAnimations(tester);
    },
  );

  testWidgets('Not Now keeps the appointment pending', (tester) async {
    final controller = await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_KEEP_PENDING',
        patientName: 'Hesitant Patient',
        appointmentDate: _todayKey(),
        appointmentTime: '08:00 AM',
        status: AppointmentStatus.pending,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not Now'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(controller.updatedIds, isEmpty);
    expect(controller.updatedStatuses, isEmpty);

    await _settleAnimations(tester);
  });

  testWidgets(
    'Card hides Symptoms/Notes and opens the full details sheet on tap',
    (tester) async {
      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_DETAILS',
          patientName: 'Detail Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
          symptoms: 'Fever and headache since two days',
          // The patient's phone lives ONLY in the details sheet now — the
          // card's former phone row was replaced by the consultation row.
          patientPhone: '9876543210',
        ),
      ]);

      // The card itself no longer shows the Symptoms/Notes block NOR the
      // patient's phone with a call affordance (that spot now shows the
      // consultation type).
      expect(find.text('Symptoms / Notes'), findsNothing);
      expect(find.text('9876543210'), findsNothing);
      expect(find.text('Patient Phone'), findsNothing);

      // Tap the card → the details sheet opens with the full information.
      await tester.tap(find.text('Detail Patient'));
      await tester.pumpAndSettle();

      expect(find.text('Symptoms / Notes'), findsOneWidget);
      expect(find.text('Fever and headache since two days'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      // The number appears only in the sheet.
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Call Now'), findsOneWidget);
      expect(find.text('Appointment ID'), findsOneWidget);

      // Close the sheet.
      await tester.tap(find.byKey(const ValueKey('appointment_details_close')));
      await tester.pumpAndSettle();
      expect(find.text('Call Now'), findsNothing);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'the patient phone is no longer on the card — dialing lives in the '
    'details sheet',
    (tester) async {
      final fake = _FakeUrlLauncher();
      UrlLauncherPlatform.instance = fake;
      addTearDown(
        () => UrlLauncherPlatform.instance = UrlLauncherPlatform.instance,
      );

      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_CALL',
          patientName: 'Callable Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
          patientPhone: '9876543210',
        ),
      ]);

      // No phone row on the card anymore — the number is not tappable
      // from the list.
      expect(find.text('9876543210'), findsNothing);
      expect(find.text('Patient Phone'), findsNothing);

      // The number + dial action live in the details sheet instead.
      await tester.tap(find.text('Callable Patient'));
      await tester.pumpAndSettle();

      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Call Now'), findsOneWidget);

      await tester.tap(find.text('Call Now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(fake.launchCalls, ['tel:9876543210']);

      await tester.tap(find.byKey(const ValueKey('appointment_details_close')));
      await tester.pumpAndSettle();
      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'tapping a returning patient\'s card opens the history timeline page',
    (tester) async {
      await _pumpScreen(
        tester,
        [
          appointmentBasic(
            appointmentId: 'APT_VISIT_1',
            patientName: 'Repeat Rita',
            appointmentDate: _todayKey(),
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.completed,
            doctorPlaceId: 'place_dash_1',
            patientPhone: '9988776655',
            symptoms: 'Fever',
          ),
          appointmentBasic(
            appointmentId: 'APT_VISIT_2',
            patientName: 'Repeat Rita',
            appointmentDate: _todayKey(),
            appointmentTime: '11:00 AM',
            status: AppointmentStatus.upcoming,
            doctorPlaceId: 'place_dash_1',
            patientPhone: '9988776655',
            symptoms: 'Cough',
          ),
        ],
        getPages: [
          GetPage(
            name: AppRoutes.patientHistory,
            page: () => const _HistoryMarkerScreen(),
          ),
        ],
      );

      // Same mobile → two visits → tapping the card navigates to the
      // history timeline instead of the details sheet.
      await tester.tap(find.text('Repeat Rita').first);
      await tester.pumpAndSettle();

      expect(find.text('HISTORY_PAGE_MARKER'), findsOneWidget);
      expect(find.text('Appointment ID'), findsNothing);

      await _settleAnimations(tester);
    },
  );

  testWidgets('legacy rows without a consultation type render no info row', (
    tester,
  ) async {
    // Legacy rows (pre consultation_type column) must not show a
    // Consultation row — and never fall back to call_number (the doctor's
    // own number) anywhere on the card.
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_NO_TYPE',
        patientName: 'Legacy Patient',
        appointmentDate: _todayKey(),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
        doctorPlaceId: 'place_dash_1',
        callNumber: '+911111111111',
      ),
    ]);

    expect(find.text('Patient Phone'), findsNothing);
    expect(find.byIcon(Icons.phone_rounded), findsNothing);
    // No consultationType → no Consultation row renders either.
    expect(find.text('Consultation'), findsNothing);
    // The doctor's own number never leaks onto the card.
    expect(find.text('+911111111111'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets(
    'Header search filters appointments across dates and hides the calendar',
    (tester) async {
      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_ALICE',
          patientName: 'Alice Green',
          appointmentDate: _todayKey(),
          appointmentTime: '09:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
        appointmentBasic(
          appointmentId: 'APT_BOB',
          patientName: 'Bob Brown',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ]);

      expect(find.text('Alice Green'), findsOneWidget);
      expect(find.text('Bob Brown'), findsOneWidget);

      // Open the search field via the header search toggle.
      await tester.tap(
        find.byKey(const ValueKey('appointments_search_toggle')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // While searching the date filter is hidden so results span dates.
      expect(find.byType(AppointmentDateFilter), findsNothing);

      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pump();
      expect(find.text('Alice Green'), findsOneWidget);
      expect(find.text('Bob Brown'), findsNothing);

      // Clearing the query restores every appointment.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('Alice Green'), findsOneWidget);
      expect(find.text('Bob Brown'), findsOneWidget);

      // Closing search brings the calendar back.
      await tester.tap(
        find.byKey(const ValueKey('appointments_search_toggle')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppointmentDateFilter), findsOneWidget);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'Tele consultation completion offers the prescription upload dialog',
    (tester) async {
      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_TELE',
          patientName: 'Tele Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
          consultationType: 'tele',
        ),
      ]);

      // Open the complete flow → the prescription dialog appears.
      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Complete Appointment'), findsOneWidget);
      expect(find.text('Upload Prescription & Complete'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Complete without Prescription'), findsOneWidget);

      await tester.tap(find.text('Complete without Prescription'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'Choose from Gallery closes the dialog and aborts cleanly when the picker is cancelled',
    (tester) async {
      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_GALLERY_CANCEL',
          patientName: 'Gallery Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ]);

      // Open the complete flow → the gallery option is present.
      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Choose from Gallery'), findsOneWidget);

      // In tests image_picker returns null (no platform channel), so the
      // flow must close the dialog and abort without leaving an overlay.
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'gallery pick shows the ImageProcessingDialog while bytes are processed',
    (tester) async {
      // A fake picker that returns a real image means the pick succeeds and
      // the flow proceeds to the processing step (the pause between pick
      // and preview where the dialog must appear).
      final originalPicker = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = _FakeGalleryPicker(_fakeJpegBytes());
      addTearDown(() => ImagePickerPlatform.instance = originalPicker);

      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_GALLERY_OK',
          patientName: 'Gallery Success Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ]);

      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Choose from Gallery'), findsOneWidget);

      // Tap the gallery path → the pick resolves instantly (fake) and the
      // processing dialog is shown while the image is decoded/padded.
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The ImageProcessingDialog (non-dismissible) must be up.
      expect(find.text('Processing Image…'), findsOneWidget);
      expect(
        find.text('Enhancing quality & preparing the prescription'),
        findsOneWidget,
      );

      // The optimize step runs in a real isolate (compute), which the fake
      // async test clock can't advance — poll until the preview sheet
      // replaces the processing dialog (bounded, CI-safe).
      await _waitForPreviewSheet(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await _settleAnimations(tester);

      expect(find.text('Prescription Preview'), findsOneWidget);
      expect(find.text('Upload & Complete'), findsOneWidget);

      // The preview frame is exactly 9:16.
      expect(aspectRatioFinder(), findsOneWidget);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'gallery pick preview renders the padded 9:16 image, never cropped',
    (tester) async {
      final originalPicker = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = _FakeGalleryPicker(_fakeJpegBytes());
      addTearDown(() => ImagePickerPlatform.instance = originalPicker);

      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_GALLERY_RATIO',
          patientName: 'Ratio Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ]);

      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Processing dialog appears first (same pause as the device flow).
      expect(find.text('Processing Image…'), findsOneWidget);

      // Let the compute isolate finish in real time, then pump the
      // microtasks so the preview sheet renders.
      await _waitForPreviewSheet(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await _settleAnimations(tester);

      // The preview image is rendered with BoxFit.contain inside the 9:16
      // frame — letterboxed padding, so the whole page is visible.
      final imageFinder = find.descendant(
        of: aspectRatioFinder(),
        matching: find.byType(Image),
      );
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.fit, BoxFit.contain);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'Video consultation shows the video label in the prescription dialog',
    (tester) async {
      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_VIDEO',
          patientName: 'Video Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '11:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
          consultationType: 'video',
        ),
      ]);

      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Video Consultation with Video Patient'),
        findsOneWidget,
      );

      // Close via the camera path cancel (image_picker returns null in
      // tests → flow aborts cleanly).
      await tester.tap(find.text('Upload Prescription & Complete'));
      await tester.pump();
      await tester.pumpAndSettle();

      // No dialog remains after the picker returns null/cancelled.
      expect(find.byType(Dialog), findsNothing);

      await _settleAnimations(tester);
    },
  );

  testWidgets('In-Clinic completion also offers the prescription upload', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_CLINIC',
        patientName: 'Clinic Patient',
        appointmentDate: _todayKey(),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
        doctorPlaceId: 'place_dash_1',
        consultationType: 'clinic',
      ),
    ]);

    await tester.tap(find.text('Mark Completed'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    // The camera + gallery upload options are offered for every
    // consultation type now.
    expect(find.text('Upload Prescription & Complete'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    expect(find.text('Complete without Prescription'), findsOneWidget);
    expect(
      find.textContaining('In-Clinic Visit with Clinic Patient'),
      findsOneWidget,
    );

    await tester.tap(find.text('Complete without Prescription'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets(
    'Completed appointment shows uploaded prescription gallery thumbnails',
    (tester) async {
      await _pumpScreen(tester, [
        appointmentBasic(
          appointmentId: 'APT_WITH_RX',
          patientName: 'Rx Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.completed,
          doctorPlaceId: 'place_dash_1',
          consultationType: 'tele',
          prescriptionUrls: const [
            'https://example.com/rx1.jpg',
            'https://example.com/rx2.jpg',
          ],
        ),
      ]);

      // The gallery header is shown on the card (compact strip).
      expect(find.text('Prescriptions (2)'), findsOneWidget);
      // The compact horizontal strip renders one tile per URL.
      expect(find.byType(ListView), findsWidgets);

      await _settleAnimations(tester);
    },
  );

  testWidgets('Expanded calendar shows the current month by default', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_CAL',
        patientName: 'Cal Patient',
        appointmentDate: _todayKey(),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    final now = DateTime.now();
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final expectedHeader = '${monthNames[now.month - 1]} ${now.year}';

    // Expand the calendar via the compact-view toggle.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The expanded header shows the current month, not a random one.
    expect(find.text(expectedHeader), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets(
    'appointment card shows all data on a narrow screen without overflow',
    (tester) async {
      // Small phone (320dp wide) — the old layout squeezed Date/Time into
      // a shared wrap line and Consultation type + Patient phone into one
      // half-width row each. The redesigned card gives every datum its own
      // full-width row, so nothing hides or overflows.
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Get.reset();
      final controller = _TestDoctorController();
      controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
      controller.appointments.assignAll([
        appointmentBasic(
          appointmentId: 'APT_NARROW',
          patientName: 'Narrow Appointment Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:30 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
          consultationType: 'video',
          patientPhone: '9876543210',
        ),
      ]);
      Get.put<DoctorController>(controller, permanent: true);

      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          home: const DoctorAppointmentsScreen(),
        ),
      );
      await tester.pump();
      await _settleAnimations(tester);

      // No RenderFlex overflow on the narrow screen.
      expect(tester.takeException(), isNull);

      // Every field renders on its own row — nothing hidden or squeezed.
      // The consultation type spans the full card width below Date / Time
      // (the phone no longer renders on the card).
      expect(find.text('Narrow Appointment Patient'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Type'), findsNothing);
      expect(find.text('Video Consultation'), findsOneWidget);
      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Patient Phone'), findsNothing);
      expect(find.text('9876543210'), findsNothing);
      expect(find.text('Upcoming'), findsOneWidget);

      // The consultation row really spans the full card width (not a
      // half-width grid cell) — its value text is far wider than the Time
      // cell's.
      final consultationRect = tester.getRect(find.text('Video Consultation'));
      final timeRect = tester.getRect(find.text('10:30 AM'));
      expect(consultationRect.width, greaterThan(timeRect.width * 1.5));

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'offline Pending payment shows the payment line with Mark Paid and Refund',
    (tester) async {
      final controller = await _pumpScreen(
        tester,
        [
          appointmentBasic(
            appointmentId: 'APT_PAY',
            patientName: 'Pay Patient',
            appointmentDate: _todayKey(),
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.upcoming,
            doctorPlaceId: 'place_dash_1',
            consultationType: 'clinic',
          ),
        ],
        payments: {'APT_PAY': paymentFor(appointmentId: 'APT_PAY')},
      );

      // The payment line shows the amount and the Pending chip.
      expect(find.text('Payment · ₹1000'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      // Offline Pending → the clinic can settle it right from the card.
      expect(find.text('Mark Paid'), findsOneWidget);
      expect(find.text('Refund'), findsOneWidget);

      await _settleAnimations(tester);
      expect(controller.markedPayments, isEmpty);
    },
  );

  testWidgets(
    'Mark Completed is disabled while the fee is Pending and enabled once paid',
    (tester) async {
      final controller = await _pumpScreen(
        tester,
        [
          appointmentBasic(
            appointmentId: 'APT_PAY_GATE',
            patientName: 'Gate Patient',
            appointmentDate: _todayKey(),
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.upcoming,
            doctorPlaceId: 'place_dash_1',
            consultationType: 'tele',
          ),
        ],
        payments: {
          'APT_PAY_GATE': paymentFor(appointmentId: 'APT_PAY_GATE'),
        },
      );

      // The button renders but is inert while the fee is unpaid — tapping
      // it must NOT open the complete flow.
      expect(find.text('Mark Completed'), findsOneWidget);
      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing,
          reason: 'an unpaid appointment must not be completable');
      expect(find.text('Complete Appointment'), findsNothing);

      // The clinic submits the payment status (Mark Paid → map reloads
      // with status Paid) — the same card now completes.
      controller.paymentsByAppointment.value = {
        'APT_PAY_GATE': paymentFor(
          appointmentId: 'APT_PAY_GATE',
          paymentStatus: 'Paid',
        ),
      };
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Complete Appointment'), findsOneWidget);

      // Close the dialog cleanly (completes without a prescription).
      await tester.tap(find.text('Complete without Prescription'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(controller.updatedStatuses, [AppointmentStatus.completed]);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'chained flow: Mark Paid → card flips to Paid → Mark Completed enabled → '
    'complete', (tester) async {
      final controller = await _pumpScreen(
        tester,
        [
          appointmentBasic(
            appointmentId: 'APT_CHAIN',
            patientName: 'Chain Patient',
            appointmentDate: _todayKey(),
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.upcoming,
            doctorPlaceId: 'place_dash_1',
            consultationType: 'clinic',
          ),
        ],
        payments: {
          'APT_CHAIN': paymentFor(appointmentId: 'APT_CHAIN', amount: 600),
        },
      );

      // Step 1 — the fee is Pending: settle actions show and Mark
      // Completed is inert.
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Mark Paid'), findsOneWidget);
      expect(find.text('Refund'), findsOneWidget);
      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing,
          reason: 'an unpaid appointment must not be completable');

      // Step 2 — the clinic settles the fee: Mark Paid → confirm dialog.
      await tester.tap(find.text('Mark Paid'));
      await tester.pumpAndSettle();
      expect(find.text('Mark Payment Paid'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Paid'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(controller.markedPayments, [('APT_CHAIN', 'Paid')]);
      expect(find.byType(Dialog), findsNothing);

      // Step 3 — the controller reloads the payment map (markPaymentStatus
      // → loadPayments): chip flips to Paid, settle actions disappear.
      controller.paymentsByAppointment.value = {
        'APT_CHAIN': paymentFor(
          appointmentId: 'APT_CHAIN',
          amount: 600,
          paymentStatus: 'Paid',
        ),
      };
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Paid'), findsWidgets,
          reason: 'payment chip must flip to Paid after the reload');
      expect(find.text('Pending'), findsNothing);
      expect(find.text('Mark Paid'), findsNothing);
      expect(find.text('Refund'), findsOneWidget,
          reason: 'a Paid payment is refundable — Refund stays after settling');

      // Let the 'Payment marked as Paid' success snackbar auto-dismiss
      // before the completion step — a lingering overlay snackbar would
      // intercept the taps below (it sits above the Navigator in the
      // overlay).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Step 4 — the settled fee unlocks Mark Completed; completing flips
      // the appointment to Completed.
      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Complete Appointment'), findsOneWidget);
      await tester.tap(find.text('Complete without Prescription'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(controller.updatedStatuses, [AppointmentStatus.completed]);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'details sheet shows the fee/payment card for an appointment with a payment',
    (tester) async {
      await _pumpScreen(
        tester,
        [
          appointmentBasic(
            appointmentId: 'APT_PAY_SHEET',
            patientName: 'Sheet Pay Patient',
            appointmentDate: _todayKey(),
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.upcoming,
            doctorPlaceId: 'place_dash_1',
          ),
        ],
        payments: {
          'APT_PAY_SHEET': paymentFor(
            appointmentId: 'APT_PAY_SHEET',
            paymentStatus: 'Paid',
            paymentMethod: 'online',
            amount: 800,
          ),
        },
      );

      // The card shows the payment line; tapping it must surface the same
      // fee info inside the details sheet (beside the actions).
      expect(find.text('Payment · ₹800'), findsOneWidget);
      await tester.tap(find.text('Sheet Pay Patient'));
      await tester.pumpAndSettle();

      expect(find.text('Appointment ID'), findsOneWidget);
      // Amount + method render on the sheet's payment card. The 'Paid' chip
      // appears twice (the card behind the sheet + the sheet's own chip).
      expect(find.text('₹800'), findsOneWidget);
      expect(find.text('Online (UPI)'), findsOneWidget);
      expect(find.text('Paid'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('appointment_details_close')));
      await tester.pumpAndSettle();
      await _settleAnimations(tester);
    },
  );

  testWidgets('details sheet always shows the fresh payment status — '
      'reopen after Mark Paid reads the updated map', (tester) async {
    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_PAY_SHEET',
          patientName: 'Sheet Pay Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        'APT_PAY_SHEET': paymentFor(
          appointmentId: 'APT_PAY_SHEET',
          amount: 1000,
        ),
      },
    );

    // The sheet is a snapshot taken at OPEN time: while the payment is
    // still Pending it shows Pending (card chip + sheet chip).
    await tester.tap(find.text('Sheet Pay Patient'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment ID'), findsOneWidget);
    expect(find.text('Pending'), findsNWidgets(2));
    expect(find.text('Paid'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('appointment_details_close')));
    await tester.pumpAndSettle();

    // The clinic settles the fee (markPaymentStatus → loadPayments
    // replaces the map).
    controller.paymentsByAppointment.value = {
      'APT_PAY_SHEET': paymentFor(
        appointmentId: 'APT_PAY_SHEET',
        paymentStatus: 'Paid',
        amount: 1000,
      ),
    };
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Reopening the sheet re-reads the map, so the paid status is always
    // what the doctor last settled — no stale 'Pending' anywhere.
    await tester.tap(find.text('Sheet Pay Patient'));
    await tester.pumpAndSettle();
    expect(find.text('Paid'), findsNWidgets(2));
    expect(find.text('Pending'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('appointment_details_close')));
    await tester.pumpAndSettle();
    await _settleAnimations(tester);
  });

  testWidgets('Mark Paid confirm flips the offline payment to Paid', (
    tester,
  ) async {
    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_PAY',
          patientName: 'Pay Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {'APT_PAY': paymentFor(appointmentId: 'APT_PAY', amount: 1000)},
    );

    await tester.tap(find.text('Mark Paid'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Mark Payment Paid'), findsOneWidget);
    expect(
      find.textContaining('₹1000 received from Pay Patient'),
      findsOneWidget,
    );

    // The card's Mark Paid is a chip; the dialog confirm is an
    // ElevatedButton — uniquely findable.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Paid'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.markedPayments, [('APT_PAY', 'Paid')]);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Payment marked as Paid'), findsOneWidget);

    await _settleAnimations(tester);
    // Let the success snackbar's auto-dismiss timer (Get.snackbar) fire
    // so no timers are left pending when the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('Mark Paid refresh: card flips to Paid once payments reload', (
    tester,
  ) async {
    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_PAY',
          patientName: 'Pay Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {'APT_PAY': paymentFor(appointmentId: 'APT_PAY', amount: 1000)},
    );

    // Card starts Pending + actionable.
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Mark Paid'), findsOneWidget);

    await tester.tap(find.text('Mark Paid'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Paid'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    // The real controller reloads the payment map after the flip lands
    // (markPaymentStatus -> loadPayments), replacing it wholesale. The card
    // must rebuild: chip flips to Paid, settle actions disappear.
    controller.paymentsByAppointment.value = {
      'APT_PAY': paymentFor(
        appointmentId: 'APT_PAY',
        amount: 1000,
        paymentStatus: 'Paid',
      ),
    };
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Paid'), findsWidgets,
        reason: 'payment chip must flip to Paid after the reload');
    expect(find.text('Pending'), findsNothing,
        reason: 'the stale Pending chip must be gone');
    expect(find.text('Mark Paid'), findsNothing,
        reason: 'Mark Paid action must disappear once settled');
    expect(find.text('Refund'), findsOneWidget,
        reason: 'a Paid payment is refundable — Refund stays after settling');

    await _settleAnimations(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('Refund refresh: card flips to Refunded once payments reload', (
    tester,
  ) async {
    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_REFUND',
          patientName: 'Refund Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        'APT_REFUND': paymentFor(appointmentId: 'APT_REFUND', amount: 500),
      },
    );

    // Card starts Pending + actionable.
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Refund'), findsOneWidget);

    // New refund flow: Refund → method picker → Cash → confirm dialog.
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(find.text('Online (UPI)'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    expect(find.text('Refund Payment'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Refund'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(controller.markedPayments, [('APT_REFUND', 'Refunded')]);
    expect(controller.refunds, [('APT_REFUND', 'cash')]);
    expect(find.byType(Dialog), findsNothing);

    // Simulate the controller's post-flip reload of the payment map.
    controller.paymentsByAppointment.value = {
      'APT_REFUND': paymentFor(
        appointmentId: 'APT_REFUND',
        amount: 500,
        paymentStatus: 'Refunded',
      ),
    };
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Refunded'), findsWidgets,
        reason: 'payment chip must flip to Refunded after the reload');
    expect(find.text('Pending'), findsNothing,
        reason: 'the stale Pending chip must be gone');
    expect(find.text('Mark Paid'), findsNothing,
        reason: 'Mark Paid action must disappear once refunded');
    expect(find.text('Refund'), findsNothing,
        reason: 'Refund action must disappear once refunded');

    await _settleAnimations(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'chained flow: Refund → card flips to Refunded → Mark Completed stays '
    'enabled → complete', (tester) async {
      final controller = await _pumpScreen(
        tester,
        [
          appointmentBasic(
            appointmentId: 'APT_REFUND_CHAIN',
            patientName: 'Refund Chain Patient',
            appointmentDate: _todayKey(),
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.upcoming,
            doctorPlaceId: 'place_dash_1',
            consultationType: 'clinic',
          ),
        ],
        payments: {
          'APT_REFUND_CHAIN': paymentFor(
            appointmentId: 'APT_REFUND_CHAIN',
            amount: 500,
          ),
        },
      );

      // Step 1 — the fee is Pending: settle actions show and Mark
      // Completed is inert.
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Refund'), findsOneWidget);
      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing,
          reason: 'an unpaid appointment must not be completable');

      // Step 2 — the clinic refunds the fee: Refund → method picker →
      // Cash → confirm dialog.
      await tester.tap(find.text('Refund'));
      await tester.pumpAndSettle();
      expect(find.text('Online (UPI)'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      expect(find.text('Refund Payment'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Refund'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(controller.markedPayments, [('APT_REFUND_CHAIN', 'Refunded')]);
      expect(controller.refunds, [('APT_REFUND_CHAIN', 'cash')]);
      expect(find.byType(Dialog), findsNothing);

      // Step 3 — the controller reloads the payment map (markPaymentStatus
      // → loadPayments): chip flips to Refunded, settle actions disappear.
      controller.paymentsByAppointment.value = {
        'APT_REFUND_CHAIN': paymentFor(
          appointmentId: 'APT_REFUND_CHAIN',
          amount: 500,
          paymentStatus: 'Refunded',
        ),
      };
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Refunded'), findsWidgets,
          reason: 'payment chip must flip to Refunded after the reload');
      expect(find.text('Pending'), findsNothing);
      expect(find.text('Mark Paid'), findsNothing);
      expect(find.text('Refund'), findsNothing);

      // Let the 'Payment marked as Refunded' success snackbar auto-dismiss
      // before the completion step (a lingering overlay snackbar would
      // intercept the taps below).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Step 4 — a settled (refunded) fee does NOT re-lock Mark Completed:
      // the button stays enabled and completes the appointment.
      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Complete Appointment'), findsOneWidget);
      await tester.tap(find.text('Complete without Prescription'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(controller.updatedStatuses, [AppointmentStatus.completed]);

      await _settleAnimations(tester);
    },
  );

  testWidgets(
    'Mark Paid confirm shows a loading spinner while the update runs',
    (tester) async {
      final controller = await _pumpScreen(
        tester,
        [
          appointmentBasic(
            appointmentId: 'APT_PAY',
            patientName: 'Pay Patient',
            appointmentDate: _todayKey(),
            appointmentTime: '10:00 AM',
            status: AppointmentStatus.upcoming,
            doctorPlaceId: 'place_dash_1',
          ),
        ],
        payments: {
          'APT_PAY': paymentFor(appointmentId: 'APT_PAY', amount: 1000),
        },
      );

      // Hold the server update open so the in-dialog spinner is visible.
      controller.markPaymentGate = Completer<bool>();

      await tester.tap(find.text('Mark Paid'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Paid'));
      await tester.pump();

      // The confirm button shows the spinner and the dialog stays open
      // (the card's own Mark Paid chip behind the dialog is untouched).
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Mark Payment Paid'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Mark Paid'), findsNothing);

      // Resolve the update — the dialog closes and success shows.
      controller.markPaymentGate!.complete(true);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(controller.markedPayments, [('APT_PAY', 'Paid')]);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Payment marked as Paid'), findsOneWidget);

      await _settleAnimations(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Refund confirm flips the offline payment to Refunded', (
    tester,
  ) async {
    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_PAY',
          patientName: 'Pay Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {'APT_PAY': paymentFor(appointmentId: 'APT_PAY', amount: 500)},
    );

    // New refund flow: Refund → method picker → Cash → confirm dialog.
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(find.text('Online (UPI)'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Refund Payment'), findsOneWidget);
    expect(
      find.textContaining('₹500 as refunded to Pay Patient'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Refund'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.markedPayments, [('APT_PAY', 'Refunded')]);
    expect(controller.refunds, [('APT_PAY', 'cash')]);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Payment marked as Refunded'), findsOneWidget);

    await _settleAnimations(tester);
    // Let the success snackbar's auto-dismiss timer (Get.snackbar) fire
    // so no timers are left pending when the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('failed payment update shows an error snackbar, not success', (
    tester,
  ) async {
    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_PAY',
          patientName: 'Pay Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {'APT_PAY': paymentFor(appointmentId: 'APT_PAY', amount: 1000)},
    );
    // Simulate the write not landing (offline / RLS denial → 0 rows).
    controller.markPaymentResult = false;

    await tester.tap(find.text('Mark Paid'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Paid'));
    await tester.pump();
    await tester.pumpAndSettle();

    // The controller was still asked, but the UI must NOT claim success.
    expect(controller.markedPayments, [('APT_PAY', 'Paid')]);
    expect(find.text('Payment marked as Paid'), findsNothing);
    expect(
      find.text('Could not update the payment. Please try again.'),
      findsOneWidget,
    );

    await _settleAnimations(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('complete flow: an online Paid payment (from UPI booking) '
      'enables Mark Completed and completes the appointment', (tester) async {
    // The payment row exactly as the patient-side UPI booking flow records
    // it: method 'online', status 'Paid', transaction id + doctor VPA.
    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_PAID',
          patientName: 'Paid Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
          consultationType: 'video',
        ),
      ],
      payments: {
        'APT_PAID': paymentFor(
          appointmentId: 'APT_PAID',
          paymentStatus: 'Paid',
          paymentMethod: 'online',
          amount: 800,
        ),
      },
    );

    // The card shows the settled fee as an informational chip.
    expect(find.text('Payment · ₹800'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    // Mark Paid is gone (nothing to collect), but a Paid payment is
    // refundable — Refund stays available.
    expect(find.text('Mark Paid'), findsNothing);
    expect(find.text('Refund'), findsOneWidget,
        reason: 'a Paid payment is refundable — Refund stays');

    // The fee was paid up-front, so Mark Completed is ENABLED (not the
    // greyed-out state a Pending payment would force).
    expect(find.text('Mark Completed'), findsOneWidget);
    await tester.tap(find.text('Mark Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Complete Appointment'), findsOneWidget);

    // Completing without a prescription flips the appointment to Completed.
    await tester.tap(find.text('Complete without Prescription'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(controller.updatedStatuses, [AppointmentStatus.completed]);

    await _settleAnimations(tester);
  });

  testWidgets('complete flow: a Refunded payment also keeps Mark Completed '
      'enabled and completes the appointment', (tester) async {
    // A payment row the clinic already refunded (stored status 'Refunded')
    // — like Paid, a settled payment must NOT re-lock completion (only
    // Pending blocks it).
    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_REFUNDED',
          patientName: 'Refunded Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
          consultationType: 'clinic',
        ),
      ],
      payments: {
        'APT_REFUNDED': paymentFor(
          appointmentId: 'APT_REFUNDED',
          paymentStatus: 'Refunded',
          amount: 500,
        ),
      },
    );

    // The card shows the settled fee as an informational chip.
    expect(find.text('Payment · ₹500'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
    // No settle actions for an already-settled payment.
    expect(find.text('Mark Paid'), findsNothing);
    expect(find.text('Refund'), findsNothing);

    // The fee is settled, so Mark Completed is ENABLED (not the
    // greyed-out state a Pending payment would force).
    expect(find.text('Mark Completed'), findsOneWidget);
    await tester.tap(find.text('Mark Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Complete Appointment'), findsOneWidget);

    // Completing without a prescription flips the appointment to Completed.
    await tester.tap(find.text('Complete without Prescription'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(controller.updatedStatuses, [AppointmentStatus.completed]);

    await _settleAnimations(tester);
  });

  testWidgets('card shows no payment line when no payment exists', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      appointmentBasic(
        appointmentId: 'APT_NOPAY',
        patientName: 'No Pay Patient',
        appointmentDate: _todayKey(),
        appointmentTime: '10:00 AM',
        status: AppointmentStatus.upcoming,
        doctorPlaceId: 'place_dash_1',
      ),
    ]);

    expect(find.textContaining('Payment ·'), findsNothing);
    expect(find.text('Mark Paid'), findsNothing);

    await _settleAnimations(tester);
  });

  testWidgets('pending card fits the widest action pair on a narrow screen', (
    tester,
  ) async {
    // Pending renders Cancel + Confirm — the widest button pair. The
    // actions Wrap must flow them onto a second line, never overflow.
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Get.reset();
    final controller = _TestDoctorController();
    controller.currentDoctor.value = doctorBasic(placeId: 'place_dash_1');
    controller.appointments.assignAll([
      appointmentBasic(
        appointmentId: 'APT_NARROW_PENDING',
        patientName: 'Narrow Pending Patient',
        appointmentDate: _todayKey(),
        appointmentTime: '10:30 AM',
        status: AppointmentStatus.pending,
        doctorPlaceId: 'place_dash_1',
        consultationType: 'tele',
        patientPhone: '9876543210',
      ),
    ]);
    Get.put<DoctorController>(controller, permanent: true);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.lightTheme,
        home: const DoctorAppointmentsScreen(),
      ),
    );
    await tester.pump();
    await _settleAnimations(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    // The consultation type renders as its own full-width row on cards.
    expect(find.text('Tele Consultation'), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets('online refund: patient UPI VPA → UPI success → marked '
      'Refunded with the refund details', (tester) async {
    // Make the UPI service run the intent on the test host and return a
    // CONFIRMED refund from the fake UPI app.
    QuantupiPaymentService.forceAndroid = true;
    QuantupiPaymentService.transactionOverride = (upi) async =>
        'upi://pay?txnId=RFDREFUND123&responseCode=00&Status=SUCCESS';
    addTearDown(() {
      QuantupiPaymentService.forceAndroid = null;
      QuantupiPaymentService.transactionOverride = null;
    });

    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_REFUND_ONLINE',
          patientName: 'Online Refund Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        // A PAID online payment — the money was collected, now refund it.
        'APT_REFUND_ONLINE': paymentFor(
          appointmentId: 'APT_REFUND_ONLINE',
          amount: 800,
          paymentStatus: 'Paid',
          paymentMethod: 'online',
        ),
      },
    );

    // A Paid payment is refundable: the Refund action is present.
    expect(find.text('Refund'), findsOneWidget);

    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online (UPI)'));
    await tester.pumpAndSettle();

    // The dialog asks for the patient's UPI ID (the value their UPI QR
    // code encodes).
    expect(find.text('Refund via UPI'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'patient@okhdfcbank');
    await tester.pump();
    await tester.tap(find.text('Send Refund'));
    await tester.pumpAndSettle();

    // The refund sends like the booking flow — the Quantupi package
    // fires the intent and Android's system chooser lists the UPI apps.
    // Only a CONFIRMED UPI refund flips the status — with the refund
    // method + transaction details recorded.
    expect(controller.markedPayments, [('APT_REFUND_ONLINE', 'Refunded')]);
    expect(controller.refunds, [('APT_REFUND_ONLINE', 'online')]);
    expect(find.textContaining('Refund of ₹800 sent'), findsOneWidget);

    await _settleAnimations(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('online refund: UPI failure does NOT mark the payment '
      'refunded when the doctor confirms it did not go through',
      (tester) async {
    QuantupiPaymentService.forceAndroid = true;
    QuantupiPaymentService.transactionOverride = (upi) async =>
        'upi://pay?txnId=RFDX&Status=FAILURE';
    addTearDown(() {
      QuantupiPaymentService.forceAndroid = null;
      QuantupiPaymentService.transactionOverride = null;
    });

    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_REFUND_FAIL',
          patientName: 'Fail Refund Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        'APT_REFUND_FAIL': paymentFor(
          appointmentId: 'APT_REFUND_FAIL',
          amount: 500,
          paymentStatus: 'Paid',
          paymentMethod: 'online',
        ),
      },
    );

    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online (UPI)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'patient@okhdfcbank');
    await tester.pump();
    await tester.tap(find.text('Send Refund'));
    await tester.pumpAndSettle();

    // A FAILURE response — the doctor must verify in their UPI app
    // whether the refund actually went through. Saying it did NOT keeps
    // the payment untouched.
    expect(find.text('Refund not confirmed'), findsOneWidget);
    await tester.tap(find.text('It did not go through'));
    await tester.pumpAndSettle();

    expect(controller.markedPayments, isEmpty);
    expect(find.textContaining('NOT marked as refunded'), findsOneWidget);

    await _settleAnimations(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('online refund: UPI returns FAILURE but the doctor confirms '
      'the refund went through → payment marked Refunded', (tester) async {
    // The UPI app answered FAILURE even though the money actually moved
    // (a known UPI intent-flow quirk). The doctor verifies in their UPI
    // app and records the refund manually.
    QuantupiPaymentService.forceAndroid = true;
    QuantupiPaymentService.transactionOverride = (upi) async =>
        'upi://pay?txnId=RFDUNCONF&Status=FAILURE';
    addTearDown(() {
      QuantupiPaymentService.forceAndroid = null;
      QuantupiPaymentService.transactionOverride = null;
    });

    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_REFUND_CONFIRMED',
          patientName: 'Confirmed Refund Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        'APT_REFUND_CONFIRMED': paymentFor(
          appointmentId: 'APT_REFUND_CONFIRMED',
          amount: 650,
          paymentStatus: 'Paid',
          paymentMethod: 'online',
        ),
      },
    );

    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online (UPI)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'patient@okhdfcbank');
    await tester.pump();
    await tester.tap(find.text('Send Refund'));
    await tester.pumpAndSettle();

    // The UPI app did not confirm — the confirmation dialog explains and
    // the doctor says it actually went through.
    expect(find.text('Refund not confirmed'), findsOneWidget);
    await tester.tap(find.text('Yes, mark as Refunded'));
    await tester.pumpAndSettle();

    // The refund is recorded as Refunded with the online method + the
    // transaction id from the (non-success) response.
    expect(controller.markedPayments, [
      ('APT_REFUND_CONFIRMED', 'Refunded'),
    ]);
    expect(controller.refunds, [('APT_REFUND_CONFIRMED', 'online')]);
    expect(
      find.textContaining('Refund of ₹650 recorded'),
      findsOneWidget,
    );

    await _settleAnimations(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('refund flow UI audit: fits a 320×568 phone without overflow',
      (tester) async {
    // Small-phone surface — the same width class that has caught overflow
    // on the doctor-side cards before.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_UI_NARROW',
          patientName: 'Narrow Screen Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        'APT_UI_NARROW': paymentFor(
          appointmentId: 'APT_UI_NARROW',
          amount: 500,
        ),
      },
    );
    // _pumpScreen re-applied the default 800×1600 surface — switch to the
    // narrow phone before opening the flow.
    tester.view.physicalSize = const Size(320, 568);
    await tester.pump();

    // Refund → method picker: both options on screen, no overflow.
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Online (UPI)'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);

    // Cash → confirm dialog: no overflow.
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Refund Payment'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Refund'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Let the success snackbar dismiss before reopening the flow.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Online → VPA dialog (long instructions + input): no overflow, and
    // the Send button only enables with a plausible VPA.
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online (UPI)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Refund via UPI'), findsOneWidget);
    final sendBtn = find.widgetWithText(ElevatedButton, 'Send Refund');
    expect(tester.widget<ElevatedButton>(sendBtn).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'patient@okhdfcbank');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.widget<ElevatedButton>(sendBtn).onPressed, isNotNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await _settleAnimations(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('refund flow UI audit: renders at 1.5× text scale without '
      'overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_UI_SCALE',
          patientName: 'Large Text Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        'APT_UI_SCALE': paymentFor(
          appointmentId: 'APT_UI_SCALE',
          amount: 500,
        ),
      },
    );

    // Method picker at 1.5× — scrolls, never overflows.
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    final e = tester.takeException();
    if (e != null) {
      debugPrint('REFUND UI OVERFLOW >>> $e');
      if (e is FlutterError) {
        for (final d in e.diagnostics) {
          debugPrint('  REFUND UI OVERFLOW diag: $d');
        }
      }
      throw e;
    }
    await tester.tap(find.text('Online (UPI)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Refund via UPI'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'patient@okhdfcbank');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await _settleAnimations(tester);
  });

  testWidgets("refund VPA dialog offers scanning the patient's UPI QR "
      'code', (tester) async {
    await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_SCAN_BTN',
          patientName: 'Scan Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        'APT_SCAN_BTN': paymentFor(
          appointmentId: 'APT_SCAN_BTN',
          amount: 400,
          paymentStatus: 'Paid',
        ),
      },
    );

    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online (UPI)'));
    await tester.pumpAndSettle();

    // The dialog's QR option — on a real device this opens the camera
    // scanner and fills the field with the scanned VPA.
    expect(find.text('Refund via UPI'), findsOneWidget);
    expect(find.text("Scan Patient's UPI QR Code"), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await _settleAnimations(tester);
  });

  testWidgets('online refund: sends via the system chooser like the '
      'booking flow (no in-app provider picker)', (tester) async {
    QuantupiPaymentService.forceAndroid = true;
    QuantupiPaymentService.transactionOverride = (upi) async =>
        'upi://pay?txnId=RFD_CHOOSER&responseCode=00&Status=SUCCESS';
    addTearDown(() {
      QuantupiPaymentService.forceAndroid = null;
      QuantupiPaymentService.transactionOverride = null;
    });

    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_REFUND_CHOOSER',
          patientName: 'Chooser Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        'APT_REFUND_CHOOSER': paymentFor(
          appointmentId: 'APT_REFUND_CHOOSER',
          amount: 600,
          paymentStatus: 'Paid',
        ),
      },
    );

    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online (UPI)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'patient@okhdfcbank');
    await tester.pump();

    // No extra provider step — Send Refund fires the UPI intent
    // straight away (Android's system chooser lists all UPI apps).
    await tester.tap(find.text('Send Refund'));
    await tester.pumpAndSettle();
    expect(find.text('System default chooser'), findsNothing);

    expect(controller.markedPayments, [('APT_REFUND_CHOOSER', 'Refunded')]);
    expect(find.textContaining('Refund of ₹600 sent'), findsOneWidget);

    await _settleAnimations(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('online refund: a sent-but-unrecorded refund NEVER re-sends '
      '— tapping Refund again retries the record only', (tester) async {
    // Count every UPI intent the flow fires — the double-refund guard must
    // keep this at exactly 1 across BOTH Refund taps.
    var payCalls = 0;
    QuantupiPaymentService.forceAndroid = true;
    QuantupiPaymentService.transactionOverride = (upi) async {
      payCalls++;
      return 'upi://pay?txnId=RFD_UNREC&responseCode=00&Status=SUCCESS';
    };
    addTearDown(() {
      QuantupiPaymentService.forceAndroid = null;
      QuantupiPaymentService.transactionOverride = null;
    });

    final controller = await _pumpScreen(
      tester,
      [
        appointmentBasic(
          appointmentId: 'APT_REFUND_UNREC',
          patientName: 'Unrecorded Patient',
          appointmentDate: _todayKey(),
          appointmentTime: '10:00 AM',
          status: AppointmentStatus.upcoming,
          doctorPlaceId: 'place_dash_1',
        ),
      ],
      payments: {
        'APT_REFUND_UNREC': paymentFor(
          appointmentId: 'APT_REFUND_UNREC',
          amount: 800,
          paymentStatus: 'Paid',
          paymentMethod: 'online',
        ),
      },
    );

    // The record write keeps failing — the UPI app already CONFIRMED the
    // refund, so the money left the clinic.
    controller.markPaymentResult = false;

    // ── First attempt: refund sent, record write fails after 3 retries. ──
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online (UPI)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'patient@okhdfcbank');
    await tester.pump();
    await tester.tap(find.text('Send Refund'));
    // The VPA dialog pops, then the 3 record attempts run with 600ms
    // retry pauses in between — advance the fake clock past them.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(payCalls, 1, reason: 'exactly one UPI refund was sent');
    expect(controller.refunds.length, 3,
        reason: 'the record write retried 3 times');
    // The doctor is told the money went out and NOT to send it again.
    expect(find.textContaining('do NOT send it again'), findsOneWidget);
    expect(find.textContaining('Tap Refund again to retry recording'),
        findsOneWidget);

    // Let the warning snackbar expire before tapping the card again.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // ── Second Refund tap: must NOT fire a new UPI payment — it retries
    //    recording the already-sent refund (now the write succeeds). ──
    controller.markPaymentResult = true;
    await tester.tap(find.text('Refund'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // No method picker (the guard intercepts before it), no second UPI
    // intent — the record update alone ran and landed.
    expect(find.text('Online (UPI)'), findsNothing);
    expect(payCalls, 1,
        reason: 're-tapping Refund must NEVER send a second refund');
    expect(controller.refunds.length, 4,
        reason: 'one more record attempt, no new payment');
    expect(find.textContaining('payment marked as Refunded'), findsOneWidget);

    await _settleAnimations(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
