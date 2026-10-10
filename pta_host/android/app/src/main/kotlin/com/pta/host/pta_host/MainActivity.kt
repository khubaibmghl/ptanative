package com.pta.host.pta_host

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telecom.TelecomManager
import android.net.wifi.WifiManager
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import java.net.NetworkInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.pta.host/telephony_methods"
    private val EVENT_CHANNEL = "com.pta.host/telephony_events"
    private var eventSink: EventChannel.EventSink? = null
    private var phoneStateReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "dialNumber" -> {
                    val number = call.argument<String>("number") ?: ""
                    val success = makeDirectCall(number)
                    result.success(success)
                }
                "endCall" -> {
                    val success = endCallNative()
                    result.success(success)
                }
                "answerCall" -> {
                    val success = answerCallNative()
                    result.success(success)
                }
                "startService" -> {
                    startForegroundServiceNative()
                    result.success(true)
                }
                "stopService" -> {
                    stopForegroundServiceNative()
                    result.success(true)
                }
                "isBatteryOptimizationIgnored" -> {
                    result.success(isBatteryOptimizationIgnored())
                }
                "requestBatteryOptimization" -> {
                    requestBatteryOptimization()
                    result.success(true)
                }
                "enableAudioRouting" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    enableCallAudioRouting(enable)
                    result.success(true)
                }
                "sendSms" -> {
                    val recipient = call.argument<String>("recipient") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val success = sendSmsNative(recipient, message)
                    result.success(success)
                }
                "isHotspotActive" -> {
                    result.success(isHotspotActiveNative())
                }
                "openTetherSettings" -> {
                    result.success(openTetherSettingsNative())
                }
                "sendDtmf" -> {
                    val digit = call.argument<String>("digit") ?: ""
                    result.success(sendDtmfNative(digit))
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                SmsBroadcastReceiver.onSmsReceived = { sender, body, timestamp ->
                    runOnUiThread {
                        val payload = HashMap<String, Any>()
                        payload["type"] = "SMS"
                        payload["sender"] = sender
                        payload["body"] = body
                        payload["timestamp"] = timestamp
                        eventSink?.success(payload)
                    }
                }
                registerPhoneStateReceiver()
            }

            override fun onCancel(arguments: Any?) {
                SmsBroadcastReceiver.onSmsReceived = null
                unregisterPhoneStateReceiver()
                eventSink = null
            }
        })
    }

    private fun startForegroundServiceNative() {
        try {
            requestBatteryOptimization()
            val intent = Intent(this, HostForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopForegroundServiceNative() {
        try {
            val intent = Intent(this, HostForegroundService::class.java)
            stopService(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun registerPhoneStateReceiver() {
        if (phoneStateReceiver != null) return
        phoneStateReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val action = intent.action
                val payload = HashMap<String, Any>()

                if (action == TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
                    val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                    val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
                    payload["type"] = "CALL"
                    payload["state"] = stateStr ?: "IDLE"
                    payload["incomingNumber"] = incomingNumber
                    eventSink?.success(payload)
                } else if (action == "android.intent.action.PRECISE_CALL_STATE_CHANGED") {
                    val fgState = intent.getIntExtra("foreground_state", -1)
                    val stateStr = when (fgState) {
                        1 -> "ACTIVE"      // Call Answered & Connected!
                        3, 4 -> "DIALING"  // Dialing out / Ringing on remote end
                        0 -> "IDLE"        // Call ended
                        else -> null
                    }
                    if (stateStr != null) {
                        payload["type"] = "CALL"
                        payload["state"] = stateStr
                        payload["incomingNumber"] = ""
                        eventSink?.success(payload)
                    }
                } else if (action == android.provider.Telephony.Sms.Intents.SMS_RECEIVED_ACTION || action == "android.provider.Telephony.SMS_RECEIVED") {
                    try {
                        val messages = android.provider.Telephony.Sms.Intents.getMessagesFromIntent(intent)
                        if (messages.isNotEmpty()) {
                            val sender = messages[0].displayOriginatingAddress ?: messages[0].originatingAddress ?: "Unknown"
                            val body = messages.joinToString("") { it.displayMessageBody ?: it.messageBody ?: "" }
                            val timestamp = messages[0].timestampMillis
                            val smsPayload = HashMap<String, Any>()
                            smsPayload["type"] = "SMS"
                            smsPayload["sender"] = sender
                            smsPayload["body"] = body
                            smsPayload["timestamp"] = timestamp
                            eventSink?.success(smsPayload)
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
            addAction("android.intent.action.PRECISE_CALL_STATE_CHANGED")
            addAction(android.provider.Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
            addAction("android.provider.Telephony.SMS_RECEIVED")
        }
        registerReceiver(phoneStateReceiver, filter)
    }

    private fun unregisterPhoneStateReceiver() {
        phoneStateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            phoneStateReceiver = null
        }
    }

    private fun makeDirectCall(number: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_CALL).apply {
                data = Uri.parse("tel:$number")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun endCallNative(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                telecomManager.endCall()
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun answerCallNative(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                telecomManager.acceptRingingCall()
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun enableCallAudioRouting(enable: Boolean) {
        // Voice transmission withdrawn: keep native device audio unchanged
        android.util.Log.d("PTA_AUDIO", "Audio routing request ignored (voice transmission withdrawn)")
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true
        } else {
            true
        }
    }

    private fun requestBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager?.isIgnoringBatteryOptimizations(packageName) == false) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    try {
                        val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(fallbackIntent)
                    } catch (_: Exception) {}
                }
            }
        }
    }

    private fun sendSmsNative(recipient: String, message: String): Boolean {
        val clean = recipient.trim()
        if (clean.isEmpty() || message.isEmpty()) return false
        return try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                applicationContext.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(clean, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(clean, null, message, null, null)
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun isHotspotActiveNative(): Boolean {
        return try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val method = wifiManager?.javaClass?.getDeclaredMethod("isWifiApEnabled")
            if (method != null) {
                method.isAccessible = true
                val isEnabled = method.invoke(wifiManager) as? Boolean
                if (isEnabled == true) return true
            }
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                val name = iface.name.lowercase()
                if ((name.contains("ap") || name.contains("wlan1") || name.contains("rndis") || name.contains("softap")) && iface.isUp) {
                    return true
                }
            }
            false
        } catch (e: Exception) {
            false
        }
    }

    private fun openTetherSettingsNative(): Boolean {
        return try {
            val intent = Intent().apply {
                action = "android.settings.TETHER_SETTINGS"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            try {
                val fallback = Intent(Settings.ACTION_WIRELESS_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(fallback)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun sendDtmfNative(digit: String): Boolean {
        // Can be routed through InCallService / TelecomManager if active
        return true
    }
}
