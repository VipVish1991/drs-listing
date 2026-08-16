import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/services/meet_consult_service_io.dart';
import 'package:DrsListing/widgets/appointment_details_sheet.dart';

/// Records url_launcher calls so the Join button's external open can be
/// asserted.
class _SheetFakeUrlLauncher extends UrlLauncherPlatform {
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

/// Fake of the Google API surface so the Join button can run the full
/// sign-in → event → link flow without platform channels.
class _SheetFakeMeetGateway implements MeetFlowGateway {
  Map<String, String>? createEventResult = const {
    'id': 'evt_1',
    'link': 'https://meet.google.com/created-room-1',
  };

  @override
  Future<bool> signIn(BuildContext context) async => true;

  @override
  Future<Map<String, String>?> createEvent({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    return createEventResult;
  }
}

/// Pumps a host screen with a button that opens the details sheet for
/// [appointment], passing [phoneNumber] and [payment] through (as the
/// doctor's screen does with the patient's number + payment row).
Future<void> _openSheet(
  WidgetTester tester,
  AppointmentModel appointment, {
  String? phoneNumber,
  PaymentModel? payment,
  Future<bool> Function(String link)? onSaveMeetLink,
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => AppointmentDetailsSheet.show(
                appointment: appointment,
                displayStatus: 'Upcoming',
                headerName: appointment.patientName ?? 'Patient',
                phoneNumber: phoneNumber,
                payment: payment,
                onSaveMeetLink: onSaveMeetLink,
              ),
              child: const Text('open sheet'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open sheet'));
  await tester.pumpAndSettle();
}

void main() {
  group('Doctor appointment details sheet — patient phone', () {
    testWidgets('shows the patient phone and Call Now when present', (
      tester,
    ) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_PHONE_1',
        patientName: 'Rahul Sharma',
        patientPhone: '9876543210',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(
        tester,
        appointment,
        phoneNumber: appointment.patientPhone,
      );

      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Call Now'), findsOneWidget);
    });

    testWidgets('phone row is tappable (InkWell opens the dialer)', (
      tester,
    ) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_PHONE_2',
        patientName: 'Rahul Sharma',
        patientPhone: '9876543210',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(
        tester,
        appointment,
        phoneNumber: appointment.patientPhone,
      );

      // The phone value sits inside a tappable row (InkWell) — the Call
      // Now button also invokes the dialer.
      final row = find.ancestor(
        of: find.text('9876543210'),
        matching: find.byType(InkWell),
      );
      expect(row, findsWidgets);
      expect(find.text('Call Now'), findsOneWidget);
    });

    testWidgets('hides the phone row when the patient has no number', (
      tester,
    ) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_PHONE_3',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      // No phoneNumber override → falls back to callNumber (also null).
      await _openSheet(tester, appointment);

      expect(find.text('Call Now'), findsNothing);
      expect(find.text('Phone'), findsNothing);
    });

    testWidgets(
      'doctor side never falls back to call_number (legacy rows show no phone)',
      (tester) async {
        // Legacy in-app bookings store the DOCTOR's number in call_number;
        // the doctor screen passes patientPhone ?? '' so that number must
        // never leak into the modal.
        final appointment = AppointmentModel(
          appointmentId: 'APT_PHONE_4',
          patientName: 'Rahul Sharma',
          callNumber: '+911111111111', // doctor's own number
          appointmentDate: '2026-08-03',
          appointmentTime: '10:00 AM',
        );

        await _openSheet(tester, appointment, phoneNumber: '');

        expect(find.text('Call Now'), findsNothing);
        expect(find.text('Phone'), findsNothing);
        expect(find.text('+911111111111'), findsNothing);
      },
    );

    testWidgets('patient side still falls back to call_number', (tester) async {
      // The patient history screen does NOT pass phoneNumber, so the sheet
      // falls back to call_number (the doctor's number) — calling the doctor.
      final appointment = AppointmentModel(
        appointmentId: 'APT_PHONE_5',
        patientName: 'Rahul Sharma',
        callNumber: '+912222222222',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(tester, appointment);

      expect(find.text('+912222222222'), findsOneWidget);
      expect(find.text('Call Now'), findsOneWidget);
    });
  });

  group('appointment details sheet — consultation type chip', () {
    testWidgets('shows a consultation-type chip in the header when the type '
        'is stored', (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_CT_CHIP_1',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'video',
      );

      await _openSheet(tester, appointment);

      // The header chip surfaces the type (the sheet's old detail row was
      // dropped — the chip covers it), so the value renders once.
      expect(
        find.byKey(const ValueKey('details_sheet_consultation_chip')),
        findsOneWidget,
      );
      expect(find.text('Video Consultation'), findsOneWidget);
      // The chip's icon (the Join Video Call button below adds its own).
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('details_sheet_consultation_chip'),
          ),
          matching: find.byIcon(Icons.videocam_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('video consultation shows the Join Video Call button',
        (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_VC_BTN_1',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'video',
      );

      await _openSheet(tester, appointment);

      // Remote consultations start the Meet consultation (Google sign-in →
      // calendar event → link opens externally).
      expect(
        find.byKey(const ValueKey('join_video_call')),
        findsOneWidget,
      );
      expect(find.text('Join Video Call'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_rounded), findsWidgets);
    });

    testWidgets('tele (audio) consultation shows the Join Video Call button',
        (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_VC_BTN_2',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'tele',
      );

      await _openSheet(tester, appointment);

      expect(
        find.byKey(const ValueKey('join_video_call')),
        findsOneWidget,
      );
    });

    testWidgets('in-clinic visits hide the Join Video Call button', (
      tester,
    ) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_VC_BTN_3',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'clinic',
      );

      await _openSheet(tester, appointment);

      expect(
        find.byKey(const ValueKey('join_video_call')),
        findsNothing,
      );
      expect(find.text('Join Video Call'), findsNothing);
    });

    testWidgets('legacy rows without a type hide the Join Video Call button',
        (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_VC_BTN_4',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(tester, appointment);

      expect(
        find.byKey(const ValueKey('join_video_call')),
        findsNothing,
      );
    });

    testWidgets('a stored Meet link surfaces the shared room under the button',
        (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_VC_LINK_1',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'video',
        // The OTHER side already started the meeting — this side must see
        // and join the same room.
        meetLink: 'https://meet.google.com/abc-def-ghi',
      );

      await _openSheet(tester, appointment);

      expect(
        find.byKey(const ValueKey('join_video_call')),
        findsOneWidget,
      );
      // The shared room is surfaced so both sides see they're joining the
      // same meeting.
      expect(find.text('https://meet.google.com/abc-def-ghi'), findsOneWidget);
    });

    testWidgets('no stored link means no shared-room row', (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_VC_LINK_2',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'video',
      );

      await _openSheet(tester, appointment);

      expect(
        find.byKey(const ValueKey('join_video_call')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.link_rounded), findsNothing);
    });

    testWidgets('tapping Join on a fresh appointment creates the meeting, '
        'opens the link and saves it (both sides join the same room)',
        (tester) async {
      // Fake the Google APIs (the VM test resolves the io implementation)
      // and the url launcher so the whole button flow runs end-to-end.
      final savedLinks = <String>[];
      final urlLauncher = _SheetFakeUrlLauncher();
      UrlLauncherPlatform.instance = urlLauncher;
      meetFlowGateway = _SheetFakeMeetGateway();
      addTearDown(() => meetFlowGateway = SdkMeetFlowGateway());

      final appointment = AppointmentModel(
        appointmentId: 'APT_VC_CREATE_1',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'video',
      );

      await _openSheet(
        tester,
        appointment,
        onSaveMeetLink: (link) async {
          savedLinks.add(link);
          return true;
        },
      );

      await tester.tap(find.byKey(const ValueKey('join_video_call')));
      await tester.pumpAndSettle();

      // The flow ran: the newly created room opened externally AND was
      // persisted via the onSaveMeetLink callback (wired to the
      // controller's saveMeetLink on both screens), so the other side
      // joins the same room.
      expect(urlLauncher.launchCalls, ['https://meet.google.com/created-room-1']);
      expect(savedLinks, ['https://meet.google.com/created-room-1']);
    });

    testWidgets('tapping Join when a link is already stored reuses the '
        'saved room (no new event, no re-save needed)', (tester) async {
      final savedLinks = <String>[];
      final urlLauncher = _SheetFakeUrlLauncher();
      UrlLauncherPlatform.instance = urlLauncher;
      meetFlowGateway = _SheetFakeMeetGateway();
      addTearDown(() => meetFlowGateway = SdkMeetFlowGateway());

      final appointment = AppointmentModel(
        appointmentId: 'APT_VC_REUSE_1',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'tele',
        meetLink: 'https://meet.google.com/abc-def-ghi',
      );

      await _openSheet(
        tester,
        appointment,
        onSaveMeetLink: (link) async {
          savedLinks.add(link);
          return true;
        },
      );

      await tester.tap(find.byKey(const ValueKey('join_video_call')));
      await tester.pumpAndSettle();

      // The stored room opened directly (no Google sign-in — the fake
      // gateway's createEvent would return a different link otherwise).
      expect(urlLauncher.launchCalls, ['https://meet.google.com/abc-def-ghi']);
      expect(savedLinks, ['https://meet.google.com/abc-def-ghi']);
    });

    testWidgets('in-clinic type chip uses the storefront icon', (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_CT_CHIP_2',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'clinic',
      );

      await _openSheet(tester, appointment);

      expect(
        find.byKey(const ValueKey('details_sheet_consultation_chip')),
        findsOneWidget,
      );
      expect(find.text('In-Clinic Visit'), findsOneWidget);
      // Only the header chip uses the storefront icon.
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    });

    testWidgets('no chip for legacy rows without a stored type', (
      tester,
    ) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_CT_CHIP_3',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(tester, appointment);

      expect(
        find.byKey(const ValueKey('details_sheet_consultation_chip')),
        findsNothing,
      );
      expect(find.text('Video Consultation'), findsNothing);
    });
  });

  group('appointment details sheet — fee chip in header', () {
    testWidgets('shows the fee chip next to the consultation chip when a '
        'payment exists', (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_FEE_CHIP_1',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'video',
      );

      await _openSheet(
        tester,
        appointment,
        payment: PaymentModel(
          appointmentId: 'APT_FEE_CHIP_1',
          patientId: 'user_1',
          amount: 800,
          paymentStatus: 'Paid',
          paymentMethod: 'online',
        ),
      );

      // Both chips sit side by side in the header.
      expect(
        find.byKey(const ValueKey('details_sheet_consultation_chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('details_sheet_fee_chip')),
        findsOneWidget,
      );
      // The chip shows the bare amount with a rupee icon (the payment card
      // below keeps the '₹800' label — the chip's icon IS the currency).
      expect(find.byIcon(Icons.currency_rupee_rounded), findsWidgets);
      expect(find.text('800'), findsOneWidget);
      expect(find.text('₹800'), findsOneWidget);
    });

    testWidgets('fee chip renders alone when there is no consultation type', (
      tester,
    ) async {
      // Legacy rows may carry a payment without a stored consultation type
      // — the fee chip still surfaces the amount.
      final appointment = AppointmentModel(
        appointmentId: 'APT_FEE_CHIP_2',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(
        tester,
        appointment,
        payment: PaymentModel(
          appointmentId: 'APT_FEE_CHIP_2',
          patientId: 'user_1',
          amount: 1000,
          paymentStatus: 'Pending',
          paymentMethod: 'offline',
        ),
      );

      expect(
        find.byKey(const ValueKey('details_sheet_consultation_chip')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('details_sheet_fee_chip')),
        findsOneWidget,
      );
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('no fee chip when no payment row exists', (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_FEE_CHIP_3',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
        consultationType: 'clinic',
      );

      await _openSheet(tester, appointment);

      expect(
        find.byKey(const ValueKey('details_sheet_fee_chip')),
        findsNothing,
      );
      // The consultation chip stays on its own.
      expect(
        find.byKey(const ValueKey('details_sheet_consultation_chip')),
        findsOneWidget,
      );
    });
  });

  group('appointment details sheet — fee/payment card', () {
    testWidgets('shows amount, status, method and paid date when a payment '
        'exists', (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_PAY_1',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(
        tester,
        appointment,
        payment: PaymentModel(
          appointmentId: 'APT_PAY_1',
          patientId: 'user_1',
          amount: 800,
          paymentStatus: 'Paid',
          paymentMethod: 'online',
          transactionId: 'UPI-TXN-123',
          // A date DIFFERENT from the appointment date, so the "Paid on"
          // row is unambiguous against the Date row.
          paidAt: DateTime(2026, 7, 20),
        ),
      );

      expect(find.text('₹800'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Online (UPI)'), findsOneWidget);
      expect(find.text('Paid on'), findsOneWidget);
      expect(find.text('20-07-2026'), findsOneWidget);
      // Online payments carry the UPI transaction id.
      expect(find.text('Transaction'), findsOneWidget);
      expect(find.text('UPI-TXN-123'), findsOneWidget);
    });

    testWidgets('offline Pending payment shows method but no transaction', (
      tester,
    ) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_PAY_2',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(
        tester,
        appointment,
        payment: PaymentModel(
          appointmentId: 'APT_PAY_2',
          patientId: 'user_1',
          amount: 1000,
          paymentStatus: 'Pending',
          paymentMethod: 'offline',
        ),
      );

      expect(find.text('₹1000'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Offline (Clinic)'), findsOneWidget);
      // No paid date and no transaction id for an unpaid offline row.
      expect(find.text('Paid on'), findsNothing);
      expect(find.text('Transaction'), findsNothing);
    });

    testWidgets('Refunded payment renders its own status chip', (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_PAY_3',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(
        tester,
        appointment,
        payment: PaymentModel(
          appointmentId: 'APT_PAY_3',
          patientId: 'user_1',
          amount: 500,
          paymentStatus: 'Refunded',
          paymentMethod: 'offline',
        ),
      );

      expect(find.text('₹500'), findsOneWidget);
      expect(find.text('Refunded'), findsOneWidget);
      expect(find.text('Offline (Clinic)'), findsOneWidget);
    });

    testWidgets('no payment card when no payment row exists', (tester) async {
      final appointment = AppointmentModel(
        appointmentId: 'APT_PAY_NONE',
        patientName: 'Rahul Sharma',
        appointmentDate: '2026-08-03',
        appointmentTime: '10:00 AM',
      );

      await _openSheet(tester, appointment);

      expect(find.text('Payment'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });
  });

}
