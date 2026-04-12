package com.gavra013.gavra_android

import android.content.Intent
import android.util.Log
import com.huawei.hms.push.HmsMessageService
import com.huawei.hms.push.RemoteMessage
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngineCache

class HmsPushService : HmsMessageService() {
    companion object {
        private const val TAG = "HmsPushService"
        private const val HMS_PUSH_CHANNEL = "com.gavra013.gavra_android/hms_push_data"
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "✅ HMS new token received: ${token.take(16)}…")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val data = message.dataOfMap
        Log.d(TAG, "📩 HMS message received. data=$data")

        if (data.isNullOrEmpty()) return

        // Pokušaj da pošalješ data flutter enginu ako je aktivan
        val engine = FlutterEngineCache.getInstance().get("main_engine")
        if (engine != null) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, HMS_PUSH_CHANNEL)
            engine.dartExecutor.binaryMessenger.let {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    channel.invokeMethod("onPushData", data)
                    Log.d(TAG, "✅ HMS push data sent to Flutter: type=${data["type"]}")
                }
            }
        } else {
            // App nije aktivna — sačuvaj u Intent i pokreni app
            Log.d(TAG, "⚠️ Flutter engine nije aktivan, prosleđujem broadcast")
            val intent = Intent(applicationContext, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                data.forEach { (k, v) -> putExtra(k, v) }
                putExtra("_hms_push_data", true)
            }
            applicationContext.startActivity(intent)
        }
    }
}