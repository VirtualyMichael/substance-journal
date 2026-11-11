package com.substancejournal.substance_journal_app

import android.content.Context
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable

// Talks to the paired Wear OS watch through the Data Layer: the curve and recent doses go out as one
// data item (the watch keeps the last one, so it still has something when the phone is out of
// range), and replies go back as small messages.
object WatchBridge {
    const val SNAPSHOT_PATH = "/snapshot"
    const val RESULT_PATH = "/result"

    fun push(context: Context, json: String) {
        val request = PutDataRequest.create(SNAPSHOT_PATH).setData(json.toByteArray(Charsets.UTF_8)).setUrgent()
        Wearable.getDataClient(context).putDataItem(request)
    }

    fun reply(context: Context, nodeId: String, json: String) {
        Wearable.getMessageClient(context).sendMessage(nodeId, RESULT_PATH, json.toByteArray(Charsets.UTF_8))
    }
}
