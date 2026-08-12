import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/screens/doctor/doctor_appointments_screen.dart';

/// Opens [PrescriptionUploadDialog] inside a [GetMaterialApp] (so its
/// `Get.back(result:)` calls resolve against a real navigator) and returns
/// a [Completer] that resolves with the value the dialog pops with. The
/// dialog starts its upload in `initState`, so [upload] must be controlled
/// with a [Completer] whenever the test needs an in-flight state.
Future<Completer<String?>> _openDialog(
  WidgetTester tester,
  Future<String?> Function() upload,
) async {
  final popped = Completer<String?>();
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final value = await Get.dialog<String?>(
                  PrescriptionUploadDialog(upload: upload),
                  barrierDismissible: false,
                );
                popped.complete(value);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return popped;
}

void main() {
  testWidgets('shows progress while uploading, then pops with the URL', (
    tester,
  ) async {
    final gate = Completer<String?>();
    final popped = await _openDialog(tester, () => gate.future);

    // Upload still in flight → progress state.
    expect(find.text('Uploading prescription…'), findsOneWidget);
    expect(find.text('Upload failed'), findsNothing);

    gate.complete('https://rx.example.com/rx1.jpg');
    await tester.pumpAndSettle();
    expect(await popped.future, 'https://rx.example.com/rx1.jpg');
    expect(find.byType(PrescriptionUploadDialog), findsNothing);
  });

  testWidgets('failure shows the error state and Retry re-runs the upload', (
    tester,
  ) async {
    var attempts = 0;
    final firstGate = Completer<String?>();
    final popped = await _openDialog(tester, () {
      attempts++;
      if (attempts == 1) return firstGate.future;
      return Future.value('https://rx.example.com/rx2.jpg');
    });

    // First attempt fails (completes null) → error state with Retry.
    firstGate.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Upload failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Complete without Prescription'), findsOneWidget);

    // Retry re-runs the upload → succeeds → dialog pops with the URL.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(await popped.future, 'https://rx.example.com/rx2.jpg');
    expect(find.byType(PrescriptionUploadDialog), findsNothing);
  });

  testWidgets('retry shows the progress state again while re-uploading', (
    tester,
  ) async {
    var attempts = 0;
    final firstGate = Completer<String?>();
    final retryGate = Completer<String?>();
    final popped = await _openDialog(tester, () {
      attempts++;
      if (attempts == 1) return firstGate.future;
      return retryGate.future;
    });

    firstGate.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Upload failed'), findsOneWidget);

    // Retry → the second attempt is gated, so the progress state must be
    // visible again (not the stale error). Pump past the AnimatedSwitcher
    // transition so the outgoing error column is removed.
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Uploading prescription…'), findsOneWidget);
    expect(find.text('Upload failed'), findsNothing);

    retryGate.complete('https://rx.example.com/rx3.jpg');
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(await popped.future, 'https://rx.example.com/rx3.jpg');
  });

  testWidgets('cancel during upload pops with null and leaves state as is', (
    tester,
  ) async {
    final gate = Completer<String?>();
    final popped = await _openDialog(tester, () => gate.future);

    expect(find.text('Uploading prescription…'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await popped.future, isNull);
    expect(find.byType(PrescriptionUploadDialog), findsNothing);
  });

  testWidgets('Complete without Prescription pops with the sentinel', (
    tester,
  ) async {
    final gate = Completer<String?>();
    final popped = await _openDialog(tester, () => gate.future);

    gate.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Upload failed'), findsOneWidget);

    await tester.tap(find.text('Complete without Prescription'));
    await tester.pumpAndSettle();

    expect(await popped.future, kCompleteWithoutPrescription);
    expect(find.byType(PrescriptionUploadDialog), findsNothing);
  });

  testWidgets('a throwing upload is treated as a failure, not a crash', (
    tester,
  ) async {
    final popped = await _openDialog(
      tester,
      () async => throw Exception('network down'),
    );

    await tester.pumpAndSettle();
    expect(find.text('Upload failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(popped.isCompleted, isFalse); // still open — awaiting the choice
  });
}
