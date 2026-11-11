package com.substancejournal.watch

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.background
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import androidx.wear.compose.material.dialog.Alert
import androidx.wear.compose.material.dialog.Dialog
import kotlinx.coroutines.delay
import java.text.DateFormat
import java.util.Date

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PhoneLink.loadLatest(this)
        setContent { WatchApp() }
    }

    override fun onResume() {
        super.onResume()
        // Ask the phone for fresh numbers whenever the app is opened.
        PhoneLink.ask(this, "/refresh")
    }
}

private fun clock(ms: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))

@Composable
fun WatchApp() {
    val context = LocalContext.current
    val snapshot by WatchState.snapshot.collectAsState()
    val message by WatchState.message.collectAsState()
    val busy by WatchState.busy.collectAsState()
    var confirm by remember { mutableStateOf(false) }
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(30_000)
        }
    }
    val listState = rememberScalingLazyListState()

    MaterialTheme {
        Scaffold(
            timeText = { TimeText() },
            vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
            positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
        ) {
            val s = snapshot
            ScalingLazyColumn(modifier = Modifier.fillMaxSize(), state = listState, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (s == null) {
                    item {
                        Text(
                            "Waiting for the phone. Open Substance Journal on it and turn on Settings, Reminders and notifications, Watch.",
                            textAlign = TextAlign.Center,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(horizontal = 12.dp),
                        )
                    }
                } else {
                    item {
                        Text(
                            if (s.bacNow != null && s.bacNow > 0.0005) "BAC ${"%.3f".format(s.bacNow)}%" else if (s.hasCurve) "Active now" else "Nothing active",
                            style = MaterialTheme.typography.title2,
                        )
                    }
                    if (s.hasCurve) {
                        item { CurveChart(s, now, Modifier.fillMaxWidth().height(96.dp).padding(horizontal = 8.dp)) }
                        items(s.lines) { line ->
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Box(Modifier.size(10.dp).background(Color(line.color), CircleShape))
                                Text(line.name, color = Color(line.color), fontSize = 14.sp)
                            }
                        }
                    }
                    item {
                        Chip(
                            modifier = Modifier.fillMaxWidth(),
                            enabled = s.canLog && !busy,
                            onClick = { confirm = true },
                            label = { Text("Same as last time") },
                            secondaryLabel = { Text(s.same ?: "Nothing yet", maxLines = 1) },
                            colors = ChipDefaults.primaryChipColors(),
                        )
                    }
                    if (!s.canLog && s.same != null) {
                        item {
                            Text("Turn on logging from the watch in the phone app.", fontSize = 11.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 14.dp))
                        }
                    }
                    if (message != null) {
                        item { Text(message ?: "", fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 14.dp)) }
                    }
                    item { Text("Recent doses", style = MaterialTheme.typography.caption1) }
                    items(s.recent) { dose ->
                        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("${dose.name} ${dose.dose}", color = Color(dose.color), fontSize = 12.sp, maxLines = 1, modifier = Modifier.weight(1f))
                            Text(clock(dose.at), fontSize = 12.sp)
                        }
                    }
                    item {
                        CompactChip(
                            onClick = { PhoneLink.ask(context, "/refresh") },
                            enabled = !busy,
                            label = { Text(if (busy) "Working..." else "Refresh") },
                        )
                    }
                    item { Text("Updated ${clock(s.sentAt)}", fontSize = 11.sp) }
                }
            }
        }

        val s = snapshot
        Dialog(showDialog = confirm, onDismissRequest = { confirm = false }) {
            Alert(
                title = { Text("Log ${s?.same ?: "this"} now?", textAlign = TextAlign.Center) },
                negativeButton = { CompactChip(onClick = { confirm = false }, label = { Text("No") }) },
                positiveButton = {
                    CompactChip(
                        onClick = {
                            confirm = false
                            PhoneLink.ask(context, "/same")
                        },
                        label = { Text("Log") },
                    )
                },
            )
        }
    }
}
