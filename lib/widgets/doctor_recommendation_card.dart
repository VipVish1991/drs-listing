import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../config/theme.dart';
import '../models/doctor_model.dart';
import '../services/launch_service.dart';
import 'app_button.dart';
import 'doctor_avatar.dart';

/// A compact doctor card designed to be shown inline inside AI chat bubbles.
///
/// Displays:
///   – Doctor photo (initial fallback) with open/closed indicator
///   – Name, specialization
///   – Rating stars + review count
///   – Distance and availability badge
///   – Phone + Map action buttons
///   – "Book Appointment" primary action button
class DoctorRecommendationCard extends StatelessWidget {
  final DoctorModel doctor;
  final VoidCallback onBook;
  final VoidCallback? onViewProfile;

  const DoctorRecommendationCard({
    super.key,
    required this.doctor,
    required this.onBook,
    this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? Colors.white70 : AppColors.textBody;
    final bool isOpen = doctor.isOpen == true;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(10) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withAlpha(15)
              : AppColors.primary.withAlpha(40),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onViewProfile ?? onBook,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row: avatar + info ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar with open/closed dot
                    Stack(
                      children: [
                        DoctorAvatar.roundedRect(
                          doctor: doctor,
                          size: 52,
                          borderRadius: 14,
                          showStatusDot: true,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isOpen ? Colors.green : Colors.grey,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withAlpha(10)
                                    : Colors.white,
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doctor.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if ((doctor.specialization ?? '').isNotEmpty)
                            Text(
                              doctor.specialization!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary.withAlpha(220),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          const SizedBox(height: 4),
                          // Rating row
                          Row(
                            children: [
                              ...List.generate(5, (i) => Icon(
                                i < (doctor.rating ?? 0).floor()
                                    ? Icons.star
                                    : Icons.star_border,
                                size: 12,
                                color: AppColors.accent,
                              )),
                              const SizedBox(width: 4),
                              Text(
                                doctor.rating != null
                                    ? doctor.rating!.toStringAsFixed(1)
                                    : '—',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: bodyColor,
                                ),
                              ),
                              if (doctor.userRatingsTotal != null) ...[
                                const SizedBox(width: 2),
                                Text(
                                  '(${doctor.userRatingsTotal})',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: bodyColor.withAlpha(160),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── Info chips row ──
                Row(
                  children: [
                    if ((doctor.distance ?? '').isNotEmpty)
                      _InfoBadge(
                        icon: Icons.near_me,
                        label: doctor.distance!,
                        color: AppColors.info,
                      ),
                    const SizedBox(width: 6),
                    _InfoBadge(
                      icon: isOpen ? Icons.check_circle : Icons.access_time,
                      label: isOpen ? 'Open Now' : 'Check Hours',
                      color: isOpen ? Colors.green : AppColors.textCaption,
                    ),
                    const Spacer(),
                    if (doctor.priceLevel != null)
                      _InfoBadge(
                        icon: Icons.currency_rupee,
                        label: '₩' * (doctor.priceLevel! + 1),
                        color: AppColors.textCaption,
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── Action buttons row ──
                Row(
                  children: [
                    // Book Appointment
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: onBook,
                          icon: const Icon(Icons.event_available, size: 16),
                          label: const Text('Book', style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if ((doctor.phoneNumber ?? '').isNotEmpty) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: AppIconActionButton(
                          icon: Icons.phone,
                          color: AppColors.success,
                          iconSize: 16,
                          onPressed: () =>
                              LaunchService.phone(doctor.phoneNumber),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: AppIconActionButton(
                        icon: Icons.map_outlined,
                        color: AppColors.info,
                        iconSize: 16,
                        onPressed: () =>
                            LaunchService.map(doctor.latitude, doctor.longitude),
                      ),
                    ),
                  ],
                ),

                // ── Address at bottom if available ──
                if ((doctor.address ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: AppColors.textCaption),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          doctor.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: bodyColor.withAlpha(180),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(
          duration: 400.ms,
          delay: 200.ms,
        ).slideY(
          begin: 0.2,
          end: 0,
          duration: 400.ms,
          curve: Curves.easeOut,
        );
  }

}

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
