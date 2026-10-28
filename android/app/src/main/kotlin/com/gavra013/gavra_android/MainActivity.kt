package com.gavra013.gavra_android

import android.content.Context
import android.content.Intent
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
    private var pushChannel: MethodChannel? = null

    // HMS tap na sistemsku notifikaciju stigne kao launch intent sa data
    // payload-om u extras (click_action = FLUTTER_NOTIFICATION_CLICK). Ako
    // Dart strana jos nije spremna, cuva se ovde dok je Dart ne pokupi preko
    // 'consumePushLaunchData'.
    private var pendingPushLaunchData: Map<String, String>? = null

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
        capturePushLaunchData(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        capturePushLaunchData(intent)
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

        pushChannel =
            MethodChannel(messenger, PUSH_TOKEN_CHANNEL).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isGmsAvailable" -> result.success(isGmsAvailable())
                        // HmsInstanceId.getToken() je blokirajuci network poziv — ne sme na UI thread.
                        "getHmsPushToken" ->
                            Thread {
                                result.success(getHmsPushToken())
                            }.start()
                        "getAndroidId" -> result.success(getAndroidId())
                        "consumePushLaunchData" -> {
                            val data = pendingPushLaunchData
                            pendingPushLaunchData = null
                            result.success(data)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    // HMS Push Kit nema callback za tap na notifikaciju — podaci stizu kao
    // extras launch intenta. Extras se brisu iz intenta da se pri recreation
    // activity-ja ne bi obradili dvaput.
    private fun capturePushLaunchData(launchIntent: Intent?) {
        if (launchIntent == null) return
        val extras = launchIntent.extras ?: return
        val keys = extras.keySet()
        val isPushIntent =
            launchIntent.action == "FLUTTER_NOTIFICATION_CLICK" ||
                keys.any { it == "type" || it == "zahtev_id" || it == "event_id" }
        if (!isPushIntent) return

        val data = HashMap<String, String>()
        for (key in keys) {
            extras.get(key)?.let { data[key] = it.toString() }
        }
        extras.clear()
        if (data.isEmpty()) return

        pendingPushLaunchData = data
        val channel = pushChannel ?: return
        channel.invokeMethod(
            "onPushLaunchData",
            data,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // Dart je obradio — skloni iz pending-a da 'consumePushLaunchData'
                    // ne vrati istu poruku dvaput.
                    if (pendingPushLaunchData == data) pendingPushLaunchData = null
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

                override fun notImplemented() {
                    // Dart handler jos nije registrovan — ostaje u pending-u.
                }
            },
        )
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

    private fun getHmsPushToken(): String? {
        return try {
            val appId = getHuaweiAppId()
            if (appId.isNullOrBlank()) {
                Log.w(TAG, "getHmsPushToken: appId missing")
                null
            } else {
                val hmsInstanceIdClass = Class.forName("com.huawei.hms.aaid.HmsInstanceId")
                val getInstanceMethod = hmsInstanceIdClass.getMethod("getInstance", Context::class.java)
                val instance = getInstanceMethod.invoke(null, this)
                val getTokenMethod = hmsInstanceIdClass.getMethod("getToken", String::class.java, String::class.java)
                val token = getTokenMethod.invoke(instance, appId, "HCM") as? String
                token?.trim()?.takeIf { it.isNotEmpty() }
            }
        } catch (e: Exception) {
            Log.w(TAG, "getHmsPushToken: ${e.message}")
            null
        }
    }

    private fun getHuaweiAppId(): String? {
        // Primarno: manifest meta-data (injektovano gradle placeholder-om iz
        // agconnect-services.json). Fallback: AGConnectServicesConfig ako
        // agconnect-core prisutan na classpath-u.
        return try {
            val appInfo =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.getApplicationInfo(
                        packageName,
                        android.content.pm.PackageManager.ApplicationInfoFlags.of(
                            android.content.pm.PackageManager.GET_META_DATA.toLong(),
                        ),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getApplicationInfo(
                        packageName,
                        android.content.pm.PackageManager.GET_META_DATA,
                    )
                }
            val meta = appInfo.metaData?.getString("com.huawei.hms.client.appid")
            val fromMeta = meta?.trim()?.removePrefix("appid=")
            if (!fromMeta.isNullOrEmpty()) {
                fromMeta
            } else {
                appIdFromAgConnect()
            }
        } catch (e: Exception) {
            Log.w(TAG, "getHuaweiAppId: ${e.message}")
            appIdFromAgConnect()
        }
    }

    private fun appIdFromAgConnect(): String? {
        return try {
            val configClass = Class.forName("com.huawei.agconnect.config.AGConnectServicesConfig")
            val fromContext = configClass.getMethod("fromContext", Context::class.java)
            val config = fromContext.invoke(null, this)
            val getString = configClass.getMethod("getString", String::class.java)
            val raw = getString.invoke(config, "client/app_id") as? String
            raw?.trim()?.removePrefix("appid=")?.takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            Log.w(TAG, "appIdFromAgConnect: ${e.message}")
            null
        }
    }
}
