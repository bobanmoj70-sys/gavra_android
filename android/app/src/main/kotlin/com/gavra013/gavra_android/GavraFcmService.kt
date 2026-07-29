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
 * 2. vozac_auto_start_tracking — UVEK (bez obzira na Flutter engine stanje) upisuje "željeno
 *    stanje" (JEDAN IZVOR ISTINE, deljen sa Dart stranom) u nativni SharedPreferences fajl koji
 *    Dart `shared_preferences` paket čita, i pokreće `flutter_background_service`-ov headless
 *    servis (BackgroundService) ako već ne radi. Taj servis (Android background isolate) sam
 *    čita ovo stanje svakih 20s (polling — vidi `v3_background_location_handler.dart`), pa
 *    radi ispravno i kad je već pokrenut za prethodni termin (ne treba mu restart), i kad je
 *    app potpuno ubijena (killed).
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
        const val PREFS_FILE_NAME = "FlutterSharedPreferences"
        // Mora biti identično sa `flutter.` prefiksom koji Dart `shared_preferences` paket
        // koristi za sve ključeve (vidi shared_preferences_legacy.dart `_prefix`).
        private const val FLUTTER_PREFS_PREFIX = "flutter."

        // JEDAN IZVOR ISTINE za "šta bi background tracking trebalo da radi" — moraju biti
        // identični sa `_kKey*` konstantama u `v3_background_location_handler.dart` i
        // `V3VozacLocationTrackingService` (Dart strana).
        const val KEY_ACTIVE_VOZAC_ID = "${FLUTTER_PREFS_PREFIX}bg_active_vozac_id"
        const val KEY_ACTIVE_DATUM_ISO = "${FLUTTER_PREFS_PREFIX}bg_active_datum_iso"
        const val KEY_ACTIVE_GRAD = "${FLUTTER_PREFS_PREFIX}bg_active_grad"
        const val KEY_ACTIVE_VREME = "${FLUTTER_PREFS_PREFIX}bg_active_vreme"
        const val KEY_ACTIVE_STARTED_AT = "${FLUTTER_PREFS_PREFIX}bg_active_started_at"

        /**
         * Normalizuje vreme na HH:mm, identično kao Dart `V3TimeUtils.normalizeToHHmm`.
         * Podržava "08:00", "8:00", "08:00:00", "2026-07-28T08:00:00Z", itd.
         */
        fun normalizeTimeToHHmm(value: String?): String {
            val raw = value?.trim() ?: return ""
            if (raw.isEmpty()) return ""
            val regex = Regex("""([01]?\\d|2[0-3]):([0-5]\\d)(?::[0-5]\\d)?""")
            val match = regex.find(raw) ?: return raw
            val hour = match.groupValues[1].toIntOrNull() ?: return raw
            val minute = match.groupValues[2].toIntOrNull() ?: return raw
            return "%02d:%02d".format(hour, minute)
        }

        /**
         * Normalizuje datum na yyyy-MM-dd, identično kao Dart `V3DateUtils.parseIsoDatePart`
         * za ulazne vrednosti bez eksplicitne TZ konverzije (server šalje Beograd vreme).
         * Podržava "2026-07-28", "2026-07-28T08:00:00Z", itd.
         */
        fun normalizeDateToIso(value: String?): String {
            val raw = value?.trim() ?: return ""
            if (raw.isEmpty()) return ""
            if (Regex("""^\\d{4}-\\d{2}-\\d{2}$""").matches(raw)) return raw
            if (raw.contains("T")) {
                val datePart = raw.substringBefore("T")
                if (Regex("""^\\d{4}-\\d{2}-\\d{2}$""").matches(datePart)) return datePart
            }
            return Regex("""^(\\d{4}-\\d{2}-\\d{2})""").find(raw)?.groupValues?.get(1) ?: ""
        }
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
            val engine = FlutterEngineCache.getInstance().get("main_engine")
            if (engine == null) {
                // App je u background-u bez aktivnog Flutter engine-a (ili killed).
                // Native mora sam da upise zeljeno stanje i pokrene foreground servis.
                writeDesiredTrackingState(data)
                return
            }
            // Flutter engine je aktivan — sve radi Dart handler (jedan izvor istine).
            // Samo prosledi poruku dalje MethodChannel-u ispod.
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
            // vozac_auto_start_tracking nema title/body (data-only push), pa se ovde ništa
            // ne prikazuje za njega — Android sam prikazuje trajnu "GPS Tracking" notifikaciju
            // preko foreground servisa pokrenutog ispod.
            android.util.Log.w(TAG, "Flutter engine nije aktivan, prikazujem nativnu notifikaciju.")
            if (remoteMessage.notification == null && (title.isNotEmpty() || body.isNotEmpty())) {
                showNativeNotification(title, body, type, data)
            }
        }
    }

    /**
     * Upisuje "željeno stanje" tracking-a u nativni SharedPreferences (isti fajl koji Dart
     * `shared_preferences` koristi) i pokreće background GPS servis ako već ne radi.
     *
     * Ovo je JEDINI posao ove funkcije — ne zna i ne treba da zna da li je servis već radio
     * za prethodni termin: Dart background isolate (`v3_background_location_handler.dart`)
     * sam čita ovo stanje svakih 20s i primenjuje razliku (novi vozač/termin), bez obzira da
     * li je servis "restartovan" ili ne. Ovim se eliminiše prethodni bug gde bi drugi termin
     * (dok je prvi još u toku) bio tiho ignorisan jer Android servisni sloj ne restartuje
     * headless Dart engine kad je već pokrenut.
     */
    private fun writeDesiredTrackingState(data: Map<String, String>) {
        val vozacId = (data["v3_auth_id"] ?: data["vozac_id"] ?: "").trim()
        val grad = (data["grad"] ?: "").trim().uppercase()
        val vreme = normalizeTimeToHHmm(data["vreme"])
        val datumIso = normalizeDateToIso(data["datum"])

        android.util.Log.d(TAG, "writeDesiredTrackingState: raw vozac=$vozacId grad=$grad vreme=$vreme datum=$datumIso")

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

            // started_at se resetuje na svaki novi vozac_auto_start_tracking push — svaki push
            // predstavlja novu sesiju trackinga. Ovo je usklađeno sa Dart stranom
            // (writeDesiredStateFromPayload/startFromPayload uvek postavljaju _trackingStartedAt
            // na DateTime.now()).
            val editor = prefs.edit()
                .putString(KEY_ACTIVE_VOZAC_ID, vozacId)
                .putString(KEY_ACTIVE_DATUM_ISO, datumIso)
                .putString(KEY_ACTIVE_GRAD, grad)
                .putString(KEY_ACTIVE_VREME, vreme)
                .putLong(KEY_ACTIVE_STARTED_AT, System.currentTimeMillis())
            editor.commit() // sinhron upis da bi background servis odmah video stanje

            android.util.Log.d(
                TAG,
                "Željeno stanje upisano: vozac=$vozacId grad=$grad vreme=$vreme datum=$datumIso",
            )

            // Verifikacija upisa
            val verifyVozacId = prefs.getString(KEY_ACTIVE_VOZAC_ID, "") ?: ""
            android.util.Log.d(TAG, "Verifikacija Prefs: vozacId=$verifyVozacId")

            // Pokreni background service (foreground GPS servis) ako već ne radi — headless,
            // bez potrebe za MainActivity/main_engine. Ako već radi (prati prethodni termin),
            // ovaj poziv je no-op na Android servisnom sloju, ALI Dart polling ionako pokupi
            // novo stanje na sledećem tick-u (do 20s), pa nema potrebe da se servis restartuje.
            val serviceIntent = Intent()
            serviceIntent.setClassName(
                applicationContext,
                "id.flutter.flutter_background_service.BackgroundService",
            )
            android.util.Log.d(TAG, "Pokrećem background service")
            ContextCompat.startForegroundService(applicationContext, serviceIntent)

            // Osiguraj periodično ponovno pokretanje servisa ako ga OS ubije
            TrackingWatchdogWorker.schedule(applicationContext)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "writeDesiredTrackingState greška: ${e.message}", e)
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
