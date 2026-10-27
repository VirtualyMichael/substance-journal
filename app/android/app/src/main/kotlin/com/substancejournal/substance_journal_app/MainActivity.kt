package com.substancejournal.substance_journal_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Opens the app, and tells it where to go when it was started from the icon's long-press menu, the
// Quick Settings tile or the home-screen widget (all send the extra "sj_route").
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initialRoute: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialRoute = intent?.getStringExtra(ROUTE_EXTRA)
        intent?.removeExtra(ROUTE_EXTRA)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sj/launch").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialRoute" -> {
                        result.success(initialRoute)
                        initialRoute = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val route = intent.getStringExtra(ROUTE_EXTRA) ?: return
        intent.removeExtra(ROUTE_EXTRA)
        channel?.invokeMethod("route", route)
    }

    companion object {
        const val ROUTE_EXTRA = "sj_route"
    }
}
