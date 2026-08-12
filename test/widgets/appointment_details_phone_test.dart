import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/models/payment_model.dart';
import 'package:DrsListing/widgets/appointment_details_sheet.dart';

/// Pumps a host screen with a button that opens the details sheet for
/// [appointment], passing [phoneNumber] and [payment] through (as the
/// doctor's screen does with the patient's number + payment row).
Future<void> _openSheet(
  WidgetTester tester,
  AppointmentModel appointment, {
  String? phoneNumber,
  PaymentModel? payment,
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
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
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
