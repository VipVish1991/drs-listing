import 'package:flutter/foundation.dart';
import 'package:quantupi/quantupi.dart';

/// Outcome of a UPI payment attempt, normalized from the raw response
/// string the [Quantupi] plugin returns so the booking flow only deals
/// with the cases it actually cares about.
class QuantupiPaymentResult {
  /// 'success' — the UPI app reported the payment SUCCEEDED (the only
  /// outcome that books the appointment, status 'Paid').
  ///
  /// 'submitted' — the payment was initiated but NOT confirmed (status
  /// 'submitted' from the UPI app). Intent-based UPI has no server-side
  /// verification, so an unconfirmed payment NEVER books the appointment —
  /// the user is asked to retry or pay offline instead.
  ///
  /// 'failed' — payment failed, was cancelled, or no UPI app handled it
  /// (no booking made).
  final String outcome;

  /// UPI transaction id from the UPI app (may be null when the app did not
  /// report one).
  final String? transactionId;

  /// Bank approval reference number (may be null).
  final String? approvalRefNo;

  /// The UPI app's response code — '00' on a confirmed success, or the
  /// raw value the app returned (e.g. the string 'null' on-device). Kept
  /// as-is for tracking/debugging.
  final String? responseCode;

  /// The transaction reference ECHOED BACK by the UPI app — the `tr`
  /// (transactionRef) value the intent was fired with. Useful to reconcile
  /// the recorded payment against the bank statement.
  final String? txnRef;

  /// Package id of the UPI app that actually processed the payment (e.g.
  /// `com.dreamplug.androidapp` for Cred, `com.phonepe.app`, …) — null when
  /// the app did not report it.
  final String? appId;

  /// The complete raw response string from the UPI app — stored verbatim
  /// so a disputed payment can always be traced back to the exact bytes.
  final String? rawResponse;

  const QuantupiPaymentResult({
    required this.outcome,
    this.transactionId,
    this.approvalRefNo,
    this.responseCode,
    this.txnRef,
    this.appId,
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

/// Thin wrapper around the vendored [Quantupi] plugin for the app's
/// booking flow.
///
/// Fires the `upi://pay` intent with the consultation fee and the
/// doctor's own receiving VPA; Android's system chooser lets the patient
/// pick the installed UPI app (GPay/PhonePe/Paytm/…). The raw response
/// string is normalized into a [QuantupiPaymentResult]. Kept deliberately
/// small so the payment logic is easy to swap later (e.g. for a full
/// payment-gateway SDK that returns a server-verifiable txnId).
///
/// UPI intents only work on Android — the plugin has no web/desktop
/// implementation and iOS custom schemes cannot return a transaction
/// status, so [pay] fails on every other platform and callers fall back
/// to offline pay-at-clinic.
class QuantupiPaymentService {
  static final QuantupiPaymentService instance =
      QuantupiPaymentService._internal();
  QuantupiPaymentService._internal();

  /// Test seam — replaces the plugin invocation (which checks
  /// `Platform.isAndroid` and would branch to the iOS path on a test
  /// host) with a fake returning a raw UPI response string.
  @visibleForTesting
  static Future<String> Function(Quantupi upi)? transactionOverride;

  /// Test seam — forces [isSupported] to true so [pay] runs the intent
  /// on hosts where the plugin can't (the fake [transactionOverride]
  /// supplies the response). Never set in production.
  @visibleForTesting
  static bool? forceAndroid;

  /// Whether the current platform can run a UPI payment intent
  /// (Android only — see class docs).
  bool get isSupported =>
      forceAndroid ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// Run a UPI payment of [amount] to [receiverUpiId] (the doctor's own
  /// VPA — never a placeholder) with the patient-facing [receiverName],
  /// a unique [transactionRef] and a human-readable [note].
  ///
  /// Returns a normalized [QuantupiPaymentResult]. Never throws — every
  /// platform/plugin failure maps to a 'failed' outcome so the booking
  /// flow always has a decision to make.
  Future<QuantupiPaymentResult> pay({
    required String receiverUpiId,
    required String receiverName,
    required double amount,
    required String transactionRef,
    required String note,
  }) async {
    // Safety net: never fire an intent to a blank / placeholder address.
    if (receiverUpiId.trim().isEmpty) {
      return const QuantupiPaymentResult(
        outcome: 'failed',
        rawResponse: 'missing_receiver_vpa',
      );
    }
    if (!isSupported) {
      return const QuantupiPaymentResult(
        outcome: 'failed',
        rawResponse: 'unsupported_platform',
      );
    }

    final upi = Quantupi(
      receiverUpiId: receiverUpiId,
      receiverName: receiverName,
      transactionRefId: transactionRef,
      transactionNote: note,
      amount: amount,
    );

    final String raw;
    try {
      raw = await (transactionOverride ?? (u) => u.startTransaction())(upi);
    } catch (_) {
      // Plugin failure (e.g. invalid parameters) — treat as not-paid.
      return QuantupiPaymentResult(
        outcome: 'failed',
        rawResponse: 'plugin_error',
      );
    }
    return QuantupiPaymentService.parseResponse(raw);
  }

  /// Normalize a raw UPI response string into a [QuantupiPaymentResult].
  ///
  /// The plugin returns whatever the UPI app put in its `response` extra —
  /// typically the full `upi://pay?txnid=…&status=…` URI (URL-encoded),
  /// or a plain error marker such as `user_canceled` / `null_response`.
  /// This parser strips the leading scheme, URL-decodes, and tolerates
  /// missing keys (the vendored plugin's own parser crashes on those).
  ///
  /// Keys are matched case-insensitively — real UPI apps return a mix of
  /// `status=…` and `Status=…` (seen on-device: `Status=FAILURE&`), and a
  /// `Status=SUCCESS` must not be misread as a failure.
  static QuantupiPaymentResult parseResponse(String raw) {
    final body = raw.startsWith('upi://')
        ? raw.replaceFirst(RegExp(r'^upi://pay\?'), '')
        : raw.replaceFirst(RegExp(r'^\?'), '');

    final params = <String, String>{};
    for (final part in body.split('&')) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      try {
        params[Uri.decodeComponent(kv[0]).toLowerCase()] =
            Uri.decodeComponent(kv[1]);
      } catch (_) {
        // Ignore a malformed segment — keep parsing the rest.
      }
    }

    final status = (params['status'] ?? '').toLowerCase();
    final String outcome;
    if (status == 'success') {
      outcome = 'success';
    } else if (status.contains('fail')) {
      outcome = 'failed';
    } else if (status.contains('submit')) {
      outcome = 'submitted';
    } else {
      // No usable status — the UPI app cancelled/ignored the request, or
      // the response is an error marker. Never treat an unknown response
      // as paid.
      outcome = 'failed';
    }

    // Collapse an empty value to null so a blank field is never recorded
    // as a real reference (on-device the UPI app returns `txnId=` with no
    // value, and `responseCode=null` as the literal string 'null').
    String? nonEmpty(String? v) =>
        (v == null || v.isEmpty || v == 'null') ? null : v;

    return QuantupiPaymentResult(
      outcome: outcome,
      transactionId: nonEmpty(params['txnid']),
      approvalRefNo: nonEmpty(params['approvalrefno']),
      responseCode: params['responsecode'],
      txnRef: nonEmpty(params['txnref']),
      appId: nonEmpty(params['appid']),
      rawResponse: raw,
    );
  }
}
