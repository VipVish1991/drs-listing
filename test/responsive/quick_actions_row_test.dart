import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/widgets/quick_actions_row.dart';
import 'package:DrsListing/config/theme.dart';

/// Builds a [QuickActionsRow] wrapped in the app theme so it renders
/// identically to how it would inside the real screen.
Widget _buildQuickActionsRow(DoctorModel doctor) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SingleChildScrollView(child: QuickActionsRow(doctor: doctor)),
    ),
  );
}

/// A minimal doctor that has phone and location (2-button case).
DoctorModel _doctorWith2Buttons() {
  return DoctorModel(
    placeId: 'test_2b',
    name: 'Test Doctor',
    phoneNumber: '+1234567890',
    latitude: 12.34,
    longitude: 56.78,
    // No website — only Call + Directions shown
  );
}

/// A doctor that also has a website URL (3-button case).
DoctorModel _doctorWith3Buttons() {
  return DoctorModel(
    placeId: 'test_3b',
    name: 'Test Doctor',
    phoneNumber: '+1234567890',
    latitude: 12.34,
    longitude: 56.78,
    website: 'https://testclinic.com',
  );
}

void main() {
  group('QuickActionsRow responsive layout', () {
    // The widget uses Expanded children so RenderFlex overflow cannot fire.
    // The real concern is whether labels are legible (checked via overflow
    // property) and that every button renders at all widths.

    const smallScreen = Size(320, 800); // iPhone SE / small Android
    const mediumScreen = Size(360, 800); // typical phone
    const largeScreen = Size(414, 896); // iPhone 11 Pro Max / larger phone

    // ── 2-button tests ────────────────────────────────────────────

    testWidgets('2 buttons render at 320dp', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(smallScreen);
      await tester.pumpWidget(_buildQuickActionsRow(_doctorWith2Buttons()));
      await tester.pumpAndSettle();

      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Website'), findsNothing);

      // Longest label's overflow is set to ellipsis as a safety measure
      final directions = tester.widget<Text>(find.text('Directions'));
      expect(directions.overflow, TextOverflow.ellipsis);
    });

    testWidgets('2 buttons render at 360dp', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(mediumScreen);
      await tester.pumpWidget(_buildQuickActionsRow(_doctorWith2Buttons()));
      await tester.pumpAndSettle();

      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Website'), findsNothing);
    });

    // ── 3-button tests ────────────────────────────────────────────

    testWidgets('3 buttons render at 320dp with ellipsis safety', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(smallScreen);
      await tester.pumpWidget(_buildQuickActionsRow(_doctorWith3Buttons()));
      await tester.pumpAndSettle();

      // All three buttons present
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);

      // "Directions" is the longest label; verify overflow is handled
      final directions = tester.widget<Text>(find.text('Directions'));
      expect(directions.overflow, TextOverflow.ellipsis);
    });

    testWidgets('3 buttons render at 360dp', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(mediumScreen);
      await tester.pumpWidget(_buildQuickActionsRow(_doctorWith3Buttons()));
      await tester.pumpAndSettle();

      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
    });

    testWidgets('3 buttons render at 414dp', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(largeScreen);
      await tester.pumpWidget(_buildQuickActionsRow(_doctorWith3Buttons()));
      await tester.pumpAndSettle();

      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
    });
  });
}
