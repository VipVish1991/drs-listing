import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/doctor_model.dart';
import '../services/launch_service.dart';

/// A row of quick-action buttons (Call / Directions / Website) for the
/// doctor detail screen.
///
/// Shows a maximum of three equally-spaced buttons.  When the doctor has a
/// website URL all three are rendered; otherwise only Call and Directions
/// are shown.
class QuickActionsRow extends StatelessWidget {
  final DoctorModel doctor;

  const QuickActionsRow({super.key, required this.doctor});

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      Expanded(
        child: QuickActionButton(
          icon: Icons.phone,
          label: 'Call',
          color: AppColors.success,
          onTap: () => LaunchService.phone(doctor.phoneNumber),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: QuickActionButton(
          icon: Icons.directions,
          label: 'Directions',
          color: AppColors.info,
          onTap: () => LaunchService.map(doctor.latitude, doctor.longitude),
        ),
      ),
    ];
    if ((doctor.website ?? '').isNotEmpty) {
      actions.add(const SizedBox(width: 8));
      actions.add(
        Expanded(
          child: QuickActionButton(
            icon: Icons.language,
            label: 'Website',
            color: AppColors.accent,
            onTap: () => LaunchService.url(doctor.website),
          ),
        ),
      );
    }
    return Row(children: actions);
  }
}

/// A single quick-action button with an icon, label, and tinted background.
class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: Column(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


