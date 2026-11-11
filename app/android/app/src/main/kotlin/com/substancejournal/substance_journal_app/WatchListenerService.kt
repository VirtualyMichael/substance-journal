package com.substancejournal.substance_journal_app

import android.os.Handler
import android.os.Looper
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

// Receives the watch's requests: "/same" logs the last dose again, "/refresh" asks for fresh data.
// If the app is open the request goes to it (so its screens update too); otherwise a copy of the
// Dart side with no screen answers.
class WatchListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        val method = when (event.path) {
            "/same" -> "same"
            "/refresh" -> "snapshot"
            else -> return super.onMessageReceived(event)
        }
        val node = event.sourceNodeId
        val app = applicationContext
        Handler(Looper.getMainLooper()).post {
            fun finish(json: String?) {
                var ok = false
                var message = "The phone could not be reached. Open the app on it and try again."
                if (json != null) {
                    try {
                        val parsed = JSONObject(json)
                        ok = parsed.optBoolean("ok", false)
                        message = if (parsed.isNull("message")) (if (ok) "Updated" else message) else parsed.getString("message")
                        parsed.optString("snapshot").takeIf { it.isNotEmpty() }?.let { WatchBridge.push(app, it) }
                    } catch (_: Exception) {
                        // Fall through with the generic message.
                    }
                }
                val reply = JSONObject().put("ok", ok).put("message", message).put("for", method)
                WatchBridge.reply(app, node, reply.toString())
            }

            fun background() = BackgroundDart.call(app, method) { finish(it) }

            val foreground = MainActivity.foreground
            if (foreground == null) {
                background()
            } else {
                foreground.invokeMethod(method, null, object : MethodChannel.Result {
                    override fun success(result: Any?) = finish(result as? String)
                    override fun error(code: String, message: String?, details: Any?) = background()
                    override fun notImplemented() = background()
                })
            }
        }
    }
}
