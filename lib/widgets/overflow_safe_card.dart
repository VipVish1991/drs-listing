import 'package:flutter/material.dart';
import '../config/theme.dart';

/// A reusable card widget that prevents RenderFlex overflow by:
/// 1. Using [MainAxisSize.min] on the Column so it only takes needed space
/// 2. Wrapping the value text in [FittedBox] so large numbers scale down
/// 3. Providing consistent padding, decoration, and shadow across the app
///
/// Use this for stat cards, info cards, mini stat cards, or any card
/// that displays icon + value + label in a vertical layout.
class OverflowSafeCard extends StatelessWidget {
  /// The icon displayed at the top of the card.
  final IconData icon;

  /// The primary value text (e.g., "123", "$45.00").
  final String value;

  /// The label text below the value (e.g., "Patients", "Revenue").
  final String label;

  /// The accent color for the icon and value text.
  final Color color;

  /// The background color for the icon container.
  /// Defaults to [color] with low opacity if not provided.
  final Color? bgColor;

  /// Padding around the card content.
  final EdgeInsetsGeometry? padding;

  /// Border radius of the card.
  final double borderRadius;

  /// Size of the icon inside its container.
  final double iconSize;

  /// Size of the icon container.
  final double iconContainerSize;

  /// Font size of the value text.
  final double valueFontSize;

  /// Font size of the label text.
  final double labelFontSize;

  /// Spacing between icon container and value text.
  final double spacingBetweenIconAndValue;

  /// Optional child to render instead of the default icon+value+label layout.
  /// When provided, [icon], [value], and [label] are ignored.
  final Widget? child;

  /// Optional callback when the card is tapped.
  final VoidCallback? onTap;

  const OverflowSafeCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.bgColor,
    this.padding,
    this.borderRadius = 16,
    this.iconSize = 20,
    this.iconContainerSize = 36,
    this.valueFontSize = 24,
    this.labelFontSize = 12,
    this.spacingBetweenIconAndValue = 8,
    this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconBgColor = bgColor ?? color.withAlpha(25);

    final cardContent = Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child ??
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon container
              Container(
                width: iconContainerSize,
                height: iconContainerSize,
                decoration: BoxDecoration(
                  color: effectiveIconBgColor,
                  borderRadius: BorderRadius.circular(iconContainerSize * 0.28),
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
              SizedBox(height: spacingBetweenIconAndValue),
              // Value text — wrapped in FittedBox to prevent overflow on large numbers
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: valueFontSize,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // Label text
              Text(
                label,
                style: TextStyle(
                  fontSize: labelFontSize,
                  color: AppColors.textCaption,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}

/// A compact mini stat card designed for horizontal Row layouts.
/// Automatically wraps itself in [Expanded] to share space equally.
class MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const MiniStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OverflowSafeCard(
        icon: icon,
        value: value,
        label: label,
        color: color,
        iconSize: 20,
        iconContainerSize: 32,
        valueFontSize: 18,
        labelFontSize: 10,
        borderRadius: 14,
        padding: const EdgeInsets.symmetric(vertical: 12),
        onTap: onTap,
      ),
    );
  }
}
