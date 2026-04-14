package com.gavra013.gavra_android

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import com.google.android.gms.common.ConnectionResult as GmsConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val VIBRATION_CHANNEL = "com.gavra013.gavra_android/vibration"
    private val WAKELOCK_CHANNEL = "com.gavra013.gavra_android/wakelock"
    private val PUSH_TOKEN_CHANNEL = "com.gavra013.gavra_android/push_token"
    private val TAG = "GavraMainActivity"
    private var wakeLock: PowerManager.WakeLock? = null
    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Registruj engine u cache
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)
        
        // WakeLock Channel - za paljenje ekrana na notifikaciju
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKELOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "wakeScreen" -> {
                    val duration = call.argument<Int>("duration") ?: 5000
                    val success = wakeScreen(duration.toLong())
                    android.util.Log.d(TAG, "wakeScreen($duration) called, success=$success")
                    result.success(success)
                }
                "releaseWakeLock" -> {
                    releaseWakeLock()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Push token bridge (FCM)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PUSH_TOKEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGmsAvailable" -> {
                    result.success(isGmsAvailable())
                }
                "getFcmToken" -> {
                    ioExecutor.execute {
                        try {
                            val token = getFcmToken()
                            runOnUiThread {
                                result.success(token)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("FCM_TOKEN_ERROR", e.message ?: "Unknown FCM token error", null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Vibration Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIBRATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "vibrate" -> {
                    val duration = call.argument<Int>("duration") ?: 200
                    val success = vibrate(duration.toLong())
                    android.util.Log.d(TAG, "vibrate($duration) called, success=$success")
                    result.success(success)
                }
                "checkVibrator" -> {
                    val vibrator = getVibrator()
                    val hasVibrator = vibrator?.hasVibrator() ?: false
                    val hasAmplitudeControl = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator?.hasAmplitudeControl() ?: false
                    } else false
                    val info = mapOf(
                        "hasVibrator" to hasVibrator,
                        "hasAmplitudeControl" to hasAmplitudeControl,
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "sdkInt" to Build.VERSION.SDK_INT
                    )
                    android.util.Log.d(TAG, "checkVibrator: $info")
                    result.success(info)
                }
                "vibratePattern" -> {
                    @Suppress("UNCHECKED_CAST")
                    val pattern = call.argument<List<Int>>("pattern") ?: listOf(0, 100, 50, 100)
                    val success = vibratePattern(pattern.map { it.toLong() }.toLongArray())
                    android.util.Log.d(TAG, "vibratePattern called, success=$success")
                    result.success(success)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun vibrate(duration: Long): Boolean {
        return try {
            val vibrator = getVibrator()
            android.util.Log.d(TAG, "vibrate: vibrator=$vibrator, hasVibrator=${vibrator?.hasVibrator()}")
            if (vibrator?.hasVibrator() == true) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(duration)
                }
                true
            } else {
                android.util.Log.w(TAG, "vibrate: No vibrator available!")
                false
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "vibrate error: ${e.message}")
            false
        }
    }

    private fun vibratePattern(pattern: LongArray): Boolean {
        return try {
            val vibrator = getVibrator()
            if (vibrator?.hasVibrator() == true) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(pattern, -1)
                }
                true
            } else {
                false
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "vibratePattern error: ${e.message}")
            false
        }
    }

    private fun getVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    /**
     * Pali ekran kada stigne notifikacija
     * Koristi WakeLock za buđenje uređaja iz sleep mode-a
     */
    private fun wakeScreen(duration: Long): Boolean {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            
            // Oslobodi prethodni WakeLock ako postoji
            releaseWakeLock()
            
            // Kreiraj novi WakeLock sa ACQUIRE_CAUSES_WAKEUP flag-om
            @Suppress("DEPRECATION")
            wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or 
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "Gavra013:NotificationWakeLock"
            )
            
            // Acquire sa timeout-om
            wakeLock?.acquire(duration)
            
            // Takođe postavi window flags za prikaz preko lock screen-a
            runOnUiThread {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    setShowWhenLocked(true)
                    setTurnScreenOn(true)
                } else {
                    @Suppress("DEPRECATION")
                    window.addFlags(
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    )
                }
            }
            
            android.util.Log.d(TAG, "WakeLock acquired for ${duration}ms")
            true
        } catch (e: Exception) {
            android.util.Log.e(TAG, "wakeScreen error: ${e.message}")
            false
        }
    }

    /**
     * Oslobađa WakeLock
     */
    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                android.util.Log.d(TAG, "WakeLock released")
            }
            wakeLock = null
        } catch (e: Exception) {
            android.util.Log.e(TAG, "releaseWakeLock error: ${e.message}")
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private fun isGmsAvailable(): Boolean {
        return try {
            val status = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this)
            status == GmsConnectionResult.SUCCESS
        } catch (e: Exception) {
            android.util.Log.w(TAG, "isGmsAvailable failed: ${e.message}")
            false
        }
    }

    private fun getFcmToken(): String {
        if (!isGmsAvailable()) {
            throw IllegalStateException("Google Play Services not available")
        }

        if (FirebaseApp.getApps(this).isEmpty()) {
            FirebaseApp.initializeApp(this) ?: throw IllegalStateException("FirebaseApp is not initialized")
        }

        val task = FirebaseMessaging.getInstance().token
        val token = com.google.android.gms.tasks.Tasks.await(task)
        if (token.isNullOrBlank()) {
            throw IllegalStateException("FCM token is empty")
        }
        android.util.Log.d(TAG, "✅ FCM token fetched: ${token.take(16)}…")
        return token
    }
}
