package com.drslisting.ai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.app.FlutterApplication

/// App-level Application — its onCreate runs on EVERY process start,
/// including when the process is spawned purely for a background FCM push
/// (FirebaseMessagingService). Creating the notification channel here —
/// not just in MainActivity (which only runs when the user opens the app)
/// — guarantees the channel exists before any FCM message is displayed, so
/// no push is silently dropped on a device that updated the app but hasn't
/// opened it yet.
class DrsListingApp : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    /// High-importance channel so appointment pushes pop as heads-up
    /// banners with sound instead of silently landing in the shade
    /// (the FCM fallback channel is DEFAULT importance).
    ///
    /// IMPORTANCE_HIGH enables the heads-up banner + default sound +
    /// vibration. The notifications Edge Function sends FCM messages with
    /// `android.notification.channel_id = "drslisting_appointments"` — keep
    /// this id in sync with supabase/functions/notifications/index.ts.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "drslisting_appointments",
            "Appointment Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New appointment requests, cancellations and status updates"
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
