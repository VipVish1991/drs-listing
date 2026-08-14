import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:DrsListing/config/theme.dart';

void main() {
  group('AppTheme system overlay style', () {
    test('appBarTheme configures a white status bar with black icons', () {
      final style = AppTheme.lightTheme.appBarTheme.systemOverlayStyle;

      expect(style, isNotNull);
      expect(
        style!.statusBarColor,
        Colors.white,
        reason: 'the status bar is solid white across the whole app',
      );
      expect(
        style.statusBarIconBrightness,
        Brightness.dark,
        reason: 'black icons stay visible on the white status bar (Android)',
      );
      expect(
        style.statusBarBrightness,
        Brightness.light,
        reason: 'iOS keeps dark text over the white status bar',
      );
      expect(style.systemNavigationBarColor, AppColors.bgMain);
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    });
  });

  group('system overlay style applied at app level', () {
    testWidgets(
      'pumping a screen with the app theme sends the white status bar to the platform',
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

        // Pick the style the AppBar sent (identifiable by its white
        // status bar) rather than assuming microtask ordering of the
        // MaterialApp-level call.
        final effective = sentStyles.firstWhere(
          (args) => args['statusBarColor'] == Colors.white.value,
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

        // Solid white status bar, matching StatusBarService (plugin).
        expect(color(effective, 'statusBarColor'), Colors.white.value);
        // Black status-bar icons on the white bar.
        expect(
          brightness(effective, 'statusBarIconBrightness'),
          'Brightness.dark',
        );
        expect(
          brightness(effective, 'statusBarBrightness'),
          'Brightness.light',
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
