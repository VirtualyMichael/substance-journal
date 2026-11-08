package com.substancejournal.substance_journal_app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import org.json.JSONObject

// Draws the live-curve notification's graph from the JSON the app sends (see live_curve.dart): one
// line per active substance, a dot for each dose, a "now" line, and optionally a legend with names.
// Every value is an estimate.
object CurveRenderer {
    class Line(val name: String, val color: Int, val pts: List<Pair<Long, Double>>, val doses: List<Long>)

    class Data(
        val from: Long,
        val to: Long,
        val endsAt: Long,
        val lines: List<Line>,
        val bacPts: List<Pair<Long, Double>>,
    ) {
        val hasAlcohol get() = bacPts.isNotEmpty()

        /// BAC (in percent) at [t], read off the curve, or null when alcohol is not part of this.
        fun bacAt(t: Long): Double? {
            if (bacPts.isEmpty()) return null
            return valueAt(bacPts, t)
        }
    }

    fun parse(json: String?): Data? {
        if (json.isNullOrEmpty()) return null
        return try {
            val o = JSONObject(json)
            val lines = o.getJSONArray("lines")
            val parsed = (0 until lines.length()).map { i ->
                val l = lines.getJSONObject(i)
                Line(
                    l.getString("name"),
                    l.getLong("color").toInt(),
                    points(l.getJSONArray("pts")),
                    (0 until l.getJSONArray("doses").length()).map { l.getJSONArray("doses").getLong(it) },
                )
            }
            val bac = o.optJSONObject("bac")
            Data(o.getLong("from"), o.getLong("to"), o.getLong("endsAt"), parsed, if (bac == null) emptyList() else points(bac.getJSONArray("pts")))
        } catch (e: Exception) {
            null
        }
    }

    private fun points(a: org.json.JSONArray): List<Pair<Long, Double>> =
        (0 until a.length()).map { val p = a.getJSONArray(it); Pair(p.getLong(0), p.getDouble(1)) }

    private fun valueAt(pts: List<Pair<Long, Double>>, t: Long): Double {
        if (pts.isEmpty()) return 0.0
        if (t <= pts.first().first) return pts.first().second
        if (t >= pts.last().first) return pts.last().second
        for (i in 1 until pts.size) {
            if (t <= pts[i].first) {
                val (t0, v0) = pts[i - 1]
                val (t1, v1) = pts[i]
                return if (t1 == t0) v1 else v0 + (v1 - v0) * (t - t0).toDouble() / (t1 - t0)
            }
        }
        return pts.last().second
    }

    fun draw(data: Data, nowMs: Long, width: Int, height: Int, legend: Boolean): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val unit = height / 100f
        val left = unit * 3
        val right = width - unit * 3
        val legendH = if (legend) unit * 17 else 0f
        val top = unit * 5 + legendH
        val bottom = height - unit * 6

        var peak = 1.0
        for (l in data.lines) for (p in l.pts) if (p.second > peak) peak = p.second
        peak *= 1.12
        val span = (data.to - data.from).coerceAtLeast(1).toDouble()
        fun x(t: Long) = left + ((t - data.from) / span).toFloat().coerceIn(0f, 1f) * (right - left)
        fun y(v: Double) = bottom - (v / peak).toFloat().coerceIn(0f, 1f) * (bottom - top)

        val grid = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(90, 140, 140, 140); strokeWidth = unit * 0.7f }
        canvas.drawLine(left, bottom, right, bottom, grid)
        // An hour tick along the bottom, so the width reads as time without any labels.
        val hour = 3_600_000L
        var tick = (data.from / hour + 1) * hour
        while (tick < data.to) {
            canvas.drawLine(x(tick), bottom, x(tick), bottom + unit * 2.5f, grid)
            tick += hour
        }

        for (l in data.lines) {
            if (l.pts.size < 2) continue
            val path = Path()
            l.pts.forEachIndexed { i, p -> if (i == 0) path.moveTo(x(p.first), y(p.second)) else path.lineTo(x(p.first), y(p.second)) }
            val fill = Path(path).apply {
                lineTo(x(l.pts.last().first), bottom)
                lineTo(x(l.pts.first().first), bottom)
                close()
            }
            canvas.drawPath(fill, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = l.color; alpha = 55; style = Paint.Style.FILL })
            canvas.drawPath(
                path,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = l.color; style = Paint.Style.STROKE; strokeWidth = unit * 1.8f; strokeJoin = Paint.Join.ROUND },
            )
            val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = l.color; style = Paint.Style.FILL }
            for (d in l.doses) {
                if (d < data.from || d > data.to) continue
                canvas.drawCircle(x(d), y(valueAt(l.pts, d)), unit * 2.1f, dot)
            }
        }

        val nowX = x(nowMs)
        canvas.drawLine(nowX, top - unit * 2, nowX, bottom, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(200, 150, 150, 150); strokeWidth = unit * 1.1f })

        if (legend) {
            val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = unit * 11f; isFakeBoldText = true }
            var cx = left
            val cy = unit * 12f
            for (l in data.lines) {
                text.color = l.color
                canvas.drawCircle(cx + unit * 2.5f, cy - unit * 3.2f, unit * 2.6f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = l.color })
                canvas.drawText(l.name, cx + unit * 7f, cy, text)
                cx += unit * 7f + text.measureText(l.name) + unit * 6f
            }
        }
        return bitmap
    }
}
