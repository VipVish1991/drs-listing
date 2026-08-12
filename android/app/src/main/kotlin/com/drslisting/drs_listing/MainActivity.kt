package com.drslisting.ai

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    /// Fallback UPI-app discovery by PACKAGE NAME, not the `upi://pay`
    /// intent. The upi_india plugin only lists apps that declare
    /// that intent filter — some installed UPI apps don't, so they silently
    /// never appear in the payment picker. This channel re-checks the known
    /// UPI package list directly and reports which ones are installed, with
    /// their real icons. See UpiPaymentService.getInstalledUpiApps.
    ///
    /// No <queries> addition is needed here: the plugin's own manifest
    /// already declares every known UPI package in <queries>, and manifest
    /// merging includes it in this app's final manifest, so the packages are
    /// visible on Android 11+.
    private val upiFallbackChannel = "drslisting/upi_fallback"

    /// Opens the system Wi-Fi / network settings page. Used by the offline
    /// banner's "Settings" action so the user can re-enable connectivity.
    /// See NetworkSettingsService.openWifiSettings.
    private val networkSettingsChannel = "drslisting/network_settings"

    /// Reads the currently connected Wi-Fi network (SSID + signal strength)
    /// for the home screen's offline connectivity status card. See
    /// WifiStatusService.getWifiStatus.
    private val wifiInfoChannel = "drslisting/wifi_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, upiFallbackChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "findInstalledUpiApps" -> {
                        val packages = call.argument<List<String>>("packages")
                        result.success(findInstalledUpiApps(packages))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkSettingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWifiSettings" -> {
                        startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wifiInfoChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getWifiStatus" -> result.success(getWifiStatus())
                    else -> result.notImplemented()
                }
            }
    }

    /// Reports the device's current Wi-Fi state for the offline status card:
    /// whether Wi-Fi is enabled, whether it is connected to an access point,
    /// and — when connected — the network name (SSID), signal strength
    /// (RSSI + 0..4 bar level) and link speed.
    ///
    /// Reading the SSID requires location permission on Android 8.1+ (and
    /// enabled location services); when the permission is missing the SSID
    /// comes back null and the card falls back to a generic "connected"
    /// message instead of guessing.
    @Suppress("DEPRECATION")
    private fun getWifiStatus(): Map<String, Any?> {
        val wifi = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return emptyMap()

        val info = wifi.connectionInfo
        // Connected = Wi-Fi is on AND the connection has a real network id
        // (networkId == -1 means not associated with any access point).
        val connected = wifi.isWifiEnabled && info != null && info.networkId != -1

        val locationGranted = Build.VERSION.SDK_INT < 23 ||
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

        // SSID comes back wrapped in quotes ("NetworkName") and as
        // "<unknown ssid>" when location is missing — normalize both away.
        val ssid = if (connected && locationGranted) {
            info.ssid
                ?.removeSurrounding("\"")
                ?.takeIf { it.isNotBlank() && it != "<unknown ssid>" }
        } else {
            null
        }

        val rssi = if (connected) info.rssi else Int.MIN_VALUE
        val signalLevel = if (connected && rssi != Int.MIN_VALUE) {
            WifiManager.calculateSignalLevel(rssi, 5)
        } else {
            -1
        }

        return mapOf(
            "wifiEnabled" to wifi.isWifiEnabled,
            "connected" to connected,
            "ssid" to ssid,
            "rssi" to (if (connected) rssi else null),
            "signalLevel" to (if (signalLevel in 0..4) signalLevel else null),
            "linkSpeedMbps" to (if (connected) info.linkSpeed else null),
            "frequencyMhz" to (if (connected) info.frequency else null),
            "locationGranted" to locationGranted,
        )
    }

    /// Returns `[{packageName, name, icon}]` for every known UPI package
    /// that is installed on this device, regardless of its intent filters.
    /// Installed packages the intent query missed are exactly the apps the
    /// payment picker was silently hiding. The display label (name) lets
    /// the Dart side build a [UpiApp] with a readable title.
    private fun findInstalledUpiApps(packages: List<String>?): List<Map<String, Any?>> {
        val pm = packageManager ?: return emptyList()
        val found = mutableListOf<Map<String, Any?>>()
        for (pkg in packages.orEmpty()) {
            try {
                // getApplicationInfo(pkg, 0) throws NameNotFoundException when
                // the package is missing or (Android 11+) not in the visible
                // set — either way it's not an app we can offer.
                val appInfo = pm.getApplicationInfo(pkg, 0)
                val label = pm.getApplicationLabel(appInfo)?.toString() ?: pkg
                found.add(
                    mapOf(
                        "packageName" to pkg,
                        "name" to label,
                        "icon" to encodeIcon(pm.getApplicationIcon(pkg)),
                    )
                )
            } catch (_: PackageManager.NameNotFoundException) {
                // Not installed / not visible — skip.
            } catch (_: Exception) {
                // Icon encoding failed — still report the app with a null
                // icon; the Dart side substitutes a neutral placeholder.
                found.add(mapOf("packageName" to pkg, "icon" to null))
            }
        }
        return found
    }

    /// Encodes an app icon drawable as a base64 PNG, or null on failure.
    private fun encodeIcon(drawable: Drawable): String? {
        return try {
            val bitmap = when (drawable) {
                is BitmapDrawable -> drawable.bitmap
                else -> {
                    // Adaptive icons report intrinsicWidth/Height of -1 —
                    // draw them onto a fixed 48x48 canvas instead.
                    val w = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 48
                    val h = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 48
                    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bmp)
                    drawable.setBounds(0, 0, w, h)
                    drawable.draw(canvas)
                    bmp
                }
            }
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        } catch (_: Exception) {
            null
        }
    }
}
