import 'package:flutter/material.dart';
import 'package:flutter_statusbarcolor_ns/flutter_statusbarcolor_ns.dart';
import '../config/theme.dart';

/// Applies the system status bar (and navigation bar) colors and icon
/// brightness using the `flutter_statusbarcolor_ns` plugin.
///
/// The status bar is solid BLACK across the whole app (with white icons)
/// regardless of the screen behind it — matching the app-wide
/// `SystemUiOverlayStyle` in the theme. Only the system navigation bar
/// still follows the screen's brightness ([isDark]).
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

  /// Applies the solid black status bar with white icons on every screen
  /// (the whole-app design), and keeps the system navigation bar
  /// consistent with the theme. [background] is accepted for call-site
  /// compatibility only — the status bar is always black.
  static Future<void> apply({
    required Color background,
    required bool isDark,
  }) async {
    try {
      // Black status bar across the whole app with white icons — the
      // screen's own background color never shows through.
      await FlutterStatusbarcolor.setStatusBarColor(Colors.black);
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
