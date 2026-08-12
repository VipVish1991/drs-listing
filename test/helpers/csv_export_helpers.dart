import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared test helpers for CSV-export widget tests — used by both the
/// payment history and patient history suites so the mocked share_plus +
/// path_provider channels stay in one place (a channel-name or argument
/// change must not drift one copy silently).

/// Mocks the share_plus + path_provider platform channels so an export
/// button runs end-to-end in tests (writes a real temp file, then
/// "shares" it). Returns the recorded share calls and the temp dir used.
(List<MethodCall>, Directory) mockExportPlatform(
  WidgetTester tester, {
  bool failPathProvider = false,
}) {
  final shareCalls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/share'),
    (call) async {
      shareCalls.add(call);
      // share_plus decodes the result as a status STRING.
      return 'dev.fluttercommunity.plus/share/success';
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      null,
    );
  });

  final tmpDir = Directory.systemTemp.createTempSync('csv_export_test');
  addTearDown(() {
    try {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort: Windows may briefly hold a freshly written CSV
      // (AV/indexer). A failed cleanup must never fail the test itself.
    }
  });
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      if (failPathProvider) {
        throw PlatformException(code: 'test_failure');
      }
      return call.method == 'getTemporaryDirectory' ? tmpDir.path : null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  return (shareCalls, tmpDir);
}

/// The path of the single file shared by the last share call (share_plus
/// passes the paths under the 'paths' argument).
String sharedFilePath(List<MethodCall> shareCalls) {
  final args = shareCalls.last.arguments as Map<dynamic, dynamic>;
  return (args['paths'] as List).cast<String>().single;
}

/// Lets the export flow's real-async tail (the temp-file write via
/// dart:io) complete: real I/O doesn't finish inside the fake-async test
/// zone, and the resumed continuation needs a flush cycle afterwards.
/// Polls until [done] returns true (or a generous cap).
Future<void> settleExport(WidgetTester tester, {bool Function()? done}) async {
  for (var i = 0; i < 10 && (done == null || !done()); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
