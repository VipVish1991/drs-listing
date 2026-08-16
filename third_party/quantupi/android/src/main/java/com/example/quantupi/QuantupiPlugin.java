package com.example.quantupi;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;
import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.util.Log;


/** QuantupiPlugin */
public class QuantupiPlugin implements FlutterPlugin, MethodCallHandler, PluginRegistry.ActivityResultListener, ActivityAware {

    int uniqueRequestCode = 3498;
    /// The pending method-channel result. STATIC on purpose: when a UPI
    /// app returns via a fresh intent, Android can relaunch this activity
    /// into a NEW task/instance (taskAffinity="" in the manifest), which
    /// recreates the Flutter engine and this plugin — but the payment the
    /// user just made belongs to the OLD instance's pending promise. A
    /// static keeps that promise alive across engine re-attach so the
    /// Dart-side `startTransaction` future still resolves.
    static MethodChannel.Result finalResult;
    boolean exception = false;
    Activity activity;

    /// The plugin instance, exposed so the host MainActivity can forward
    /// UPI return intents to it from onNewIntent. Many real UPI apps
    /// (PhonePe, GPay, Paytm, …) do NOT deliver the payment result via
    /// onActivityResult — they relaunch the calling app with a fresh
    /// `upi://pay?…` VIEW intent. That lands in onNewIntent, which the
    /// plugin has no way to observe, so without this bridge the pending
    /// transaction would hang forever (exactly what the on-device smoke
    /// test caught). Set on attach, cleared on detach.
    public static QuantupiPlugin instance;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        instance = this;
        final MethodChannel channel = new MethodChannel(flutterPluginBinding.getFlutterEngine().getDartExecutor(), "quantupi");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        if (call.method.equals("startTransaction")) {
            finalResult = result;
            String receiverUpiId = call.argument("receiverUpiId");
            String receiverName = call.argument("receiverName");
            String transactionRefId = call.argument("transactionRefId");
            String transactionNote = call.argument("transactionNote");
            String amount = call.argument("amount");
            String currency = call.argument("currency");
            String url = call.argument("url");
            String merchantId = call.argument("merchantId");

            try {
                exception = false;
                Uri.Builder uriBuilder = new Uri.Builder();
                uriBuilder.scheme("upi").authority("pay");
                uriBuilder.appendQueryParameter("pa", receiverUpiId);
                uriBuilder.appendQueryParameter("pn", receiverName);
                uriBuilder.appendQueryParameter("tn", transactionNote);
                uriBuilder.appendQueryParameter("am", amount);
                if (transactionRefId != null) {
                    uriBuilder.appendQueryParameter("tr", transactionRefId);
                }
                if (currency == null) {
                    uriBuilder.appendQueryParameter("cr", "INR");
                } else
                    uriBuilder.appendQueryParameter("cu", currency);
                if (url != null) {
                    uriBuilder.appendQueryParameter("url", url);
                }
                if (merchantId != null) {
                    uriBuilder.appendQueryParameter("mc", merchantId);
                }

                Uri uri = uriBuilder.build();

                Intent intent = new Intent(Intent.ACTION_VIEW);
                intent.setData(uri);
                activity.startActivityForResult(intent, uniqueRequestCode);
            } catch (Exception ex) {
                exception = true;
                result.error("FAILED", "invalid_parameters", null);
            }
        } else {
            result.notImplemented();
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (instance == this) instance = null;
    }

    /// Handles a UPI response delivered as a NEW intent (the return path
    /// used by PhonePe/GPay/Paytm). The response params ride in the URI
    /// query of the `upi://pay?…` data, e.g.
    /// `upi://pay?txnId=…&responseCode=00&Status=SUCCESS&…`. They are
    /// rebuilt into the same `key=value&…` string the method channel
    /// contract promises, so the Dart-side parser sees an identical
    /// payload whether the response came via onActivityResult or a fresh
    /// intent. A `upi://` return without a pending transaction is
    /// ignored (e.g. the app was cold-started by a stale deep link).
    ///
    /// STATIC because the return intent may land on a fresh activity/engine
    /// (taskAffinity=""), and the static [finalResult] is what needs
    /// resolving — no per-instance state is involved.
    public static void handleNewIntent(Intent intent) {
        Log.d("Quantupi", "handleNewIntent: data="
                + (intent != null && intent.getData() != null ? intent.getData() : "null"));
        if (finalResult == null) return;
        Uri data = intent.getData();
        if (data == null || !"upi".equalsIgnoreCase(data.getScheme())) return;
        try {
            StringBuilder sb = new StringBuilder();
            for (String key : data.getQueryParameterNames()) {
                String value = data.getQueryParameter(key);
                if (value == null) continue;
                if (sb.length() > 0) sb.append('&');
                sb.append(key).append('=').append(value);
            }
            finalResult.success(sb.length() > 0 ? sb.toString() : "user_canceled");
        } catch (Exception ex) {
            finalResult.success("user_canceled");
        }
    }

    // On receiving the response.
    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (uniqueRequestCode == requestCode && finalResult != null) {
            if (data != null) {
                try {
                    String response =data.getStringExtra("response");

                    if (!exception) finalResult.success(response);
                } catch (Exception ex) {
                    if (!exception) finalResult.success("null_response");
                }
            } else {
                Log.d("Quantupi NOTE: ", "Received NULL, User cancelled the transaction.");
                if (!exception) finalResult.success("user_canceled");
            }
        }
        return true;
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activity = binding.getActivity();
        binding.addActivityResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {

    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {

    }

    @Override
    public void onDetachedFromActivity() {

    }
}
