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
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Parcelable;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
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

        // ── CUSTOM designed chooser (matches the app's teal-green look) ──
        // The stock AlertDialog's black title bar + plain list looked
        // foreign next to the app's rounded mint cards. This dialog is a
        // white rounded card with a teal header, per-app rows (icon in a
        // soft container + label), and a full-width Cancel pill.
        // Root column: teal header + scrollable app list + Cancel pill.
        LinearLayout root = new LinearLayout(activity);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);

        // Header — the app's teal gradient, white bold title + subtitle.
        LinearLayout header = new LinearLayout(activity);
        header.setOrientation(LinearLayout.VERTICAL);
        header.setPadding(dp(20), dp(18), dp(20), dp(16));
        GradientDrawable headerBg = new GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                new int[]{0xFF0B8A6F, 0xFF076B55});
        // Round ONLY the top corners — the header sits at the top of the
        // dialog's rounded card, so its own corners must follow the card's
        // radius or the square teal corners would stick out.
        headerBg.setCornerRadii(new float[]{
                dp(20), dp(20), dp(20), dp(20), 0, 0, 0, 0});
        header.setBackground(headerBg);

        TextView title = new TextView(activity);
        title.setText("Pay with");
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        header.addView(title);

        TextView subtitle = new TextView(activity);
        subtitle.setText("Choose a UPI app to send the payment");
        subtitle.setTextColor(Color.parseColor("#B3FFFFFF"));
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        LinearLayout.LayoutParams subLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        subLp.topMargin = dp(2);
        header.addView(subtitle, subLp);
        root.addView(header);

        // Guard: the dialog can be dismissed WITHOUT the Cancel button
        // (back key, tap-outside). Both paths must resolve the pending
        // Dart future — but only if the user hasn't already picked an app
        // (choosing an app dismisses the dialog too, and the UPI app's own
        // response must be what resolves the future then).
        final boolean[] launched = {false};

        // The app list: one rounded row per UPI app. Built programmatically
        // (no layout XML in this plugin) — icon in a soft mint container,
        // label beside it. The rows get their click listeners AFTER the
        // dialog exists (tapping one must dismiss the dialog, so the
        // handler needs the dialog reference).
        LinearLayout list = new LinearLayout(activity);
        list.setOrientation(LinearLayout.VERTICAL);
        final List<LinearLayout> rows = new ArrayList<>();
        for (int i = 0; i < labels.size(); i++) {
            final int index = i;
            LinearLayout row = new LinearLayout(activity);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(dp(16), dp(10), dp(16), dp(10));

            // Icon in a soft mint rounded container.
            FrameLayout iconWrap = new FrameLayout(activity);
            GradientDrawable iconBg = new GradientDrawable();
            iconBg.setColor(Color.parseColor("#E8F5F0"));
            iconBg.setCornerRadius(dp(12));
            iconWrap.setBackground(iconBg);
            int box = dp(40);
            iconWrap.setLayoutParams(new LinearLayout.LayoutParams(box, box));

            ImageView iconView = new ImageView(activity);
            Drawable icon = icons.get(index);
            if (icon != null) {
                int size = dp(22);
                icon.setBounds(0, 0, size, size);
                iconView.setImageDrawable(icon);
            }
            FrameLayout.LayoutParams iconLp = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER);
            iconWrap.addView(iconView, iconLp);
            row.addView(iconWrap);

            TextView label = new TextView(activity);
            label.setText(labels.get(index));
            label.setTextColor(Color.parseColor("#1A1D21"));
            label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
            label.setTypeface(Typeface.create("sans-serif-medium",
                    Typeface.NORMAL));
            LinearLayout.LayoutParams labelLp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT);
            labelLp.setMarginStart(dp(14));
            row.addView(label, labelLp);

            list.addView(row);
            rows.add(row);
        }
        // Wrap the list in a ScrollView capped at ~6 rows so a phone with
        // many UPI apps never overflows the screen (8+ apps would exceed
        // small displays; the list scrolls instead).
        ScrollView scroller = new ScrollView(activity);
        scroller.setVerticalScrollBarEnabled(false);
        scroller.addView(list);
        int maxRows = Math.min(labels.size(), 6);
        LinearLayout.LayoutParams listLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(60) * maxRows);
        root.addView(scroller, listLp);

        // Full-width Cancel pill (teal outline style).
        TextView cancel = new TextView(activity);
        cancel.setText("Cancel");
        cancel.setGravity(Gravity.CENTER);
        cancel.setTextColor(Color.parseColor("#0B8A6F"));
        cancel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        cancel.setTypeface(Typeface.DEFAULT_BOLD);
        cancel.setPadding(0, dp(14), 0, dp(14));
        GradientDrawable cancelBg = new GradientDrawable();
        cancelBg.setColor(Color.parseColor("#E8F5F0"));
        cancelBg.setCornerRadius(dp(14));
        cancel.setBackground(cancelBg);
        LinearLayout.LayoutParams cancelLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        cancelLp.setMargins(dp(16), dp(4), dp(16), dp(16));
        root.addView(cancel, cancelLp);

        // Dialog with rounded corners + white card background. Zero insets
        // on the custom view so the teal header reaches the card's edges
        // (AlertDialog's default padding would leave white gaps around it).
        AlertDialog dialog = new AlertDialog.Builder(activity)
                .setView(root)
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
        // AlertDialog's default padding would leave white gaps around the
        // custom view — zero it out so the teal header + list span the
        // whole rounded card.
        dialog.setView(root, 0, 0, 0, 0);
        if (dialog.getWindow() != null) {
            GradientDrawable bg = new GradientDrawable();
            bg.setColor(Color.WHITE);
            bg.setCornerRadius(dp(20));
            dialog.getWindow().setBackgroundDrawable(bg);
        }

        // Attach the tap handlers NOW that the dialog exists — BOTH must
        // dismiss the dialog. The old stock dialog auto-dismissed on item
        // tap / Cancel (AlertDialog's setAdapter + setNegativeButton), but
        // this custom view has no auto-dismiss, so without an explicit
        // dismiss() the picker would stay on screen forever after the user
        // picked an app or hit Cancel — exactly the "popup won't close"
        // report.
        //   • App row → dismiss, THEN launch that UPI app. The UPI app's
        //     own response resolves the pending Dart future; the dismiss
        //     fires onDismiss, which no-ops because launched[0] is true.
        //   • Cancel → take-and-clear + resolve 'user_canceled' FIRST,
        //     then dismiss. The dismiss fires onDismiss, but finalResult
        //     is already null so it no-ops — no "Reply already submitted"
        //     double-resolve crash.
        for (int i = 0; i < rows.size(); i++) {
            final int index = i;
            rows.get(i).setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    launched[0] = true;
                    dialog.dismiss();
                    try {
                        activity.startActivityForResult(
                                appIntents.get(index), uniqueRequestCode);
                    } catch (Exception e) {
                        // The app vanished between the query and the tap
                        // (uninstalled/disabled) — resolve as cancelled so
                        // the booking flow never hangs.
                        MethodChannel.Result pending = finalResult;
                        finalResult = null;
                        if (pending != null) {
                            pending.success("user_canceled");
                        }
                    }
                }
            });
        }
        cancel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                // Take-and-clear BEFORE resolving: the dismiss below fires
                // onDismiss, and a second success() on the same
                // MethodChannel Result throws "Reply already submitted" —
                // which crashes the app (the user sees the app exit).
                // Clearing the pending slot here makes that onDismiss a
                // no-op, exactly like the onActivityResult /
                // handleNewIntent double-delivery guard.
                MethodChannel.Result pending = finalResult;
                finalResult = null;
                if (pending != null) {
                    pending.success("user_canceled");
                }
                dialog.dismiss();
            }
        });

        dialog.show();
    }

    /// Density-scaled dp → px helper for the programmatically built
    /// chooser dialog (the plugin ships no layout resources).
    private int dp(int value) {
        return (int) (value * activity.getResources()
                .getDisplayMetrics().density + 0.5f);
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
