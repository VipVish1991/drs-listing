import 'package:flutter/material.dart';
import 'package:flutter_statusbarcolor_ns/flutter_statusbarcolor_ns.dart';
import '../config/theme.dart';

/// Applies the system status bar (and navigation bar) colors and icon
/// brightness using the `flutter_statusbarcolor_ns` plugin.
///
/// The status bar is TRANSPARENT by default so the teal gradient
/// headers show through; individual screens with white/light backgrounds
/// override locally via `AnnotatedRegion<SystemUiOverlayStyle>`.
///
/// The plugin calls are best-effort: on platforms where they are
/// unavailable (e.g. widget tests) they fail silently and the theme's
/// `SystemUiOverlayStyle` remains the default.
class StatusBarService {
  /// Applies the status bar style derived from [theme] (scaffold
  /// background color + brightness).
  static Future<void> applyTheme(ThemeData theme) {
    return apply(
      background: theme.scaffoldBackgroundColor,
      isDark: theme.brightness == Brightness.dark,
    );
  }

  /// Applies a transparent status bar with white foreground icons so
  /// the gradient headers show through, and keeps the system navigation
  /// bar consistent with the theme. [background] is accepted for
  /// call-site compatibility only.
  static Future<void> apply({
    required Color background,
    required bool isDark,
  }) async {
    try {
      // Transparent status bar — the gradient header shows through.
      // White foreground icons since the gradient is dark teal.
      await FlutterStatusbarcolor.setStatusBarColor(Colors.transparent);
      await FlutterStatusbarcolor.setStatusBarWhiteForeground(true);

      final navBarColor = isDark ? const Color(0xFF111318) : AppColors.bgMain;
      await FlutterStatusbarcolor.setNavigationBarColor(navBarColor);
      await FlutterStatusbarcolor.setNavigationBarWhiteForeground(
        useWhiteForeground(navBarColor),
      );
    } catch (_) {
      // Plugin unavailable (widget tests / unsupported platform) — the
      // theme's SystemUiOverlayStyle still covers the default styling.
    }
  }
}
