package com.pta.host.pta_host

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsBroadcastReceiver : BroadcastReceiver() {
    companion object {
        var onSmsReceived: ((sender: String, body: String, timestamp: Long) -> Unit)? = null
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION || action == "android.provider.Telephony.SMS_RECEIVED") {
            try {
                val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                if (messages.isNotEmpty()) {
                    val sender = messages[0].displayOriginatingAddress ?: messages[0].originatingAddress ?: "Unknown"
                    val body = messages.joinToString("") { it.displayMessageBody ?: it.messageBody ?: "" }
                    val timestamp = messages[0].timestampMillis
                    android.util.Log.d("PTA_SMS", "SMS received from $sender: $body (timestamp=$timestamp)")
                    onSmsReceived?.invoke(sender, body, timestamp)
                }
            } catch (e: Exception) {
                android.util.Log.e("PTA_SMS", "Error processing received SMS: ${e.message}", e)
            }
        }
    }
}
