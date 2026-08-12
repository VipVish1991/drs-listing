import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/widgets/confirm_continue_button.dart';

void main() {
  Widget buildButton({
    FutureOr<void> Function()? onPressed,
    Duration minDuration = const Duration(milliseconds: 200),
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: ConfirmContinueButton(
            onPressed: onPressed ?? () {},
            minimumSpinnerDuration: minDuration,
          ),
        ),
      ),
    );
  }

  group('ConfirmContinueButton', () {
    testWidgets('renders label without a spinner initially', (tester) async {
      await tester.pumpWidget(buildButton());
      await tester.pumpAndSettle();

      expect(find.text('Confirm & Continue'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows spinner on tap and returns to idle for a sync '
        'callback', (tester) async {
      var pressed = false;
      await tester.pumpWidget(buildButton(onPressed: () => pressed = true));

      await tester.tap(find.text('Confirm & Continue'));
      await tester.pump(); // start loading state

      // Spinner visible; a sync callback fires immediately on tap.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Confirming…'), findsOneWidget);
      expect(pressed, isTrue);

      // After the minimum spinner duration the button returns to idle.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Confirm & Continue'), findsOneWidget);
    });

    testWidgets('does not fire callback twice on rapid taps', (tester) async {
      var pressCount = 0;
      await tester.pumpWidget(
        buildButton(onPressed: () => pressCount++),
      );

      await tester.tap(find.text('Confirm & Continue'));
      await tester.pump(); // button now loading/disabled

      // A second tap while loading must be ignored.
      await tester.tap(
        find.byType(ConfirmContinueButton),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(pressCount, 1);
    });

    testWidgets('spinner is tied to the real async load, not a fixed delay',
        (tester) async {
      var pressed = false;
      // Simulate a slow async action (e.g. OTP verification).
      await tester.pumpWidget(
        buildButton(
          onPressed: () async {
            await Future<void>.delayed(const Duration(seconds: 3));
            pressed = true;
          },
        ),
      );

      await tester.tap(find.text('Confirm & Continue'));
      await tester.pump(); // start loading

      // Well beyond the old 400ms fixed delay, the spinner is still up
      // because the real work is still running.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(pressed, isFalse);

      // The async work completes at 3s; the button then holds the spinner
      // for the minimum duration before returning to idle.
      await tester.pump(const Duration(seconds: 2));
      expect(pressed, isTrue);

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Confirm & Continue'), findsOneWidget);
    });
  });
}
