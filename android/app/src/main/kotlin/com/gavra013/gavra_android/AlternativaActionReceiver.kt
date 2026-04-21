package com.gavra013.gavra_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class AlternativaActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_ALTERNATIVA = "com.gavra013.gavra_android.ALTERNATIVA_ACTION"
        const val EXTRA_ZAHTEV_ID = "zahtev_id"
        const val EXTRA_ACTION_ID = "action_id"

        private const val TAG = "AlternativaActionReceiver"
        private const val FEEDBACK_CHANNEL_ID = "gavra_push_v2"
        private const val FEEDBACK_CHANNEL_NAME = "Gavra obaveštenja"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        Executors.newSingleThreadExecutor().execute {
            try {
                val actionId = intent.getStringExtra(EXTRA_ACTION_ID).orEmpty().trim()
                val zahtevId = intent.getStringExtra(EXTRA_ZAHTEV_ID).orEmpty().trim()

                if (zahtevId.isEmpty() || actionId.isEmpty()) {
                    showFeedback(
                        context,
                        "⚠️ Akcija nije izvršena",
                        "Nedostaje zahtev ili akcija.",
                    )
                    return@execute
                }

                val env = loadEnv(context)
                val supabaseUrl = env["SUPABASE_URL"].orEmpty().trim().trimEnd('/')
                val anonKey = env["SUPABASE_ANON_KEY"].orEmpty().trim()

                if (supabaseUrl.isEmpty() || anonKey.isEmpty()) {
                    android.util.Log.e(TAG, "Nedostaje SUPABASE_URL ili SUPABASE_ANON_KEY u .env")
                    showFeedback(
                        context,
                        "⚠️ Greška",
                        "Nedostaje konfiguracija aplikacije.",
                    )
                    return@execute
                }

                val result = invokeAlternativaEdge(
                    supabaseUrl = supabaseUrl,
                    anonKey = anonKey,
                    zahtevId = zahtevId,
                    actionId = actionId,
                )

                if (!result.ok) {
                    val msg = when (result.reason) {
                        "selected_slot_full" -> "Izabrani termin se u međuvremenu popunio."
                        "zahtev_not_in_alternativa" -> "Zahtev više nije u statusu alternativa."
                        else -> "Akcija nije uspela: ${result.reason}"
                    }
                    showFeedback(context, "⚠️ Akcija nije uspela", msg)
                    return@execute
                }

                if (actionId == "reject") {
                    showFeedback(context, "❌ Alternativa odbijena", "Zahtev je postavljen na odbijeno.")
                } else {
                    val selected = result.selectedTime?.trim().orEmpty()
                    val msg = if (selected.isNotEmpty()) {
                        "Prihvaćen termin: $selected"
                    } else {
                        "Alternativa je prihvaćena."
                    }
                    showFeedback(context, "✅ Alternativa prihvaćena", msg)
                }
            } catch (error: Exception) {
                android.util.Log.e(TAG, "Greška u action receiver-u", error)
                showFeedback(
                    context,
                    "⚠️ Greška",
                    "Akcija nije uspela: ${error.message ?: "Unknown error"}",
                )
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun loadEnv(context: Context): Map<String, String> {
        val result = mutableMapOf<String, String>()
        context.assets.open(".env").use { input ->
            BufferedReader(InputStreamReader(input)).useLines { lines ->
                lines.forEach { rawLine ->
                    val line = rawLine.trim()
                    if (line.isEmpty() || line.startsWith("#")) return@forEach
                    val idx = line.indexOf('=')
                    if (idx <= 0) return@forEach
                    val key = line.substring(0, idx).trim()
                    val valueRaw = line.substring(idx + 1).trim()
                    val value = valueRaw.removeSurrounding("\"").removeSurrounding("'")
                    if (key.isNotEmpty()) {
                        result[key] = value
                    }
                }
            }
        }
        return result
    }

    private fun invokeAlternativaEdge(
        supabaseUrl: String,
        anonKey: String,
        zahtevId: String,
        actionId: String,
    ): EdgeResult {
        val url = URL("$supabaseUrl/functions/v1/v3-alternativa-action")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 10_000
            readTimeout = 15_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("apikey", anonKey)
            setRequestProperty("Authorization", "Bearer $anonKey")
        }

        val body = JSONObject()
            .put("zahtev_id", zahtevId)
            .put("action", actionId)
            .toString()

        BufferedWriter(OutputStreamWriter(conn.outputStream, Charsets.UTF_8)).use { writer ->
            writer.write(body)
            writer.flush()
        }

        val statusCode = conn.responseCode
        val responseText = try {
            BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { it.readText() }
        } catch (_: Exception) {
            BufferedReader(InputStreamReader(conn.errorStream, Charsets.UTF_8)).use { it.readText() }
        }

        if (responseText.isBlank()) {
            return EdgeResult(
                ok = false,
                reason = "empty_response_status_$statusCode",
                selectedTime = null,
            )
        }

        val json = JSONObject(responseText)
        val ok = json.optBoolean("ok", false)
        val reason = json.optString("reason", if (ok) "ok" else "unknown_error")
        val selected = json.optString("selected_time", "")

        return EdgeResult(
            ok = ok,
            reason = reason,
            selectedTime = selected.ifBlank { null },
        )
    }

    private fun showFeedback(context: Context, title: String, body: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            FEEDBACK_CHANNEL_ID,
            FEEDBACK_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            enableVibration(true)
            enableLights(true)
        }
        notificationManager.createNotificationChannel(channel)

        val notification = NotificationCompat.Builder(context, FEEDBACK_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(System.currentTimeMillis().rem(100000).toInt(), notification)
    }

    data class EdgeResult(
        val ok: Boolean,
        val reason: String,
        val selectedTime: String?,
    )
}
