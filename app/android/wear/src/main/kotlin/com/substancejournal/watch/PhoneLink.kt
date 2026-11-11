package com.substancejournal.watch

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject

/** What the screen shows: the last data from the phone and the phone's last answer to a button. */
object WatchState {
    val snapshot = MutableStateFlow<Snapshot?>(null)
    val message = MutableStateFlow<String?>(null)
    val busy = MutableStateFlow(false)
}

object PhoneLink {
    /** Reads the newest data the phone left for us (it keeps it while the watch is away). */
    fun loadLatest(context: Context) {
        Wearable.getDataClient(context).getDataItems(Uri.parse("wear://*/snapshot")).addOnSuccessListener { items ->
            try {
                for (item in items) {
                    val data = item.data ?: continue
                    parseSnapshot(String(data, Charsets.UTF_8))?.let { WatchState.snapshot.value = it }
                }
            } finally {
                items.release()
            }
        }
    }

    /** Sends [path] ("/same" or "/refresh") to the paired phone. */
    fun ask(context: Context, path: String) {
        WatchState.busy.value = true
        WatchState.message.value = null
        Wearable.getNodeClient(context).connectedNodes.addOnSuccessListener { nodes ->
            val phone = nodes.firstOrNull { it.isNearby } ?: nodes.firstOrNull()
            if (phone == null) {
                WatchState.busy.value = false
                WatchState.message.value = "No phone connected."
            } else {
                Wearable.getMessageClient(context).sendMessage(phone.id, path, ByteArray(0)).addOnFailureListener {
                    WatchState.busy.value = false
                    WatchState.message.value = "Could not reach the phone."
                }
            }
        }.addOnFailureListener {
            WatchState.busy.value = false
            WatchState.message.value = "Could not reach the phone."
        }
    }
}

/** Runs when the phone sends new data or answers a button, even while the app is not open. */
class PhoneLinkService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.type == DataEvent.TYPE_CHANGED && event.dataItem.uri.path == "/snapshot") {
                val data = event.dataItem.data ?: continue
                parseSnapshot(String(data, Charsets.UTF_8))?.let { WatchState.snapshot.value = it }
            }
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/result") return
        try {
            val reply = JSONObject(String(event.data, Charsets.UTF_8))
            WatchState.message.value = reply.optString("message").ifEmpty { null }
        } catch (_: Exception) {
            WatchState.message.value = null
        }
        WatchState.busy.value = false
    }
}
