import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/services/notification_service.dart';

/// Guards the startup path: `main()` awaits `NotificationService.instance
/// .initBounded()` so a FirebaseMessaging init that hangs forever (broken
/// Google Play Services) can never block app boot. Every case injects a stub
/// [init] and a short [timeout] — the real Firebase plugin is never touched.
void main() {
  group('NotificationService.initBounded', () {
    test('completes when init finishes normally', () async {
      var calls = 0;

      await NotificationService.instance.initBounded(
        init: () async => calls++,
        timeout: const Duration(seconds: 1),
      );

      expect(calls, 1, reason: 'the underlying init must actually run');
    });

    test('returns after the timeout when init never completes', () async {
      var called = false;
      final neverCompletes = Completer<void>();
      final stopwatch = Stopwatch()..start();

      await NotificationService.instance.initBounded(
        init: () {
          called = true;
          return neverCompletes.future; // hangs forever, like broken GMS
        },
        timeout: const Duration(milliseconds: 100),
      );

      stopwatch.stop();
      expect(called, isTrue, reason: 'the hung init is still started');
      expect(stopwatch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 100)),
          reason: 'it waited for the timeout instead of bailing early');
      // Reaching this point without hanging is the core assertion: startup
      // continues even though the underlying init never resolved.
    });

    test('swallows an error thrown by init before the timeout', () async {
      await NotificationService.instance.initBounded(
        init: () async => throw StateError('firebase exploded'),
        timeout: const Duration(seconds: 1),
      );
      // No throw escaping initBounded = startup proceeds, notifications no-op.
    });

    test('swallows an error that arrives after the timeout fired', () async {
      final lateError = Completer<void>();

      await NotificationService.instance.initBounded(
        init: () => lateError.future,
        timeout: const Duration(milliseconds: 50),
      );

      // The init future errors AFTER initBounded already returned. The
      // timeout machinery must drop it — otherwise it surfaces as an
      // unhandled async error and this test fails.
      lateError.completeError(StateError('late failure'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  });
}
