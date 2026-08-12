import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/doctor_model.dart';
import '../utils/extensions.dart';
import 'app_button.dart';
import 'doctor_avatar.dart';

/// A compact yet rich doctor card designed for the search-result list.
///
/// Shows:
///   – Name, specialization, rating + review count
///   – Address, distance, open/closed status
///   – Contact info (phone, website) when available
///   – Key stats (reviews, distance, experience)
///   – Book & Map action buttons
class DoctorCard extends StatelessWidget {
  final DoctorModel doctor;
  final VoidCallback onTap;
  final VoidCallback onMap;
  final bool isFavorited;
  final ValueChanged<bool>? onToggleFavorite;

  const DoctorCard({
    super.key,
    required this.doctor,
    required this.onTap,
    required this.onMap,
    this.isFavorited = false,
    this.onToggleFavorite,
  });

  // ── Helpers ────────────────────────────────────────────────────────

  String? get _todaysHours {
    if (doctor.openingHours.isEmpty) return null;
    const weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final today = weekdayNames[DateTime.now().weekday - 1];
    return doctor.openingHours.firstWhere(
      (line) => line.startsWith(today),
      orElse: () => doctor.openingHours.first,
    );
  }

  Map<String, dynamic>? get _featuredReview {
    if (doctor.reviews.isEmpty) return null;
    final withText = doctor.reviews
        .where((r) => (r['text']?.toString() ?? '').trim().isNotEmpty)
        .toList();
    if (withText.isEmpty) return null;
    withText.sort(
      (a, b) =>
          ((b['rating'] as num?) ?? 0).compareTo((a['rating'] as num?) ?? 0),
    );
    return withText.first;
  }

  String get _statusLabel {
    if (doctor.isOpen == true) return 'Open Now';
    if (doctor.isOpen == false) return 'Closed';
    if (doctor.businessStatus?.toLowerCase() == 'closed_temporarily') {
      return 'Temp. Closed';
    }
    return '—';
  }

  Color get _statusColor {
    if (doctor.isOpen == true) return Colors.green;
    if (doctor.businessStatus?.toLowerCase() == 'closed_temporarily') {
      return AppColors.warning;
    }
    return AppColors.textCaption;
  }

  String get _priceIndicator {
    if (doctor.priceLevel == null) return '';
    return '₩' * (doctor.priceLevel! + 1);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;
    final review = _featuredReview;
    final hoursLine = _todaysHours;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 0 : 10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row: avatar + name/info + bookmark ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DoctorAvatar.circle(
                    doctor: doctor,
                    size: 68,
                    showStatusDot: true,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        Text(
                          doctor.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Specialization badge
                        if ((doctor.specialization ?? '').isNotEmpty) ...[
                          Text(
                            doctor.specialization!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.primary.withAlpha(220),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        // Stars + rating count
                        Row(
                          children: [
                            ..._buildStars(doctor.rating ?? 0),
                            const SizedBox(width: 6),
                            Text(
                              doctor.rating != null
                                  ? doctor.rating!.ratingString
                                  : '—',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: bodyColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (doctor.userRatingsTotal != null)
                              Text(
                                '(${doctor.userRatingsTotal})',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: bodyColor.withAlpha(180),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Bookmark button
                  if (onToggleFavorite != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onToggleFavorite!(!isFavorited),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isFavorited
                                  ? AppColors.healthHeart.withAlpha(25)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isFavorited
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 20,
                              color: isFavorited
                                  ? AppColors.healthHeart
                                  : AppColors.textCaption,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Stat row ──
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.bgSecondarySurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _StatBlock(
                      value: '${doctor.userRatingsTotal ?? 0}',
                      label: 'Reviews',
                    ),
                    Container(
                      width: 1,
                      height: 28,
                      color: AppColors.textCaption.withAlpha(60),
                    ),
                    _StatBlock(value: (doctor.distance ?? '—'), label: 'Away'),
                    Container(
                      width: 1,
                      height: 28,
                      color: AppColors.textCaption.withAlpha(60),
                    ),
                    _StatBlock(
                      value: _statusLabel,
                      label: 'Status',
                      valueColor: _statusColor,
                    ),
                    if (_priceIndicator.isNotEmpty) ...[
                      Container(
                        width: 1,
                        height: 28,
                        color: AppColors.textCaption.withAlpha(60),
                      ),
                      _StatBlock(
                        value: _priceIndicator,
                        label: 'Price',
                        valueColor: AppColors.textCaption,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ── Detail rows ──
              if ((doctor.address ?? '').isNotEmpty)
                _DetailRow(
                  icon: Icons.location_on_outlined,
                  text: doctor.address!,
                  color: bodyColor,
                  maxLines: 2,
                ),
              if ((doctor.website ?? '').isNotEmpty)
                _DetailRow(
                  icon: Icons.language_outlined,
                  text: doctor.website!.replaceFirst('https://', ''),
                  color: AppColors.primary,
                ),
              if (hoursLine != null)
                _DetailRow(
                  icon: Icons.access_time,
                  text: hoursLine,
                  color: AppColors.textCaption,
                ),

              // ── Review snippet ──
              if (review != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.format_quote,
                            size: 14,
                            color: AppColors.primary.withAlpha(180),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              (review['author_name'] ?? 'Patient').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                          ),
                          if (review['rating'] != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  size: 12,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${review['rating']}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        review['text'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: bodyColor),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // ── Action buttons ──
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.event_available, size: 18),
                      label: const Text('Book'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppIconActionButton(
                    icon: Icons.map_outlined,
                    color: AppColors.primary,
                    onPressed: onMap,
                    tooltip: 'Get Directions',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStars(double rating) {
    final full = rating.floor();
    return List.generate(5, (i) {
      return Icon(
        i < full ? Icons.star : Icons.star_border,
        size: 14,
        color: AppColors.accent,
      );
    });
  }
}

// ── Sub‑widgets ──────────────────────────────────────────────────────

class _StatBlock extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const _StatBlock({required this.value, required this.label, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor ?? textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textCaption),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final int maxLines;

  const _DetailRow({
    required this.icon,
    required this.text,
    required this.color,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textCaption),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
