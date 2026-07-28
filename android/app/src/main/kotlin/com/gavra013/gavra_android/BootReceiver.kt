package com.gavra013.gavra_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Pokreće background GPS servis posle reboot-a ako je tracking bio aktivan.
 * Koristi isti SharedPreferences fajl kao GavraFcmService (jedan izvor istine).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences(
            GavraFcmService.PREFS_FILE_NAME,
            Context.MODE_PRIVATE,
        )
        val vozacId = prefs.getString(GavraFcmService.KEY_ACTIVE_VOZAC_ID, "") ?: ""
        if (vozacId.isBlank()) return

        android.util.Log.d("GavraBootReceiver", "Restartujem tracking posle reboot-a: vozac=$vozacId")
        val serviceIntent = Intent().setClassName(
            context,
            "id.flutter.flutter_background_service.BackgroundService",
        )
        ContextCompat.startForegroundService(context, serviceIntent)

        // Osiguraj da watchdog radi i posle reboot-a
        TrackingWatchdogWorker.schedule(context)
    }
}
