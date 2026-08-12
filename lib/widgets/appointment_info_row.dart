import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Full-width info row (icon box + label + value) used by appointment
/// cards on both the doctor and patient sides for Date, Time, Consultation
/// type and phone rows. Each datum gets its own row spanning the card, so
/// nothing is ever squeezed or truncated — the same pattern as the
/// patient-history timeline cards.
class AppointmentInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  /// When set, the row renders as a tappable tinted call row (e.g. the
  /// doctor card's Patient phone). Nested inside a card's InkWell, the
  /// inner InkWell wins the tap so the action fires instead of opening
  /// the card's details.
  final VoidCallback? onTap;

  const AppointmentInfoRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withAlpha(18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textCaption.withAlpha(180),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHeading,
                ),
              ),
            ],
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 12,
            color: iconColor,
          ),
        ],
      ],
    );

    if (onTap == null) return row;

    return Material(
      color: iconColor.withAlpha(10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: row,
        ),
      ),
    );
  }
}
