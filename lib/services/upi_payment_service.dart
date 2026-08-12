import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:upi_india/upi_india.dart';

import '../config/constants.dart';

/// Outcome of a UPI payment attempt, normalized from the raw [UpiResponse]
/// so the booking flow only deals with the cases it actually cares about.
class UpiPaymentResult {
  /// 'success' — the UPI app reported the payment SUCCEEDED (the only
  /// outcome that books the appointment, status 'Paid').
  ///
  /// 'submitted' — the payment was initiated but NOT confirmed (status
  ///                'submitted' from the UPI app). Intent-based UPI has no
  ///                server-side verification, so an unconfirmed payment
  ///                NEVER books the appointment — the user is asked to
  ///                retry or pay offline instead.
  ///
  /// 'failed' — payment failed or was cancelled (no booking made).
  final String outcome;

  /// UPI transaction id from the UPI app (may be null when the app did not
  /// report one).
  final String? transactionId;

  final String? approvalRefNo;
  final String? rawResponse;

  const UpiPaymentResult({
    required this.outcome,
    this.transactionId,
    this.approvalRefNo,
    this.rawResponse,
  });

  bool get isSuccess => outcome == 'success';
  bool get isSubmitted => outcome == 'submitted';
  bool get isFailed => outcome == 'failed';

  /// True when the payment is CONFIRMED and the booking may proceed.
  ///
  /// Only 'success' counts — an unconfirmed ('submitted') payment must not
  /// book the appointment (the patient may not have paid anything).
  bool get proceedWithBooking => isSuccess;
}

/// Thin wrapper around [upi_india] for the app's booking flow.
///
/// Fires an intent to an installed UPI app (GPay/PhonePe/Paytm/…) with the
/// consultation fee and the clinic's VPA ([AppConstants.upiReceiverVpa]),
/// then maps the raw platform response to a [UpiPaymentResult]. Kept
/// deliberately small so the payment logic is easy to swap later (e.g. for
/// a full payment-gateway SDK that returns a server-verifiable txnId).
class UpiPaymentService {
  static final UpiPaymentService instance = UpiPaymentService._internal();
  UpiPaymentService._internal();

  /// Whether `getAllUpiApps` should include apps that don't return a
  /// standard Transaction ID, and apps the package hasn't verified.
  ///
  /// The package's defaults silently drop installed apps that don't return
  /// a txn id or report a non-success status. We want EVERY installed UPI
  /// app the device reports to be offered; the UPI app itself handles any
  /// extra confirmation.
  static const bool includeAllApps = true;

  /// Method channel for the native Android fallback discovery (see
  /// MainActivity.kt). The upi_india plugin finds UPI apps by the
  /// `upi://pay` intent — installed apps that don't declare that intent
  /// never show up in the picker. The native side re-checks the known UPI
  /// package list directly and reports which are installed.
  static const MethodChannel _upiFallbackChannel =
      MethodChannel('drslisting/upi_fallback');

  /// 1x1 transparent PNG — substituted when the native side couldn't encode
  /// an app's icon, so `UpiApp.icon` always has valid bytes.
  static final Uint8List _transparentIconPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  /// Installed UPI apps the patient can pay with (works only on Android;
  /// on other platforms returns an empty list so callers can fall back to
  /// offline payment). Apps come back in the phone's discovery order (the
  /// package manager's priority order — most-used apps first).
  ///
  /// The intent-based discovery is augmented with a native package-name
  /// fallback so a known UPI app that doesn't declare the `upi://pay`
  /// intent is still offered.
  /// Test seams — pin the discovery / fallback implementations so the
  /// crash-recovery interplay can be exercised on hosts without the
  /// platform channels. Null (default) uses the real implementations.
  @visibleForTesting
  static Future<List<UpiApp>> Function()? upiDiscoveryOverride;

  @visibleForTesting
  static Future<List<UpiApp>> Function()? packageFallbackOverride;

  Future<List<UpiApp>> getInstalledUpiApps() async {
    // Intent discovery and the package-name fallback are INDEPENDENT: a
    // crash in one must never hide the apps the other found. A single
    // try/catch around both meant the vendored plugin's getAllUpiApps
    // crash (adaptive-icon devices, API 26+) emptied the picker even
    // though the native fallback knew every installed app — the "no UPI
    // apps, payment not possible" bug.
    var discovered = const <UpiApp>[];
    try {
      discovered = await (upiDiscoveryOverride ??
          () => UpiIndia().getAllUpiApps(
                mandatoryTransactionId: !includeAllApps,
                allowNonVerifiedApps: includeAllApps,
              ))();
    } catch (_) {
      // Intent discovery failed — the fallback below still reports apps.
    }
    try {
      final fallback =
          await (packageFallbackOverride ?? _packageFallbackApps)();
      return mergePackageFallback(discovered, fallback);
    } catch (_) {
      // Fallback failed — keep whatever intent discovery found.
      return discovered;
    }
  }

  /// Native package-name discovery: every known UPI app that is INSTALLED
  /// is returned, even when it doesn't declare the `upi://pay` intent the
  /// plugin queries. Returns an empty list when the channel is unavailable
  /// (non-Android, tests).
  ///
  /// The native side supplies the app's display label and icon so the
  /// constructed [UpiApp] renders just like a discovered one.
  Future<List<UpiApp>> _packageFallbackApps() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    try {
      final packages = knownUpiPackageNames();
      final installed =
          await _upiFallbackChannel.invokeListMethod<Map<dynamic, dynamic>>(
        'findInstalledUpiApps',
        {'packages': packages},
      );
      final result = <UpiApp>[];
      for (final entry in installed ?? const <Map<dynamic, dynamic>>[]) {
        final pkg = entry['packageName'] as String?;
        if (pkg == null || pkg.isEmpty) continue;
        final app = UpiApp(
          entry['name']?.toString() ?? pkg,
          pkg,
        );
        app.icon = decodeFallbackIcon(entry['icon']);
        result.add(app);
      }
      return result;
    } catch (_) {
      // Channel missing / error — keep the intent-based list only.
      return const [];
    }
  }

  /// The known UPI package names the native fallback re-checks — the same
  /// set the [upi_india] plugin ships (see `UpiApp`'s predefined apps).
  static List<String> knownUpiPackageNames() => const [
        'com.lcode.allahabadupi',
        'in.amazon.mShop.android.shopping',
        'com.upi.axispay',
        'com.bankofbaroda.upi',
        'in.org.npci.upiapp',
        'com.infra.boiupi',
        'com.infrasofttech.centralbankupi',
        'in.cointab.app',
        'com.lcode.corpupi',
        'com.lcode.csbupi',
        'com.cub.wallet.gui',
        'com.dreamplug.androidapp',
        'com.dbs.in.digitalbank',
        'com.olive.dcb.upi',
        'com.equitasbank.upi',
        'com.finopaytech.bpayfino',
        'com.freecharge.android',
        'com.google.android.apps.nbu.paisa.user',
        'com.mgs.hsbcupi',
        'com.csam.icici.bank.imobile',
        'com.mgs.induspsp',
        'com.khaalijeb.inkdrops',
        'com.msf.kbank.mobile',
        'com.infrasofttech.mahaupi',
        'com.mipay.in.wallet',
        'com.mipay.wallet.in',
        'com.mobikwik_new',
        'com.mgs.obcbank',
        'net.one97.paytm',
        'com.idbibank.paywiz',
        'com.enstage.wibmo.hdfc',
        'com.phonepe.app',
        'com.fss.pnbpsp',
        'com.mobileware.upipsb',
        'com.rblbank.upi',
        'com.realmepay.payments',
        'com.sbi.upi',
        'com.truecaller',
        'com.fss.unbipsp',
        'com.fss.vijayapsp',
        'com.YesBank',
      ];

  /// Decodes a base64 icon from the native side, or returns the transparent
  /// placeholder when it's missing/corrupt. Public so the fallback seam is
  /// unit-testable on hosts where the platform channel never runs.
  static Uint8List decodeFallbackIcon(Object? iconB64) {
    if (iconB64 is! String || iconB64.isEmpty) return _transparentIconPng;
    try {
      return base64Decode(iconB64);
    } catch (_) {
      return _transparentIconPng;
    }
  }

  /// Merges the package-name-discovered [fallback] apps into the
  /// intent-based [discovered] list, skipping any package already present so
  /// no app is listed twice. Returns a new list; neither input is mutated.
  static List<UpiApp> mergePackageFallback(
    List<UpiApp> discovered,
    List<UpiApp> fallback,
  ) {
    final seen = discovered.map((a) => a.packageName).toSet();
    final merged = List<UpiApp>.of(discovered);
    for (final app in fallback) {
      if (seen.add(app.packageName)) {
        merged.add(app);
      }
    }
    return merged;
  }

  /// Launch the UPI payment flow in [app] for [amount] INR.
  ///
  /// [transactionRef] is a unique reference echoed back by the UPI app
  /// (the appointment id works well). [note] is the human-readable purpose
  /// shown in the UPI app (e.g. 'Consultation fee — Dr. X').
  ///
  /// [receiverUpiAddress] / [receiverName] override the app-wide default
  /// merchant VPA — the booking flow passes the booked doctor's own UPI ID
  /// so every clinic collects on their own account. Null falls back to
  /// [AppConstants.upiReceiverVpa] / [AppConstants.upiReceiverName].
  ///
  /// Returns a normalized [UpiPaymentResult]; never throws — platform
  /// errors (no UPI apps, invalid amount, cancelled) map to a 'failed'
  /// outcome so the caller always has a decision to make.
  Future<UpiPaymentResult> pay({
    required UpiApp app,
    required double amount,
    required String transactionRef,
    String note = 'Consultation fee',
    String? receiverUpiAddress,
    String? receiverName,
  }) async {
    try {
      final response = await UpiIndia().startTransaction(
        app: app,
        receiverUpiId: receiverUpiAddress ?? AppConstants.upiReceiverVpa,
        receiverName: receiverName ?? AppConstants.upiReceiverName,
        transactionRefId: transactionRef,
        transactionNote: note,
        amount: amount,
      );
      return mapResponse(response);
    } catch (_) {
      // Platform errors — including the package's own thrown exceptions
      // (user_canceled, app_not_installed, null_response,
      // invalid_parameters) — never reach the booking flow.
      return const UpiPaymentResult(outcome: 'failed');
    }
  }

  /// Maps the raw [UpiResponse] to a normalized outcome. Public so the real
  /// parsing path is directly testable (build a response from the raw UPI
  /// callback string, exactly like the platform does).
  UpiPaymentResult mapResponse(UpiResponse response) {
    switch (response.status) {
      case UpiPaymentStatus.SUCCESS:
        return UpiPaymentResult(
          outcome: 'success',
          transactionId: response.transactionId ?? response.approvalRefNo,
          approvalRefNo: response.approvalRefNo,
        );
      case UpiPaymentStatus.SUBMITTED:
        // Payment initiated but NOT confirmed — per the booking rule this
        // never proceeds (see UpiPaymentResult.proceedWithBooking).
        return UpiPaymentResult(
          outcome: 'submitted',
          transactionId: response.transactionId ?? response.approvalRefNo,
          approvalRefNo: response.approvalRefNo,
        );
      default:
        // failure / other / null — payment did not go through.
        return const UpiPaymentResult(outcome: 'failed');
    }
  }
}
