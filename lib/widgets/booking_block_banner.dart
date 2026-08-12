import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Amber notice explaining the "one patient, one doctor at a time" rule —
/// shown while the patient can't book right now (an active Pending/Upcoming
/// booking, or within the 12h cooldown from their most recent booking).
///
/// Shared by the booking screen (where it appears above the form while the
/// Book action is blocked) and the appointment history screen (where it
/// explains the block the patient would hit if they tried to book).
class BookingBlockBanner extends StatelessWidget {
  /// The gate message — the output of
  /// `AppointmentController.bookingBlockMessage`.
  final String message;

  const BookingBlockBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.schedule_rounded,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textBody,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
