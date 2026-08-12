import '../models/payment_model.dart';
import 'csv_utils.dart';

/// Builds a CSV export of [payments] for the payment history screen —
/// one row per payment, honoring the app's display conventions. Pure and
/// testable: no I/O, no platform channels.
///
/// [nameFor] resolves the "counterparty" column — the doctor's name on the
/// patient side, the patient's name on the doctor (clinic) side.
///
/// [nameColumn] is the header for that column and follows the same
/// counterparty role: `'Doctor Name'` in the patient's export (who was
/// paid), `'Patient Name'` in the doctor/clinic export (who paid).
///
/// Header: `Date,{nameColumn},Consultation,Method,Status,Amount (INR),
/// Transaction ID,UPI ID,Appointment ID`. Amounts are plain numbers
/// (`800` / `800.50`) so spreadsheets treat them as numeric.
String buildPaymentsCsv(
  List<PaymentModel> payments, {
  required String Function(PaymentModel) nameFor,
  required String nameColumn,
}) {
  final rows = <List<String>>[
    [
      'Date',
      nameColumn,
      'Consultation',
      'Method',
      'Status',
      'Amount (INR)',
      'Transaction ID',
      'UPI ID',
      'Appointment ID',
    ],
  ];
  for (final p in payments) {
    final paidOn = p.paidAt ?? p.createdAt;
    rows.add([
      paidOn != null ? csvDateLabel(paidOn) : '',
      nameFor(p),
      p.consultationTypeLabel ?? '',
      p.paymentMethodLabel,
      p.paymentStatus,
      PaymentModel.formatAmount(p.amount),
      p.transactionId ?? '',
      p.upiId ?? '',
      p.appointmentId,
    ]);
  }
  return rows.map(csvRow).join('\r\n');
}
