package com.substancejournal.substance_journal_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

// A copy of the Dart side with no screen, started when the watch asks for something while the app is
// closed. It answers, then shuts itself down after a little while. Everything runs on the main thread.
object BackgroundDart {
    private const val IDLE_MS = 45_000L
    private const val START_TIMEOUT_MS = 20_000L

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private val waiting = mutableListOf<() -> Unit>()
    private var closer: Runnable? = null

    /** Calls [method] on the background Dart and hands its reply (JSON text, or null on failure) to [done]. */
    fun call(context: Context, method: String, done: (String?) -> Unit) {
        main.post {
            val app = context.applicationContext
            ensureStarted(app)
            closer?.let { main.removeCallbacks(it) }
            val run: () -> Unit = {
                val target = channel
                if (target == null) {
                    finish(done, null)
                } else {
                    target.invokeMethod(method, null, object : MethodChannel.Result {
                        override fun success(result: Any?) = finish(done, result as? String)
                        override fun error(code: String, message: String?, details: Any?) = finish(done, null)
                        override fun notImplemented() = finish(done, null)
                    })
                }
            }
            if (ready) {
                run()
            } else {
                waiting.add(run)
                main.postDelayed({
                    if (!ready && waiting.remove(run)) finish(done, null)
                }, START_TIMEOUT_MS)
            }
        }
    }

    private fun finish(done: (String?) -> Unit, value: String?) {
        done(value)
        scheduleClose()
    }

    private fun ensureStarted(app: Context) {
        if (engine != null) return
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val e = FlutterEngine(app)
        val ch = MethodChannel(e.dartExecutor.binaryMessenger, "sj/watchbg")
        ch.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                ready = true
                result.success(null)
                val pending = waiting.toList()
                waiting.clear()
                pending.forEach { it() }
            } else {
                result.notImplemented()
            }
        }
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "package:substance_journal_app/watch_background.dart", "watchMain"),
        )
        engine = e
        channel = ch
    }

    private fun scheduleClose() {
        closer?.let { main.removeCallbacks(it) }
        val r = Runnable {
            channel?.invokeMethod("close", null)
            // Give the journal a moment to close before the engine goes.
            main.postDelayed({
                engine?.destroy()
                engine = null
                channel = null
                ready = false
            }, 1_500L)
        }
        closer = r
        main.postDelayed(r, IDLE_MS)
    }
}
