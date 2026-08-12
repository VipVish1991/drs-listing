import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:upi_india/upi_india.dart';

import 'package:DrsListing/services/upi_payment_service.dart';

void main() {
  group('UpiPaymentService.getInstalledUpiApps (discovery)', () {
    final service = UpiPaymentService.instance;

    test('requests every installed UPI app (verified + unverified, no txn-id '
        'requirement)', () {
      // The package's defaults silently drop installed apps that don't
      // return a txn id or report a non-success status. The service must
      // always request the full list and let the UPI app itself handle any
      // extra confirmation.
      expect(UpiPaymentService.includeAllApps, isTrue);
    });

    test('returns an empty list gracefully on non-mobile hosts (no crash)',
        () async {
      // On the test host (not Android) the package throws
      // MissingPluginException; the service must swallow it and return []
      // so callers fall back to offline payment.
      final apps = await service.getInstalledUpiApps();
      expect(apps, isEmpty);
    });
  });

  group('UpiPaymentService.mergePackageFallback (native package fallback)',
      () {
    UpiApp fakeApp(String name, String package) {
      final app = UpiApp(name, package);
      app.icon = Uint8List.fromList(List.filled(8, 0));
      return app;
    }

    List<String> namesOf(List<UpiApp> apps) =>
        apps.map((a) => a.name).toList();

    test('appends installed-but-missed apps after the discovered ones', () {
      final discovered = [fakeApp('GPay', 'com.google.android.apps.nbu.paisa.user')];
      final fallback = [
        fakeApp('PhonePe', 'com.phonepe.app'),
        fakeApp('Paytm', 'net.one97.paytm'),
      ];
      final merged =
          UpiPaymentService.mergePackageFallback(discovered, fallback);
      expect(namesOf(merged), ['GPay', 'PhonePe', 'Paytm']);
    });

    test('skips fallback apps the intent query already found (no dupes)', () {
      final discovered = [
        fakeApp('GPay', 'com.google.android.apps.nbu.paisa.user'),
        fakeApp('Paytm', 'net.one97.paytm'),
      ];
      final fallback = [
        fakeApp('Paytm', 'net.one97.paytm'),
        fakeApp('PhonePe', 'com.phonepe.app'),
      ];
      final merged =
          UpiPaymentService.mergePackageFallback(discovered, fallback);
      expect(namesOf(merged), ['GPay', 'Paytm', 'PhonePe']);
    });

    test('an empty discovered list keeps every fallback app', () {
      final fallback = [fakeApp('GPay', 'com.google.android.apps.nbu.paisa.user')];
      final merged = UpiPaymentService.mergePackageFallback(const [], fallback);
      expect(namesOf(merged), ['GPay']);
    });

    test('does not mutate either input list', () {
      final discovered = [fakeApp('GPay', 'com.google.android.apps.nbu.paisa.user')];
      final fallback = [fakeApp('PhonePe', 'com.phonepe.app')];
      UpiPaymentService.mergePackageFallback(discovered, fallback);
      expect(discovered.length, 1);
      expect(fallback.length, 1);
    });
  });

  group('UpiPaymentService.getInstalledUpiApps (crash recovery)', () {
    final service = UpiPaymentService.instance;

    UpiApp fakeApp(String name, String package) {
      final app = UpiApp(name, package);
      app.icon = Uint8List.fromList(List.filled(8, 0));
      return app;
    }

    List<String> namesOf(List<UpiApp> apps) =>
        apps.map((a) => a.name).toList();

    tearDown(() {
      UpiPaymentService.upiDiscoveryOverride = null;
      UpiPaymentService.packageFallbackOverride = null;
    });

    test('a crashing intent discovery still offers the native fallback apps',
        () async {
      // Regression: the vendored plugin's getAllUpiApps crashed on
      // adaptive-icon devices (API 26+); a single try/catch around BOTH
      // discovery and fallback meant the whole picker came back empty. The
      // package-name fallback must still run and offer every known app.
      UpiPaymentService.upiDiscoveryOverride = () async =>
          throw StateError('native getAllUpiApps crashed');
      UpiPaymentService.packageFallbackOverride = () async => [
            fakeApp('Google Pay', 'com.google.android.apps.nbu.paisa.user'),
            fakeApp('PhonePe', 'com.phonepe.app'),
          ];
      final apps = await service.getInstalledUpiApps();
      expect(namesOf(apps), ['Google Pay', 'PhonePe']);
    });

    test('a crashing fallback keeps the intent-discovered apps', () async {
      UpiPaymentService.upiDiscoveryOverride = () async =>
          [fakeApp('Google Pay', 'com.google.android.apps.nbu.paisa.user')];
      UpiPaymentService.packageFallbackOverride = () async =>
          throw StateError('channel missing');
      final apps = await service.getInstalledUpiApps();
      expect(namesOf(apps), ['Google Pay']);
    });

    test('both discovery and fallback crashing yields an empty list (no '
        'throw)', () async {
      UpiPaymentService.upiDiscoveryOverride =
          () async => throw StateError('boom');
      UpiPaymentService.packageFallbackOverride =
          () async => throw StateError('boom');
      final apps = await service.getInstalledUpiApps();
      expect(apps, isEmpty);
    });

    test('working discovery and fallback merge without duplicate packages',
        () async {
      UpiPaymentService.upiDiscoveryOverride = () async =>
          [fakeApp('Google Pay', 'com.google.android.apps.nbu.paisa.user')];
      UpiPaymentService.packageFallbackOverride = () async => [
            fakeApp('PhonePe', 'com.phonepe.app'),
            fakeApp('Google Pay', 'com.google.android.apps.nbu.paisa.user'),
          ];
      final apps = await service.getInstalledUpiApps();
      expect(namesOf(apps), ['Google Pay', 'PhonePe']);
    });
  });

  group('UpiPaymentService.knownUpiPackageNames (coverage)', () {
    test('includes the reference manifest’s popular UPI payment apps '
        '(incl. CRED)', () {
      final known = UpiPaymentService.knownUpiPackageNames();
      for (final pkg in const [
        'com.google.android.apps.nbu.paisa.user', // Google Pay
        'com.phonepe.app', // PhonePe
        'net.one97.paytm', // Paytm
        'in.amazon.mShop.android.shopping', // Amazon Pay
        'in.org.npci.upiapp', // BHIM
        'com.dreamplug.androidapp', // CRED
        'com.mobikwik_new', // Mobikwik
        'com.freecharge.android', // Freecharge
      ]) {
        expect(known, contains(pkg));
      }
    });
  });

  group('UpiPaymentService.decodeFallbackIcon (native icon decoding)', () {
    test('valid base64 icon decodes to its bytes', () {
      final bytes = UpiPaymentService.decodeFallbackIcon(
        base64Encode([1, 2, 3, 4, 5]),
      );
      expect(bytes, [1, 2, 3, 4, 5]);
    });

    test('missing / empty / non-string icons get the transparent placeholder',
        () {
      for (final bad in [null, '', 42]) {
        final bytes = UpiPaymentService.decodeFallbackIcon(bad);
        // Valid, non-empty PNG bytes (the 1x1 transparent placeholder).
        expect(bytes, isNotEmpty);
        expect(bytes.first, 0x89); // PNG magic byte
      }
    });

    test('corrupt base64 gets the transparent placeholder', () {
      final bytes =
          UpiPaymentService.decodeFallbackIcon('@@@not-base64@@@');
      expect(bytes, isNotEmpty);
      expect(bytes.first, 0x89); // PNG magic byte
    });
  });

  group('UpiPaymentService.mapResponse (real parser path)', () {
    final service = UpiPaymentService.instance;

    // Build real responses exactly like the platform does — UpiResponse
    // parses the raw UPI callback string itself, then mapResponse()
    // normalizes it. This exercises the production parsing path, not a
    // test-only helper.

    test('status=success → success outcome, proceeds with booking', () {
      final response = UpiResponse(
        'txnId=TXN123&responseCode=00&approvalRefNo=APPROVED&status=success',
      );
      final result = service.mapResponse(response);
      expect(result.isSuccess, isTrue);
      expect(result.proceedWithBooking, isTrue);
      expect(result.outcome, 'success');
    });

    test('status=submitted → submitted outcome, does NOT proceed with '
        'booking (payment not confirmed)', () {
      // Regression: an unconfirmed payment must never book the appointment.
      final response = UpiResponse('txnId=TXN456&status=submitted');
      final result = service.mapResponse(response);
      expect(result.isSubmitted, isTrue);
      expect(result.proceedWithBooking, isFalse);
      expect(result.outcome, 'submitted');
    });

    test('status=failure → failed outcome, blocks booking', () {
      final response = UpiResponse(
        'txnId=TXN789&responseCode=ZM&status=failure',
      );
      final result = service.mapResponse(response);
      expect(result.isFailed, isTrue);
      expect(result.proceedWithBooking, isFalse);
    });

    test('unknown/other status → failed outcome (defaults to failure)', () {
      final response = UpiResponse('status=other');
      final result = service.mapResponse(response);
      expect(result.isFailed, isTrue);
      expect(result.proceedWithBooking, isFalse);
    });

    test('transactionId / approvalRefNo are carried through', () {
      final response = UpiResponse(
        'txnId=TXN123&responseCode=00&approvalRefNo=APPROVED&status=success',
      );
      final result = service.mapResponse(response);
      expect(result.transactionId, 'TXN123');
      expect(result.approvalRefNo, 'APPROVED');
    });

    test('malformed response (trailing & / empty part) parses without '
        'crashing — a paid transaction is never misread as failed', () {
      // Regression: a trailing '&' produced an empty split segment that
      // made UpiResponse throw RangeError, mapping a possibly-paid
      // transaction to 'failed'.
      final response = UpiResponse('txnId=TXN123&status=success&');
      final result = service.mapResponse(response);
      expect(result.isSuccess, isTrue);
      expect(result.transactionId, 'TXN123');
    });
  });
}
