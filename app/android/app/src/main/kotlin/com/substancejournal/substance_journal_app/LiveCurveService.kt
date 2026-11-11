package com.substancejournal.substance_journal_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.KeyguardManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Locale

// The persistent "live curve" notification. The app sends the curve data (JSON, see live_curve.dart);
// this service keeps the notification up and redraws it every minute so the "now" line and the BAC
// keep moving even with the app closed, then removes itself when nothing is active any more.
//
// Unlocked, the notification names each substance in its line's colour. Whenever the screen is off or
// the phone is locked it posts the lock-screen version instead: the same graph and the BAC figure, with
// no names (done here, because Android would otherwise show full content if the person's lock screen
// settings allow sensitive content). Android's own public version covers the hidden-content setting.
class LiveCurveService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            if (!refresh()) {
                shutDown()
            } else {
                handler.postDelayed(this, 60_000)
            }
        }
    }
    private val refreshReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!refresh()) shutDown()
        }
    }

    // The screen turning off or on and the phone being unlocked change which version to show.
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!refresh()) shutDown()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        // Standard importance (so Android is willing to show it on the lock screen, which it skips for
        // "silent" notifications) but with no sound, vibration or light, so it never interrupts.
        nm.deleteNotificationChannel("live_curve")
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Live curve", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "A graph of your current estimated curve while something is active"
                setSound(null, null)
                enableVibration(false)
                enableLights(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
        ContextCompat.registerReceiver(this, refreshReceiver, IntentFilter(ACTION_REFRESH), ContextCompat.RECEIVER_NOT_EXPORTED)
        val screen = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        ContextCompat.registerReceiver(this, screenReceiver, screen, ContextCompat.RECEIVER_EXPORTED)
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            shutDown()
            return START_NOT_STICKY
        }
        val data = CurveRenderer.parse(load(this))
        if (data == null || System.currentTimeMillis() > data.endsAt) {
            // startForeground is still owed after startForegroundService, so show something briefly.
            startForeground(ID, placeholder())
            shutDown()
            return START_NOT_STICKY
        }
        val notification = build(data)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID, notification)
        }
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, 60_000)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        try {
            unregisterReceiver(refreshReceiver)
            unregisterReceiver(screenReceiver)
        } catch (e: IllegalArgumentException) {
            // Already gone.
        }
        running = false
        super.onDestroy()
    }

    private fun shutDown() {
        handler.removeCallbacks(tick)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun refresh(): Boolean {
        val data = CurveRenderer.parse(load(this)) ?: return false
        if (System.currentTimeMillis() > data.endsAt) return false
        getSystemService(NotificationManager::class.java).notify(ID, build(data))
        return true
    }

    private fun placeholder(): Notification =
        NotificationCompat.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_stat_curve).setContentTitle("Substance Journal").build()

    private fun route(route: String, code: Int): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = "sj.live.$route"
            putExtra(MainActivity.ROUTE_EXTRA, route)
            putExtra(MainActivity.TOKEN_EXTRA, MainActivity.routeToken(this@LiveCurveService))
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        return PendingIntent.getActivity(this, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun views(layout: Int, graph: android.graphics.Bitmap, title: CharSequence, text: CharSequence): RemoteViews =
        RemoteViews(packageName, layout).apply {
            setImageViewBitmap(R.id.graph, graph)
            setTextViewText(R.id.title, title)
            setTextViewText(R.id.text, text)
        }

    // True while the lock screen (or a dark screen that is about to become it) could be showing this.
    private fun hideNames(): Boolean {
        val locked = getSystemService(KeyguardManager::class.java).isKeyguardLocked
        val interactive = getSystemService(PowerManager::class.java).isInteractive
        return locked || !interactive
    }

    private fun build(data: CurveRenderer.Data): Notification {
        val now = System.currentTimeMillis()
        val hidden = hideNames()
        val bac = data.bacAt(now)
        val bacText = if (bac == null) "" else String.format(Locale.US, "BAC about %.3f%% (estimate)", bac)
        val subtitle = if (bacText.isEmpty()) "Estimated curve, not a measurement" else bacText

        // Names, each in its line's colour.
        val names = SpannableStringBuilder()
        data.lines.forEachIndexed { i, line ->
            if (i > 0) names.append("  ")
            val start = names.length
            names.append(line.name)
            names.setSpan(ForegroundColorSpan(line.color), start, names.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }

        val small = views(R.layout.notification_curve, CurveRenderer.draw(data, now, 640, 80, legend = false), if (hidden) "Substance Journal" else names, subtitle)
        val big = views(R.layout.notification_curve_big, CurveRenderer.draw(data, now, 640, 300, legend = !hidden), if (hidden) "Substance Journal" else names, subtitle)

        // The lock-screen version: the graph and the BAC figure, no names.
        val publicSmall = views(R.layout.notification_curve, CurveRenderer.draw(data, now, 640, 80, legend = false), "Substance Journal", subtitle)
        val publicBig = views(R.layout.notification_curve_big, CurveRenderer.draw(data, now, 640, 300, legend = false), "Substance Journal", subtitle)
        val publicVersion = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_curve)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(publicSmall)
            .setCustomBigContentView(publicBig)
            .setOnlyAlertOnce(true)
            .build()

        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_curve)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(small)
            .setCustomBigContentView(big)
            .setContentIntent(route("live-open", 1))
            .addAction(0, "Same as last", route("live-same", 2))
            .addAction(0, "Add dose", route("live-add", 3))
            .addAction(0, "Add note", route("live-note", 4))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
            .setColor(Color.GRAY)
            .build()
    }

    companion object {
        const val CHANNEL = "live_curve_v2"
        const val ID = 4107
        const val ACTION_REFRESH = "com.substancejournal.substance_journal_app.LIVE_REFRESH"
        const val ACTION_STOP = "com.substancejournal.substance_journal_app.LIVE_STOP"
        private const val PREFS = "sj_live"

        @Volatile
        var running = false

        fun save(context: Context, json: String?) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
                if (json == null) remove("json") else putString("json", json)
            }.apply()
        }

        fun load(context: Context): String? = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("json", null)

        /// Shows or updates the notification with new data. Returns false when Android refused to start
        /// the service (the app was in the background); a running service is refreshed regardless.
        fun update(context: Context, json: String): Boolean {
            save(context, json)
            if (running) {
                context.sendBroadcast(Intent(ACTION_REFRESH).setPackage(context.packageName))
                return true
            }
            return try {
                ContextCompat.startForegroundService(context, Intent(context, LiveCurveService::class.java))
                true
            } catch (e: Exception) {
                false
            }
        }

        fun stop(context: Context) {
            save(context, null)
            if (running) context.sendBroadcast(Intent(ACTION_REFRESH).setPackage(context.packageName))
        }
    }
}
