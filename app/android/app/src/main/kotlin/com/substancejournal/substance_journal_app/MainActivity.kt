package com.substancejournal.substance_journal_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Opens the app, and tells it where to go when it was started from the icon's long-press menu, the
// Quick Settings tile, the home-screen widget or the live-curve notification (all send the extra
// "sj_route"). Also the bridge for the live-curve notification: the app sends it curve data, and it
// asks for the notification permission.
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var initialRoute: String? = null
    private var permissionResult: MethodChannel.Result? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sj/live").setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> result.success(LiveCurveService.update(applicationContext, call.arguments as String))
                "stop" -> {
                    LiveCurveService.stop(applicationContext)
                    result.success(true)
                }
                "permission" -> askForNotifications(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun askForNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        permissionResult?.success(false)
        permissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATIONS) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
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
        private const val REQUEST_NOTIFICATIONS = 4108
    }
}
