import '../models/appointment_model.dart';
import 'csv_utils.dart';

/// Builds a CSV export of the doctor-side patient history timeline — one
/// row per visit, in the order given (the screen passes its newest-first
/// timeline). Pure and testable: no I/O, no platform channels.
///
/// Header: `Date,Time,Status,Consultation,Symptoms,Prescriptions,
/// Appointment ID`. Dates use the app-wide dd-MM-yyyy display format and
/// the consultation column is empty for legacy rows without a stored type.
String buildPatientHistoryCsv(List<AppointmentModel> visits) {
  final rows = <List<String>>[
    [
      'Date',
      'Time',
      'Status',
      'Consultation',
      'Symptoms',
      'Prescriptions',
      'Appointment ID',
    ],
  ];
  for (final a in visits) {
    rows.add([
      a.displayDate ?? a.appointmentDate ?? '',
      a.appointmentTime ?? '',
      a.status,
      a.consultationTypeLabel ?? '',
      a.symptoms ?? '',
      '${a.prescriptionUrls.length}',
      a.appointmentId,
    ]);
  }
  return rows.map(csvRow).join('\r\n');
}
