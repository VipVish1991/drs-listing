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
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Parcelable;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;


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

                // This app itself declares a `upi://` VIEW intent-filter
                // (to catch the payment-return intents PhonePe/GPay/Paytm
                // relaunch), which makes the Android resolver list the app
                // alongside the real UPI apps in the payment picker.
                // Exclude our own package from the candidates so the
                // picker never offers the app itself as a "UPI app".
                final List<ResolveInfo> candidates = activity.getPackageManager()
                        .queryIntentActivities(intent, 0);
                final String selfPackage = activity.getPackageName();
                final List<Intent> targets = new ArrayList<>();
                for (ResolveInfo ri : candidates) {
                    if (ri.activityInfo == null
                            || selfPackage.equals(ri.activityInfo.packageName)) {
                        continue;
                    }
                    Intent target = new Intent(intent);
                    target.setPackage(ri.activityInfo.packageName);
                    targets.add(target);
                }

                // Debug aid: confirm every installed UPI app made it into
                // the picker (package-visibility fix) — tag `Quantupi` in
                // logcat.
                StringBuilder names = new StringBuilder();
                for (Intent t : targets) {
                    if (names.length() > 0) names.append(", ");
                    names.append(t.getPackage());
                }
                Log.d("Quantupi", "UPI picker targets (" + targets.size()
                        + "): " + names);

                if (targets.isEmpty()) {
                    // No other UPI app installed/visible — nothing to
                    // launch. Resolve immediately so the booking flow
                    // doesn't hang; the Dart side treats this as failed.
                    // Take-and-clear: a stale `upi://` return intent or a
                    // late onActivityResult must never resolve this dead
                    // Result a second time (throws and crashes).
                    MethodChannel.Result pending = finalResult;
                    finalResult = null;
                    if (pending != null) {
                        pending.success("user_canceled");
                    }
                } else if (targets.size() == 1) {
                    activity.startActivityForResult(targets.get(0), uniqueRequestCode);
                } else {
                    // CUSTOM in-app chooser (replaces Android's system
                    // chooser): the system chooser is a horizontally-paged
                    // carousel that only shows ~3 apps per page, so users
                    // thought the provider list was incomplete. This dialog
                    // lists EVERY installed UPI app vertically, with its
                    // real icon and label, in one scrollable list. Tapping
                    // one launches exactly that app.
                    showUpiAppChooser(intent, candidates, targets.size());
                }
            } catch (Exception ex) {
                exception = true;
                result.error("FAILED", "invalid_parameters", null);
            }
        } else {
            result.notImplemented();
        }
    }

    /// Shows a custom UPI-app chooser dialog listing EVERY installed UPI
    /// app (excluding this app itself) vertically — the system chooser is
    /// a paged carousel that hides apps behind swipes, which made users
    /// think the provider list was incomplete. Tapping an entry launches
    /// that exact app via startActivityForResult (same result flow as
    /// before, so onActivityResult/handleNewIntent still resolve the
    /// Dart-side future).
    private void showUpiAppChooser(Intent baseIntent,
                                   List<ResolveInfo> candidates,
                                   int targetCount) {
        final PackageManager pm = activity.getPackageManager();
        final String selfPackage = activity.getPackageName();

        // Collect (label, icon, intent) per candidate, skipping self.
        final List<String> labels = new ArrayList<>();
        final List<Drawable> icons = new ArrayList<>();
        final List<Intent> appIntents = new ArrayList<>();
        for (ResolveInfo ri : candidates) {
            if (ri.activityInfo == null
                    || selfPackage.equals(ri.activityInfo.packageName)) {
                continue;
            }
            try {
                labels.add((String) ri.loadLabel(pm));
            } catch (Exception e) {
                labels.add(ri.activityInfo.packageName);
            }
            try {
                icons.add(ri.loadIcon(pm));
            } catch (Exception e) {
                icons.add(null);
            }
            Intent appIntent = new Intent(baseIntent);
            appIntent.setPackage(ri.activityInfo.packageName);
            appIntents.add(appIntent);
        }

        // If anything above failed to line up (shouldn't happen), fall
        // back to the system chooser rather than showing a broken dialog.
        if (appIntents.size() != targetCount) {
            Intent chooser = Intent.createChooser(appIntents.remove(0),
                    "Choose UPI app");
            chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS,
                    appIntents.toArray(new Parcelable[0]));
            activity.startActivityForResult(chooser, uniqueRequestCode);
            return;
        }

        ArrayAdapter<String> adapter = new ArrayAdapter<String>(
                activity, android.R.layout.select_dialog_item,
                android.R.id.text1, labels) {
            @Override
            public View getView(int position, View convertView,
                                ViewGroup parent) {
                View view = super.getView(position, convertView, parent);
                if (view instanceof TextView) {
                    TextView tv = (TextView) view;
                    Drawable icon = icons.get(position);
                    if (icon != null) {
                        int size = (int) (24 * activity.getResources()
                                .getDisplayMetrics().density);
                        icon.setBounds(0, 0, size, size);
                        tv.setCompoundDrawables(icon, null, null, null);
                        tv.setCompoundDrawablePadding((int) (16 * activity
                                .getResources().getDisplayMetrics().density));
                    }
                }
                return view;
            }
        };

        // Guard: the dialog can be dismissed WITHOUT the Cancel button
        // (back key, tap-outside). Both paths must resolve the pending
        // Dart future — but only if the user hasn't already picked an app
        // (choosing an app dismisses the dialog too, and the UPI app's own
        // response must be what resolves the future then).
        final boolean[] launched = {false};
        AlertDialog dialog = new AlertDialog.Builder(activity)
                .setTitle("Pay with")
                .setAdapter(adapter, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dlg, int which) {
                        launched[0] = true;
                        activity.startActivityForResult(
                                appIntents.get(which), uniqueRequestCode);
                    }
                })
                .setNegativeButton("Cancel",
                        new DialogInterface.OnClickListener() {
                            @Override
                            public void onClick(DialogInterface dlg,
                                                int which) {
                                // Take-and-clear BEFORE resolving: the
                                // dialog dismisses right after this click
                                // (firing onDismiss below), and a second
                                // success() on the same MethodChannel
                                // Result throws "Reply already submitted"
                                // — which crashes the app (the user sees
                                // the app exit). Clearing the pending slot
                                // here makes that onDismiss a no-op,
                                // exactly like the onActivityResult /
                                // handleNewIntent double-delivery guard.
                                MethodChannel.Result pending = finalResult;
                                finalResult = null;
                                if (pending != null) {
                                    pending.success("user_canceled");
                                }
                            }
                        })
                .setOnDismissListener(new DialogInterface.OnDismissListener() {
                    @Override
                    public void onDismiss(DialogInterface dlg) {
                        // Back key / tap-outside with no app picked —
                        // resolve as cancelled so the flow never hangs.
                        // finalResult is null here after a Cancel click or
                        // after an app was picked, so those paths no-op.
                        if (!launched[0] && finalResult != null) {
                            MethodChannel.Result pending = finalResult;
                            finalResult = null;
                            pending.success("user_canceled");
                        }
                    }
                })
                .create();
        dialog.show();
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
        // Take the reply and clear the pending slot BEFORE resolving: some
        // UPI apps (e.g. Cred) deliver the result via BOTH the fresh-intent
        // path AND onActivityResult. Only the first delivery may resolve the
        // Dart-side reply — a second one throws "Reply already submitted"
        // and crashes the app. Clearing here makes the second a no-op.
        MethodChannel.Result pending = finalResult;
        finalResult = null;
        try {
            StringBuilder sb = new StringBuilder();
            for (String key : data.getQueryParameterNames()) {
                String value = data.getQueryParameter(key);
                if (value == null) continue;
                if (sb.length() > 0) sb.append('&');
                sb.append(key).append('=').append(value);
            }
            pending.success(sb.length() > 0 ? sb.toString() : "user_canceled");
        } catch (Exception ex) {
            pending.success("user_canceled");
        }
    }

    // On receiving the response.
    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (uniqueRequestCode == requestCode && finalResult != null) {
            // Same double-delivery guard as handleNewIntent: whichever path
            // resolves the reply first wins; the late onActivityResult (e.g.
            // result 0 with null data after the fresh-intent already
            // returned the payment) must not submit the reply a second time.
            MethodChannel.Result pending = finalResult;
            finalResult = null;
            if (data != null) {
                try {
                    String response = data.getStringExtra("response");

                    if (!exception) pending.success(response);
                } catch (Exception ex) {
                    if (!exception) pending.success("null_response");
                }
            } else {
                Log.d("Quantupi NOTE: ", "Received NULL, User cancelled the transaction.");
                if (!exception) pending.success("user_canceled");
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
