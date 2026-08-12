import 'package:flutter/material.dart';
import '../config/theme.dart';

// ════════════════════════════════════════════════════════════════════
// 1. AppBackButton — standard 44×44 rounded icon button for navigation
// ════════════════════════════════════════════════════════════════════

/// A 44×44 rounded icon button used consistently for back navigation,
/// close actions, and header icon controls across every screen.
///
/// Automatically adapts to dark mode. When [onPressed] is `null` the
/// button is disabled (dimmed and non-interactive) — e.g. screens that
/// must not be left mid-operation pass `_isLoading ? null : Get.back`.
class AppBackButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final Color? background;
  final double size;

  const AppBackButton({
    super.key,
    this.icon = Icons.arrow_back_ios_new,
    required this.onPressed,
    this.iconColor,
    this.background,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final col = iconColor ?? (isDark ? Colors.white : AppColors.textHeading);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            background ??
            (isDark
                ? const Color(0xFF1A1A2E).withAlpha(200)
                : AppColors.bgCard),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          if (!isDark)
            BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 18, color: col),
        onPressed: onPressed,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 2. AppPrimaryButton — full-width primary action with loading state
// ════════════════════════════════════════════════════════════════════

/// A full-width primary action button that follows the app's theme.
///
/// Supports an optional loading spinner that replaces the label while
/// [isLoading] is `true`, and custom [backgroundColor]/[foregroundColor]
/// for variant buttons such as "Logout" or "Cancel".
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.padding,
    this.borderRadius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.primary;
    final fg = foregroundColor ?? Colors.white;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          // Keep the button's primary colours while loading so the
          // white spinner stays visible on the themed background instead
          // of the default grey disabled palette (mirrors
          // ConfirmContinueButton).
          disabledBackgroundColor: bg,
          disabledForegroundColor: fg,
          elevation: 0,
          padding: padding ?? const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: isLoading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 3. AppActionChip — compact action button for cards
// ════════════════════════════════════════════════════════════════════

/// A compact action chip used inside doctor / appointment cards
/// (Call, Map, Cancel, Book, etc.).
///
/// Can be used directly or wrapped in a Row with one or more siblings.
class AppActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double verticalPadding;
  final double borderRadius;

  const AppActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.verticalPadding = 10,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: verticalPadding,
            horizontal: 12,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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

// ════════════════════════════════════════════════════════════════════
// 4. AppIconActionButton — icon button with tinted rounded background
// ════════════════════════════════════════════════════════════════════

/// A small square icon button with a tinted background, used for secondary
/// inline actions (e.g. the "Map" icon next to "Book" in doctor cards).
class AppIconActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final double size;
  final String? tooltip;
  final double iconSize;

  const AppIconActionButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 22,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: iconSize),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 5. AppSecondaryButton — outlined button for secondary actions
// ════════════════════════════════════════════════════════════════════

/// An outlined action button styled to match the app's secondary
/// UI patterns ("Try again", "Browse categories").
///
/// Uses an [OutlinedButton] with a tinted border and foreground.
class AppSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.color = AppColors.primary,
    this.borderRadius = 12,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(120)),
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 6. AppFilterChip — toggleable filter chip for search/filter bars
// ════════════════════════════════════════════════════════════════════

/// A compact toggle chip designed for horizontal filter bars.
///
/// When [isActive] the chip uses the primary color; otherwise it uses
/// a neutral card-style background.
class AppFilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color? activeColor;

  const AppFilterChip({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ac = activeColor ?? AppColors.primary;

    return Material(
      color: isActive
          ? ac.withAlpha(30)
          : isDark
          ? const Color(0xFF1A1A2E).withAlpha(200)
          : AppColors.bgCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? ac : AppColors.textCaption,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? ac : AppColors.textBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
