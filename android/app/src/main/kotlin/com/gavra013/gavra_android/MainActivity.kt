package com.gavra013.gavra_android

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.view.WindowCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Android-only native bridges. Channel names must match AppPlatform in Dart
 * (`lib/config/app_platform.dart`). iOS uses plugins / system APIs only.
 *
 * - wakelock: wakeScreen / releaseWakeLock
 * - push_token: isGmsAvailable / getAndroidId
 *
 * FCM is Dart-only (firebase_messaging) on both platforms.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        // Keep in sync with lib/config/app_platform.dart
        const val WAKELOCK_CHANNEL = "com.gavra013.gavra_android/wakelock"
        const val PUSH_TOKEN_CHANNEL = "com.gavra013.gavra_android/push_token"
        const val TAG = "GavraMainActivity"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    // Android 15 (SDK 35) prikazuje aplikaciju edge-to-edge po difoltu.
    // FlutterActivity nasledjuje android.app.Activity (ne ComponentActivity),
    // pa androidx.activity.enableEdgeToEdge() ekstenzija ovde ne kompajlira.
    // WindowCompat.setDecorFitsSystemWindows(window, false) daje isti efekat
    // (edge-to-edge prikaz) i radi na svakoj Activity/Window, ukljucujuci
    // starije Android verzije (backward-compatible), isto kao Flutter-ova
    // SystemUiMode.edgeToEdge u main.dart - samo primenjeno ranije, pre nego
    // sto Flutter stigne da postavi svoj UI mod (sprecava "skok" native teme).
    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, WAKELOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "wakeScreen" -> {
                    val duration = (call.argument<Int>("duration") ?: 5000).toLong()
                    result.success(wakeScreen(duration))
                }
                "releaseWakeLock" -> {
                    releaseWakeLock()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, PUSH_TOKEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGmsAvailable" -> result.success(isGmsAvailable())
                "getAndroidId" -> result.success(getAndroidId())
                else -> result.notImplemented()
            }
        }
    }

    private fun wakeScreen(duration: Long): Boolean {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            releaseWakeLock()
            @Suppress("DEPRECATION")
            wakeLock =
                powerManager.newWakeLock(
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
            Log.e(TAG, "wakeScreen: ${e.message}")
            false
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (e: Exception) {
            Log.e(TAG, "releaseWakeLock: ${e.message}")
        } finally {
            wakeLock = null
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun isGmsAvailable(): Boolean {
        return try {
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this) ==
                ConnectionResult.SUCCESS
        } catch (e: Exception) {
            Log.w(TAG, "isGmsAvailable: ${e.message}")
            false
        }
    }

    private fun getAndroidId(): String? {
        return try {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            Log.w(TAG, "getAndroidId: ${e.message}")
            null
        }
    }
}
