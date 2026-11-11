package com.substancejournal.watch

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import kotlin.math.max

/** One line per active substance (in its own colour), dots where doses were taken, and a dotted "now". */
@Composable
fun CurveChart(snapshot: Snapshot, nowMs: Long, modifier: Modifier = Modifier) {
    Box(modifier) {
        Canvas(Modifier.fillMaxSize()) {
            val span = max(1L, snapshot.to - snapshot.from).toFloat()
            var top = 1.2
            for (line in snapshot.lines) for (p in line.points) top = max(top, p.second * 1.1)
            val w = size.width
            val h = size.height
            fun x(t: Long) = ((t - snapshot.from) / span).coerceIn(0f, 1f) * w
            fun y(v: Double) = (h - (v / top).toFloat().coerceIn(0f, 1f) * (h - 6.dp.toPx())) - 2.dp.toPx()

            // Baseline and the "now" marker.
            drawLine(Color(0x44FFFFFF), Offset(0f, h - 2.dp.toPx()), Offset(w, h - 2.dp.toPx()), 1.dp.toPx())
            val nowX = x(nowMs)
            drawLine(
                Color(0x99FFFFFF), Offset(nowX, 0f), Offset(nowX, h), 1.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())),
            )

            for (line in snapshot.lines) {
                val color = Color(line.color)
                if (line.points.size >= 2) {
                    val path = Path()
                    line.points.forEachIndexed { i, p ->
                        if (i == 0) path.moveTo(x(p.first), y(p.second)) else path.lineTo(x(p.first), y(p.second))
                    }
                    drawPath(path, color, style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round))
                }
                for (dose in line.doses) {
                    if (dose in snapshot.from..snapshot.to) drawCircle(color, 3.dp.toPx(), Offset(x(dose), h - 2.dp.toPx()))
                }
            }
        }
    }
}
