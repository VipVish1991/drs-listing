import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Selectable payment row used by the booking screen's Online/Offline
/// payment-method sheet.
class PaymentMethodTile extends StatelessWidget {
  final IconData? icon;

  /// Optional custom leading widget (e.g. a payment-app icon image)
  /// rendered in place of the icon box.
  final Widget? leading;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const PaymentMethodTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  }) : assert(icon != null || leading != null,
            'either icon or leading must be provided');

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(45), width: 1.2),
          ),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withAlpha(14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon ?? Icons.currency_rupee_rounded,
                    color: color,
                    size: 21,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHeading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textCaption,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
