package com.substancejournal.watch

import org.json.JSONObject

class Line(val name: String, val color: Int, val points: List<Pair<Long, Double>>, val doses: List<Long>)

class Dose(val name: String, val color: Int, val dose: String, val at: Long)

/** What the phone sent: the live curve, the last few doses and the "Same as last time" button. */
class Snapshot(
    val sentAt: Long,
    val from: Long,
    val to: Long,
    val lines: List<Line>,
    val bacNow: Double?,
    val recent: List<Dose>,
    val same: String?,
    val canLog: Boolean,
) {
    val hasCurve: Boolean get() = lines.isNotEmpty()
}

fun parseSnapshot(json: String): Snapshot? = try {
    val root = JSONObject(json)
    val curve = if (root.isNull("curve")) null else root.getJSONObject("curve")
    val lines = ArrayList<Line>()
    var bacNow: Double? = null
    if (curve != null) {
        val array = curve.getJSONArray("lines")
        for (i in 0 until array.length()) {
            val l = array.getJSONObject(i)
            val pts = l.getJSONArray("pts")
            val doses = l.getJSONArray("doses")
            lines.add(
                Line(
                    name = l.getString("name"),
                    color = l.getLong("color").toInt(),
                    points = List(pts.length()) { n -> pts.getJSONArray(n).let { it.getLong(0) to it.getDouble(1) } },
                    doses = List(doses.length()) { n -> doses.getLong(n) },
                ),
            )
        }
        if (!curve.isNull("bac")) bacNow = curve.getJSONObject("bac").getDouble("now")
    }
    val recent = root.getJSONArray("recent")
    Snapshot(
        sentAt = root.getLong("now"),
        from = curve?.getLong("from") ?: 0L,
        to = curve?.getLong("to") ?: 0L,
        lines = lines,
        bacNow = bacNow,
        recent = List(recent.length()) { n ->
            val d = recent.getJSONObject(n)
            Dose(d.getString("name"), d.getLong("color").toInt(), d.getString("dose"), d.getLong("at"))
        },
        same = if (root.isNull("same")) null else root.getString("same"),
        canLog = root.optBoolean("canLog", false),
    )
} catch (_: Exception) {
    null
}
