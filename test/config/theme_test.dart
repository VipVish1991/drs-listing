import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:DrsListing/config/theme.dart';

void main() {
  group('AppTheme system overlay style', () {
    test('appBarTheme configures a transparent status bar with light icons', () {
      final style = AppTheme.lightTheme.appBarTheme.systemOverlayStyle;

      expect(style, isNotNull);
      expect(
        style!.statusBarColor,
        Colors.transparent,
        reason: 'transparent so gradient headers show through',
      );
      expect(
        style.statusBarIconBrightness,
        Brightness.light,
        reason: 'white icons on the dark teal gradient header (Android)',
      );
      expect(
        style.statusBarBrightness,
        Brightness.dark,
        reason: 'iOS keeps light text over the gradient header',
      );
      expect(style.systemNavigationBarColor, AppColors.bgMain);
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    });
  });

  group('system overlay style applied at app level', () {
    testWidgets(
      'pumping a screen with the app theme sends the transparent status bar to the platform',
      (tester) async {
        // SystemChrome.setSystemUIOverlayStyle is invoked on
        // SystemChannels.platform with a map of platform-encoded values
        // (colors as ints, brightnesses as 'Brightness.dark' strings).
        final sentStyles = <Map<dynamic, dynamic>>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
              sentStyles.add(call.arguments as Map<dynamic, dynamic>);
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });

        // Every app screen renders an AppBar, which applies
        // appBarTheme.systemOverlayStyle (the configured white status bar)
        // via SystemChrome.setSystemUIOverlayStyle.
        await tester.pumpWidget(
          GetMaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              appBar: AppBar(title: const Text('overlay style test')),
              body: const Center(child: Text('overlay style test')),
            ),
          ),
        );

        // Pick the style the AppBar sent (identifiable by its transparent
        // status bar) rather than assuming microtask ordering of the
        // MaterialApp-level call.
        final effective = sentStyles.firstWhere(
          (args) => args['statusBarColor'] == Colors.transparent.value,
          orElse: () => <dynamic, dynamic>{},
        );
        String? brightness(Map<dynamic, dynamic> args, String key) =>
            args[key] as String?;
        int? color(Map<dynamic, dynamic> args, String key) => args[key] as int?;

        expect(
          effective,
          isNotEmpty,
          reason: 'the AppBar must call SystemChrome.setSystemUIOverlayStyle',
        );

        // Transparent status bar so gradient headers show through.
        expect(color(effective, 'statusBarColor'), Colors.transparent.value);
        // White status-bar icons on the dark teal gradient.
        expect(
          brightness(effective, 'statusBarIconBrightness'),
          'Brightness.light',
        );
        expect(
          brightness(effective, 'statusBarBrightness'),
          'Brightness.dark',
        );
        // Light system navigation bar with dark icons.
        expect(
          color(effective, 'systemNavigationBarColor'),
          AppColors.bgMain.value,
        );
        expect(
          brightness(effective, 'systemNavigationBarIconBrightness'),
          'Brightness.dark',
        );
      },
    );
  });
}
