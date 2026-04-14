package com.gavra013.gavra_android

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Sluša sve incoming notifikacije i budi ekran kad stigne notifikacija
 * za Gavra 013 app (com.gavra013.gavra_android).
 *
 * NAPOMENA: Korisnik mora jednom da odobri pristup u:
 *   Settings → Apps → Special App Access → Notification access → Gavra 013
 */
class GavraNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "GavraNotifListener"
        private const val GAVRA_PACKAGE = "com.gavra013.gavra_android"
        // Koliko ms ekran ostaje upaljen (8 sekundi)
        private const val WAKE_DURATION_MS = 8_000L
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        sbn ?: return

        // Reaguj samo na notifikacije ove aplikacije
        if (sbn.packageName != GAVRA_PACKAGE) return

        android.util.Log.d(TAG, "Gavra notifikacija primljena, budim ekran…")
        wakeScreen(WAKE_DURATION_MS)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        // Ništa ne radimo pri uklanjanju
    }

    /**
     * Budi ekran koristeći PowerManager WakeLock sa ACQUIRE_CAUSES_WAKEUP.
     * Ovo radi i kad je app u background-u / ekran ugašen.
     */
    private fun wakeScreen(durationMs: Long) {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager

            @Suppress("DEPRECATION")
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                "Gavra013:NotifListenerWakeLock"
            )

            // Acquire sa auto-release timeout-om — ne treba ručno release
            wakeLock.acquire(durationMs)

            android.util.Log.d(TAG, "✅ WakeLock acquired za ${durationMs}ms")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "wakeScreen greška: ${e.message}")
        }
    }
}
