package com.gavra013.gavra_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Native FCM handler.
 *
 * Odgovornosti:
 * 1. onMessageReceived — app je u FOREGROUND-u ili BACKGROUND-u ali running:
 *    → ako je Flutter engine aktivan (foreground): prosleđuje data Flutteru via MethodChannel
 *      → Flutter prikazuje lokalnu notifikaciju + budi ekran
 *    → ako engine NIJE aktivan (background, ali ne killed): prikazuje nativnu Android notifikaciju
 *      direktno iz Kotlin-a bez Fluttera
 *
 * 2. onNewToken — FCM token se regenerisao:
 *    → prosleđuje novi token Flutteru da se sync-uje sa Supabase
 *
 * NAPOMENA: Kada je app KILLED, Android OS sam prikazuje notifikaciju
 * iz `notification` polja — ovaj servis se ne poziva za to.
 * Tap na tu notifikaciju otvara MainActivity sa Intent extras-ima.
 */
class GavraFcmService : FirebaseMessagingService() {

    companion object {
        const val FCM_CHANNEL = "com.gavra013.gavra_android/fcm"
        private const val NOTIF_CHANNEL_ID = "gavra_push_v2"
        private const val NOTIF_CHANNEL_NAME = "Gavra obaveštenja"
        private const val TAG = "GavraFcmService"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        android.util.Log.d(TAG, "FCM onMessageReceived from: ${remoteMessage.from}")

        val data = remoteMessage.data
        val title = remoteMessage.notification?.title ?: data["title"] ?: ""
        val body = remoteMessage.notification?.body ?: data["body"] ?: ""
        val type = data["type"] ?: ""

        android.util.Log.d(TAG, "FCM type=$type title=$title")

        // Prosledi Flutteru via MethodChannel (radi samo ako je engine aktivan)
        val engine = FlutterEngineCache.getInstance().get("main_engine")
        if (engine != null) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, FCM_CHANNEL)
            // Mora se pozvati na main thread-u
            val handler = android.os.Handler(android.os.Looper.getMainLooper())
            handler.post {
                channel.invokeMethod(
                    "onMessage",
                    mapOf(
                        "title" to title,
                        "body" to body,
                        "type" to type,
                        "data" to data,
                    ),
                )
            }
        } else {
            // Engine nije aktivan (background bez keširanog engine-a).
            // Prikaži nativnu Android notifikaciju samo za data-only poruke.
            // Za poruke sa `notification` payload-om Android već prikazuje system notifikaciju.
            android.util.Log.w(TAG, "Flutter engine nije aktivan, prikazujem nativnu notifikaciju.")
            if (remoteMessage.notification == null && (title.isNotEmpty() || body.isNotEmpty())) {
                showNativeNotification(title, body, type, data)
            }
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        android.util.Log.d(TAG, "FCM token refresh: ${token.take(16)}…")

        // Prosledi novi token Flutteru da se sync-uje sa Supabase
        val engine = FlutterEngineCache.getInstance().get("main_engine")
        if (engine != null) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, FCM_CHANNEL)
            val handler = android.os.Handler(android.os.Looper.getMainLooper())
            handler.post {
                channel.invokeMethod("onTokenRefresh", mapOf("token" to token))
            }
        }
    }

    /**
     * Prikazuje nativnu Android notifikaciju kada Flutter engine nije aktivan (background).
     * Tap na notifikaciju otvara MainActivity sa FCM data kao extras — isti tok kao KILLED state.
     */
    private fun showNativeNotification(
        title: String,
        body: String,
        type: String,
        data: Map<String, String>,
    ) {
        val notifManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Kreiraj kanal (idempotentno — bezopasno ako već postoji)
        val channel = NotificationChannel(
            NOTIF_CHANNEL_ID,
            NOTIF_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            enableVibration(true)
            enableLights(true)
        }
        notifManager.createNotificationChannel(channel)

        // Intent koji otvara MainActivity sa FCM data kao extras.
        // Dodajemo "google.message_id" marker da extractFcmData() u MainActivity prepozna ovo kao FCM tap.
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("google.message_id", "gavra_bg_${System.currentTimeMillis()}")
            putExtra("fcm_type", type)
            data.forEach { (k, v) -> putExtra(k, v) }
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            System.currentTimeMillis().toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notifId = System.currentTimeMillis().rem(100000).toInt()
        val notification = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notifManager.notify(notifId, notification)
        android.util.Log.d(TAG, "Nativna notifikacija prikazana id=$notifId type=$type")
    }
}
