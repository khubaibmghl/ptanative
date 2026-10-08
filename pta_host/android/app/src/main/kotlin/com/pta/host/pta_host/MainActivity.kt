package com.pta.host.pta_host

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
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
                "enableAudioRouting" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    enableCallAudioRouting(enable)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                registerPhoneStateReceiver()
            }

            override fun onCancel(arguments: Any?) {
                unregisterPhoneStateReceiver()
                eventSink = null
            }
        })
    }

    private fun startForegroundServiceNative() {
        try {
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
                        payload["state"] = stateStr
                        payload["incomingNumber"] = ""
                        eventSink?.success(payload)
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
            addAction("android.intent.action.PRECISE_CALL_STATE_CHANGED")
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
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            val prevMode = audioManager.mode
            val prevSpeaker = audioManager.isSpeakerphoneOn
            val prevMute = audioManager.isMicrophoneMute
            android.util.Log.d("PTA_AUDIO", "enableCallAudioRouting(enable=$enable) PREV -> Mode: $prevMode, Speaker: $prevSpeaker, Mute: $prevMute")

            if (enable) {
                audioManager.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
                audioManager.isSpeakerphoneOn = true
                audioManager.isMicrophoneMute = false
            } else {
                audioManager.mode = android.media.AudioManager.MODE_NORMAL
                audioManager.isSpeakerphoneOn = false
            }

            android.util.Log.d("PTA_AUDIO", "enableCallAudioRouting(enable=$enable) NEW -> Mode: ${audioManager.mode}, Speaker: ${audioManager.isSpeakerphoneOn}, Mute: ${audioManager.isMicrophoneMute}")
        } catch (e: Exception) {
            android.util.Log.e("PTA_AUDIO", "Exception in enableCallAudioRouting: ${e.message}", e)
        }
    }
}
