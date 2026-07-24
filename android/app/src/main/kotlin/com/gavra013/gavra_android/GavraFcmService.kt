package com.gavra013.gavra_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
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
 * 2. vozac_auto_start_tracking — UVEK (bez obzira na Flutter engine stanje) upisuje payload
 *    u nativni SharedPreferences fajl koji Dart `shared_preferences` paket čita, i direktno
 *    pokreće `flutter_background_service`-ov headless servis (BackgroundService), koji sadrži
 *    sopstveni, potpuno nezavisan Flutter engine (odvojen od `main_engine` cache-a). Tako se
 *    tracking pokreće automatski i kad je app potpuno ubijena (killed), bez potrebe za tap-om.
 *
 * 3. onNewToken — FCM token se regenerisao:
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
        private const val ALTERNATIVA_CHANNEL_ID = "gavra_alternativa"
        private const val ALTERNATIVA_CHANNEL_NAME = "Alternativa termina"
        private const val TAG = "GavraFcmService"

        // Mora biti identično sa `LegacySharedPreferencesPlugin.SHARED_PREFERENCES_NAME`
        // (shared_preferences_android paket) — isti fajl koji Dart `SharedPreferences.getInstance()` čita.
        private const val PREFS_FILE_NAME = "FlutterSharedPreferences"
        // Mora biti identično sa `flutter.` prefiksom koji Dart `shared_preferences` paket
        // koristi za sve ključeve (vidi shared_preferences_legacy.dart `_prefix`).
        private const val FLUTTER_PREFS_PREFIX = "flutter."

        // Ključevi za native→Dart payload za auto-start tracking (čita ih background isolate
        // u v3_background_location_handler.dart pri pokretanju headless servisa).
        private const val KEY_PENDING_VOZAC_ID = "${FLUTTER_PREFS_PREFIX}bg_pending_vozac_id"
        private const val KEY_PENDING_DATUM_ISO = "${FLUTTER_PREFS_PREFIX}bg_pending_datum_iso"
        private const val KEY_PENDING_GRAD = "${FLUTTER_PREFS_PREFIX}bg_pending_grad"
        private const val KEY_PENDING_VREME = "${FLUTTER_PREFS_PREFIX}bg_pending_vreme"
        private const val KEY_PENDING_TIMESTAMP = "${FLUTTER_PREFS_PREFIX}bg_pending_timestamp"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        android.util.Log.d(TAG, "FCM onMessageReceived from: ${remoteMessage.from}")

        val data = remoteMessage.data
        val title = remoteMessage.notification?.title ?: data["title"] ?: ""
        val body = remoteMessage.notification?.body ?: data["body"] ?: ""
        val type = data["type"] ?: ""

        android.util.Log.d(TAG, "FCM type=$type title=$title")

        if (type == "v3_alternativa") {
            showAlternativaNotification(
                title = if (title.isNotEmpty()) title else "Informacija o dostupnosti termina",
                body = if (body.isNotEmpty()) body else "Trenutno nema slobodnih mesta u željenom terminu.",
                data = data,
            )
            return
        }

        if (type == "vozac_auto_start_tracking") {
            handleAutoStartTracking(data)
            return
        }

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

    /**
     * Pokreće GPS tracking automatski, bez obzira na Flutter engine stanje.
     *
     * Zašto ovo radi i kad je app potpuno ubijena: umesto da se osloni na `main_engine`
     * cache (koji je null kad je Activity/Flutter engine mrtav), ovaj metod:
     *  1) Upisuje payload direktno u nativni `FlutterSharedPreferences` fajl (isti koji
     *     `package:shared_preferences` koristi na Dart strani), sa `flutter.` prefiksom.
     *  2) Pokreće `id.flutter.flutter_background_service.BackgroundService` — koji ima
     *     SOPSTVENI headless Flutter engine, potpuno nezavisan od MainActivity/main_engine,
     *     konfigurisan preko `flutter_background_service`-ovog `background_handle` (upisan
     *     ranije u main isolate-u pri `service.configure()`).
     *  3) `onBackgroundServiceStart` (Dart) pri startu čita ovaj payload i sam pokreće
     *     activateSlot + GPS tracking — bez tap-a, bez UI-ja, bez `main_engine`.
     *
     * Ako je Flutter engine ipak aktivan (foreground), ovo je samo redundantno-bezbedan
     * fallback — postojeći main isolate flow (`_autoStartVozacTrackingFromPush`) i dalje radi
     * normalno i preko `onMessage` MethodChannel-a, a `start()` u
     * `V3VozacLocationTrackingService` je idempotentan za istog vozača.
     */
    private fun handleAutoStartTracking(data: Map<String, String>) {
        val vozacId = (data["v3_auth_id"] ?: data["vozac_id"] ?: "").trim()
        val grad = (data["grad"] ?: "").trim().uppercase()
        val vreme = (data["vreme"] ?: "").trim()
        val datumIso = (data["datum"] ?: "").trim()

        if (vozacId.isEmpty() || grad.isEmpty() || vreme.isEmpty() || datumIso.isEmpty()) {
            android.util.Log.w(
                TAG,
                "vozac_auto_start_tracking: nedostaju podaci vozac=$vozacId grad=$grad vreme=$vreme datum=$datumIso",
            )
            return
        }

        try {
            val prefs: SharedPreferences = applicationContext.getSharedPreferences(
                PREFS_FILE_NAME,
                Context.MODE_PRIVATE,
            )
            prefs.edit()
                .putString(KEY_PENDING_VOZAC_ID, vozacId)
                .putString(KEY_PENDING_DATUM_ISO, datumIso)
                .putString(KEY_PENDING_GRAD, grad)
                .putString(KEY_PENDING_VREME, vreme)
                .putLong(KEY_PENDING_TIMESTAMP, System.currentTimeMillis())
                .apply()

            android.util.Log.d(
                TAG,
                "Auto-start payload upisan u native prefs: vozac=$vozacId grad=$grad vreme=$vreme datum=$datumIso",
            )

            // Direktno pokreni background service (foreground GPS servis) — headless,
            // bez potrebe za MainActivity/main_engine. Isti servis koji koristi
            // `flutter_background_service`, samo pokrenut iz native koda umesto Dart-a.
            val serviceIntent = Intent()
            serviceIntent.setClassName(
                applicationContext,
                "id.flutter.flutter_background_service.BackgroundService",
            )
            ContextCompat.startForegroundService(applicationContext, serviceIntent)

            android.util.Log.d(TAG, "BackgroundService pokrenut direktno iz GavraFcmService (auto-start tracking)")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "handleAutoStartTracking greška: ${e.message}", e)
        }

        // Ako je Flutter main engine ipak aktivan (foreground), prosledi i njemu —
        // main isolate flow ostaje kao redundantan/idempotentan fallback.
        val engine = FlutterEngineCache.getInstance().get("main_engine")
        if (engine != null) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, FCM_CHANNEL)
            val handler = android.os.Handler(android.os.Looper.getMainLooper())
            handler.post {
                channel.invokeMethod(
                    "onMessage",
                    mapOf(
                        "title" to "",
                        "body" to "",
                        "type" to "vozac_auto_start_tracking",
                        "data" to data,
                    ),
                )
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

    private fun showAlternativaNotification(
        title: String,
        body: String,
        data: Map<String, String>,
    ) {
        val zahtevId = data["zahtev_id"].orEmpty().trim()
        val altPre = data["alt_pre"].orEmpty().trim()
        val altPosle = data["alt_posle"].orEmpty().trim()

        if (zahtevId.isEmpty()) {
            android.util.Log.w(TAG, "v3_alternativa bez zahtev_id, fallback na regular notifikaciju")
            showNativeNotification(title, body, "v3_alternativa", data)
            return
        }

        val notifManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            ALTERNATIVA_CHANNEL_ID,
            ALTERNATIVA_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            enableVibration(true)
            enableLights(true)
        }
        notifManager.createNotificationChannel(channel)

        val builder = NotificationCompat.Builder(this, ALTERNATIVA_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)

        if (altPre.isNotEmpty()) {
            builder.addAction(
                0,
                "✅ $altPre",
                buildAlternativaActionIntent(zahtevId, "accept_pre", 101),
            )
        }

        if (altPosle.isNotEmpty()) {
            builder.addAction(
                0,
                "✅ $altPosle",
                buildAlternativaActionIntent(zahtevId, "accept_posle", 102),
            )
        }

        builder.addAction(
            0,
            "❌ Odbij",
            buildAlternativaActionIntent(zahtevId, "reject", 103),
        )

        val notifId = System.currentTimeMillis().rem(100000).toInt()
        notifManager.notify(notifId, builder.build())
        android.util.Log.d(TAG, "Alternativa notifikacija prikazana id=$notifId zahtevId=$zahtevId")
    }

    private fun buildAlternativaActionIntent(
        zahtevId: String,
        actionId: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(this, AlternativaActionReceiver::class.java).apply {
            action = AlternativaActionReceiver.ACTION_ALTERNATIVA
            putExtra(AlternativaActionReceiver.EXTRA_ZAHTEV_ID, zahtevId)
            putExtra(AlternativaActionReceiver.EXTRA_ACTION_ID, actionId)
        }

        return PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
