import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/doctor_controller.dart';
import '../models/appointment_model.dart';

/// Shows the "Confirm Appointment" dialog for a Pending booking created
/// via the QR / browser booking page.
///
/// "Confirm" accepts the booking by moving it to [AppointmentStatus.upcoming]
/// via [DoctorController.updateAppointmentStatus]; "Not Now" dismisses it.
void showConfirmAppointmentDialog(
  DoctorController controller,
  AppointmentModel appointment,
) {
  Get.dialog(
    AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Confirm Appointment'),
      content: Text(
        'Accept the booking from ${appointment.patientName ?? 'patient'}?\n\n'
        'It will be confirmed and moved to Upcoming.',
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: Text(
            'Not Now',
            style: TextStyle(color: AppColors.textCaption),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            controller.updateAppointmentStatus(
              appointment.appointmentId,
              AppointmentStatus.upcoming,
            );
            Get.back();
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}
