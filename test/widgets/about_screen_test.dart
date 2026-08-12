import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/screens/profile/about_screen.dart';

/// Lets every flutter_animate effect on the About screen run to completion.
Future<void> _settleAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('About screen renders its content sections', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const AboutScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('About'), findsOneWidget);
    expect(find.text('DrsListing'), findsOneWidget);
    expect(find.text('Our Mission'), findsOneWidget);
    expect(find.text('Key Features'), findsOneWidget);
    expect(find.text('App Version'), findsOneWidget);

    await _settleAnimations(tester);
  });

  testWidgets('the removed API Calls Today row no longer renders', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const AboutScreen(),
      ),
    );
    await tester.pump();

    // Regression guard: the Google Places usage counter was removed from the
    // app, so neither the label nor its count chip may appear on About.
    expect(find.text('API Calls Today'), findsNothing);
    expect(find.text('—'), findsNothing);

    await _settleAnimations(tester);
  });
}
