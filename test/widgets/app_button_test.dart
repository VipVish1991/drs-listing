import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/widgets/app_button.dart';

void main() {
  Widget buildButton({
    required String label,
    required bool isLoading,
    VoidCallback? onPressed,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: AppPrimaryButton(
            label: label,
            isLoading: isLoading,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  group('AppPrimaryButton', () {
    testWidgets('renders label without a spinner when idle', (tester) async {
      await tester.pumpWidget(
        buildButton(label: 'Continue', isLoading: false, onPressed: () {}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows spinner in the button instead of the label while '
        'loading', (tester) async {
      await tester.pumpWidget(
        buildButton(label: 'Continue', isLoading: true, onPressed: () {}),
      );
      // pump (not pumpAndSettle): the indeterminate spinner never settles.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('button is disabled and does not fire callback while loading',
        (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        buildButton(
          label: 'Book Appointment',
          isLoading: true,
          onPressed: () => pressed = true,
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(AppPrimaryButton), warnIfMissed: false);
      await tester.pump();

      expect(pressed, isFalse);
    });

    testWidgets('fires callback when tapped while idle', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        buildButton(
          label: 'Continue',
          isLoading: false,
          onPressed: () => pressed = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppPrimaryButton));
      expect(pressed, isTrue);
    });

    testWidgets('keeps primary background colour while loading (not grey)',
        (tester) async {
      await tester.pumpWidget(
        buildButton(label: 'Continue', isLoading: true, onPressed: () {}),
      );
      // pump (not pumpAndSettle): the indeterminate spinner never settles.
      await tester.pump();

      final elevated = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      // Resolve the background for the DISABLED state: styleFrom builds
      // backgroundColor as a state-dependent property, so resolving with
      // MaterialState.disabled returns the disabledBackgroundColor value.
      final disabledBg =
          elevated.style?.backgroundColor?.resolve({MaterialState.disabled});
      // The resolved disabled background must still be the primary colour,
      // not Material's default grey.
      expect(disabledBg, AppColors.primary);
    });
  });
}
