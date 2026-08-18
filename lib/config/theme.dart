import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // Zocdoc-inspired Primary Colors
  static const Color primary = Color(0xFF0B8A6F); // Rich teal-green
  static const Color primaryLight = Color(0xFFE8F5F0); // Light mint
  static const Color primaryDark = Color(0xFF076B55); // Darker green
  static const Color secondary = Color(0xFF2DCA9A); // Bright accent green
  static const Color accent = Color(
    0xFFFFB800,
  ); // Warm amber for ratings/accents
  static const Color success = Color(0xFF2DCA9A);
  static const Color warning = Color(0xFFFFB800);
  static const Color error = Color(0xFFE54D4D);
  static const Color info = Color(0xFF4A9FE7);

  // Background Colors
  static const Color bgMain = Color(0xFFF5F7FA); // Light grey-blue
  static const Color bgSurface = Color(0xFFFFFFFF);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgSecondarySurface = Color(0xFFF0F2F5);

  // Text Colors
  static const Color textHeading = Color(0xFF1A1D21);
  static const Color textBody = Color(0xFF636E7A);
  static const Color textCaption = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFD1D5DB);
  static const Color textWhite = Color(0xFFFFFFFF);

  // Specialist Colors (softened)
  static const Color healthBrain = Color(0xFF7C8CF5);
  static const Color healthHeart = Color(0xFFF57C9A);
  static const Color healthDigestive = Color(0xFF5BBA6F);
  static const Color healthBone = Color(0xFF7C8CF5);
  static const Color healthImmune = Color(0xFFFFB84D);
  static const Color healthEndocrine = Color(0xFFFF8A6C);
  static const Color healthRespiratory = Color(0xFF4A9FE7);
  static const Color healthNervous = Color(0xFF9B7CF5);

  // Navigation Colors
  static const Color navBackground = Color(0xFFFFFFFF);
  static const Color navActiveIcon = Color(0xFF0B8A6F);
  static const Color navInactiveIcon = Color(0xFF9CA3AF);
  static const Color navCenterAction = Color(0xFF0B8A6F);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.bgSurface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.bgMain,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        // App-wide system UI style: a WHITE status bar with BLACK
        // icons/text so the clock/battery stay visible (Android), plus a
        // light system navigation bar. `statusBarBrightness` is the
        // iOS-only counterpart — kept light there so the (transparent,
        // uncolorable) iOS status bar keeps dark text over the app's
        // light surfaces. This matches what StatusBarService + main.dart
        // apply via the flutter_statusbarcolor_ns plugin. MaterialApp uses
        // this as the default for every route; screens with dark surfaces
        // (e.g. the splash screen) override locally.
        systemOverlayStyle: const SystemUiOverlayStyle(
          // Transparent so the teal gradient headers show through.
          // Light icons/text on the dark gradient; screens with a
          // white/light body override locally via AnnotatedRegion.
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.bgMain,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: AppColors.textHeading,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: AppColors.textHeading),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.textHeading,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: AppColors.textHeading,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: AppColors.textHeading,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: AppColors.textHeading,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(color: AppColors.textBody, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.textBody, fontSize: 14),
        bodySmall: TextStyle(color: AppColors.textCaption, fontSize: 12),
        labelLarge: TextStyle(
          color: AppColors.textWhite,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textWhite,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgMain,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: AppColors.textCaption, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textBody),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        shadowColor: Colors.black.withAlpha(10),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.navBackground,
        selectedItemColor: AppColors.navActiveIcon,
        unselectedItemColor: AppColors.navInactiveIcon,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textWhite,
        elevation: 4,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.textDisabled.withAlpha(60),
        thickness: 1,
      ),
    );
  }

  /// Standard card decoration used across the app — Zocdoc-style white card
  /// with subtle shadow and rounded corners.
  static BoxDecoration cardDecoration({
    double radius = 16,
    Color? backgroundColor,
    double blurRadius = 16,
    double opacity = 0.08,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? AppColors.bgCard,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha((opacity * 255).round()),
          blurRadius: blurRadius,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// Border-only card decoration for secondary surfaces.
  static BoxDecoration borderCardDecoration({
    double radius = 16,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? const Color(0xFFE5E7EB),
        width: 1,
      ),
    );
  }
}
