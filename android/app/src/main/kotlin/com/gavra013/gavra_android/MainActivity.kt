package com.gavra013.gavra_android

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.NotificationManagerCompat
import com.google.android.gms.common.ConnectionResult as GmsConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native bridges that stay outside firebase_messaging:
 * - vibration
 * - wake screen / notification-listener helpers
 * - Android ID + GMS availability (device identity / token gate)
 *
 * FCM receive/display/tap is handled entirely in Dart via firebase_messaging
 * + flutter_local_notifications (same path as iOS).
 */
class MainActivity : FlutterFragmentActivity() {
    private val VIBRATION_CHANNEL = "com.gavra013.gavra_android/vibration"
    private val WAKELOCK_CHANNEL = "com.gavra013.gavra_android/wakelock"
    private val PUSH_TOKEN_CHANNEL = "com.gavra013.gavra_android/push_token"
    private val TAG = "GavraMainActivity"
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                "isNotifListenerGranted" -> {
                    val packages = NotificationManagerCompat.getEnabledListenerPackages(this)
                    result.success(packages.contains(packageName))
                }
                "openNotifListenerSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message ?: "Cannot open settings", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PUSH_TOKEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGmsAvailable" -> result.success(isGmsAvailable())
                "getAndroidId" -> result.success(getAndroidId())
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIBRATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "vibrate" -> {
                    val duration = call.argument<Int>("duration") ?: 200
                    result.success(vibrate(duration.toLong()))
                }
                "checkVibrator" -> {
                    val vibrator = getVibrator()
                    val hasVibrator = vibrator?.hasVibrator() ?: false
                    val hasAmplitudeControl = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator?.hasAmplitudeControl() ?: false
                    } else {
                        false
                    }
                    result.success(
                        mapOf(
                            "hasVibrator" to hasVibrator,
                            "hasAmplitudeControl" to hasAmplitudeControl,
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "sdkInt" to Build.VERSION.SDK_INT,
                        ),
                    )
                }
                "vibratePattern" -> {
                    @Suppress("UNCHECKED_CAST")
                    val pattern = call.argument<List<Int>>("pattern") ?: listOf(0, 100, 50, 100)
                    result.success(vibratePattern(pattern.map { it.toLong() }.toLongArray()))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun vibrate(duration: Long): Boolean {
        return try {
            val vibrator = getVibrator()
            if (vibrator?.hasVibrator() == true) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(duration)
                }
                true
            } else {
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

    private fun wakeScreen(duration: Long): Boolean {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            releaseWakeLock()
            @Suppress("DEPRECATION")
            wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "Gavra013:NotificationWakeLock",
            )
            wakeLock?.acquire(duration)
            runOnUiThread {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    setShowWhenLocked(true)
                    setTurnScreenOn(true)
                } else {
                    @Suppress("DEPRECATION")
                    window.addFlags(
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                    )
                }
            }
            true
        } catch (e: Exception) {
            android.util.Log.e(TAG, "wakeScreen error: ${e.message}")
            false
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            wakeLock = null
        } catch (e: Exception) {
            android.util.Log.e(TAG, "releaseWakeLock error: ${e.message}")
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
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

    private fun getAndroidId(): String? {
        return try {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            android.util.Log.w(TAG, "getAndroidId failed: ${e.message}")
            null
        }
    }
}
