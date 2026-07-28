package com.gavra013.gavra_android

import android.content.Context
import android.content.Intent
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Periodično proverava da li postoji aktivno "željeno stanje" tracking-a.
 * Ako postoji, pokreće (ili ponovo pokreće) foreground GPS servis.
 * Ovo je zaštita od agresivnih OEM battery manager-a koji ubijaju servis
 * usred vožnje (Huawei/Xiaomi/Samsung).
 */
class TrackingWatchdogWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(
            GavraFcmService.PREFS_FILE_NAME,
            Context.MODE_PRIVATE,
        )
        val vozacId = prefs.getString(GavraFcmService.KEY_ACTIVE_VOZAC_ID, "") ?: ""
        if (vozacId.isBlank()) {
            return Result.success()
        }

        android.util.Log.d("GavraWatchdog", "Pokrećem tracking servis za vozac=$vozacId")
        val intent = Intent().setClassName(
            applicationContext,
            "id.flutter.flutter_background_service.BackgroundService",
        )
        androidx.core.content.ContextCompat.startForegroundService(applicationContext, intent)
        return Result.success()
    }

    companion object {
        private const val WORK_NAME = "gavra_tracking_watchdog"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<TrackingWatchdogWorker>(
                15,
                TimeUnit.MINUTES,
            ).build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }
    }
}
