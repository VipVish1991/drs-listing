import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
    // Keyed by the message so the entrance animation REPLAYS whenever the
    // wording changes in place (e.g. an active booking being completed
    // flips the notice to the 12h-cooldown text) — the notice always
    // animates in for the patient, matching the app's animated-notice
    // language on the history screen.
    return KeyedSubtree(
      key: ValueKey(message),
      child: Container(
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
      )
          // The "You already have an appointment…" / 12h-cooldown gate
          // notice drops in with the same fade + slide family as the rest
          // of the screen — a soft slide-down from above that reads as a
          // notice arriving, never a jarring pop.
          .animate()
          .fadeIn(duration: 400.ms, curve: Curves.easeOut)
          .slideY(begin: -0.25, end: 0, duration: 400.ms, curve: Curves.easeOut),
    );
  }
}
