package com.pta.host.pta_host

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.FileObserver
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.telecom.TelecomManager
import android.net.wifi.WifiManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import java.io.File
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
    private var audioRouteReceiver: BroadcastReceiver? = null
    private var recordingFileObserver: FileObserver? = null
    private var audioRecordingCallback: AudioManager.AudioRecordingCallback? = null
    private var isCallMonitoringActive = false
    private var lastEmittedActiveTimestamp = 0L
    private var toneGenerator: ToneGenerator? = null

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
                "getAudioRoute" -> {
                    result.success(getAudioRouteNative())
                }
                "setAudioRoute" -> {
                    val route = call.argument<String>("route") ?: "EARPIECE"
                    result.success(setAudioRouteNative(route))
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
                "getAllSms" -> {
                    val limit = call.argument<Int>("limit") ?: 500
                    val list = getAllSmsNative(limit)
                    result.success(list)
                }
                "setMobileData" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    result.success(setMobileDataNative(enabled))
                }
                "setDataSim" -> {
                    val subId = call.argument<Int>("subId") ?: -1
                    result.success(setDataSimNative(subId))
                }
                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(true)
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

                    if (stateStr == TelephonyManager.EXTRA_STATE_OFFHOOK) {
                        startCallAnswerMonitoring()
                    } else if (stateStr == TelephonyManager.EXTRA_STATE_IDLE) {
                        stopCallAnswerMonitoring()
                    } else if (stateStr == TelephonyManager.EXTRA_STATE_RINGING) {
                        stopCallAnswerMonitoring()
                    }

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

        // Register hardware Audio Route & Bluetooth SCO change listener
        try {
            val audioFilter = IntentFilter().apply {
                addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
                addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
                addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
                addAction(BluetoothHeadset.ACTION_AUDIO_STATE_CHANGED)
            }
            val aReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    val updated = getAudioRouteNative()
                    val payload = HashMap<String, Any>()
                    payload["type"] = "AUDIO_ROUTE"
                    payload.putAll(updated)
                    eventSink?.success(payload)
                }
            }
            registerReceiver(aReceiver, audioFilter)
            audioRouteReceiver = aReceiver
        } catch (e: Exception) {
            android.util.Log.e("PTA_AUDIO", "Error registering audioRouteReceiver: ${e.message}")
        }
    }

    private fun unregisterPhoneStateReceiver() {
        stopCallAnswerMonitoring()
        phoneStateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            phoneStateReceiver = null
        }
        audioRouteReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            audioRouteReceiver = null
        }
    }

    private fun startCallAnswerMonitoring() {
        if (isCallMonitoringActive) return
        isCallMonitoringActive = true
        android.util.Log.d("PTA_TELEPHONY", "Starting call answer detectors (Vivo FileObserver & AudioRecordingCallback)...")

        // 1. Vivo Call Recording Inotify / FileObserver
        // Vivo S1 begins writing .m4a file the exact second the call connects
        try {
            val candidateDirs = listOf(
                File("/storage/emulated/0/Recordings/Record/Call"),
                File("/storage/emulated/0/Record/Call")
            )
            for (dir in candidateDirs) {
                if (dir.exists()) {
                    val observer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        object : FileObserver(dir, CREATE or MOVED_TO) {
                            override fun onEvent(event: Int, path: String?) {
                                if (path != null && (path.endsWith(".m4a") || path.endsWith(".amr") || path.endsWith(".mp3") || path.endsWith(".aac"))) {
                                    emitCallAnswered("VIVO_RECORDING_FILE", path)
                                }
                            }
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        object : FileObserver(dir.absolutePath, CREATE or MOVED_TO) {
                            override fun onEvent(event: Int, path: String?) {
                                if (path != null && (path.endsWith(".m4a") || path.endsWith(".amr") || path.endsWith(".mp3") || path.endsWith(".aac"))) {
                                    emitCallAnswered("VIVO_RECORDING_FILE", path)
                                }
                            }
                        }
                    }
                    observer.startWatching()
                    recordingFileObserver = observer
                    android.util.Log.d("PTA_TELEPHONY", "Vivo Call Recording FileObserver active on ${dir.absolutePath}")
                    break
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("PTA_TELEPHONY", "Error setting up recording FileObserver: ${e.message}")
        }

        // 2. AudioManager AudioRecordingCallback (detects hardware VOICE_CALL recording activation)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager != null) {
                    val cb = object : AudioManager.AudioRecordingCallback() {
                        override fun onRecordingConfigChanged(configs: List<AudioRecordingConfiguration>?) {
                            super.onRecordingConfigChanged(configs)
                            configs?.forEach { cfg ->
                                val src = cfg.clientAudioSource
                                if (src == MediaRecorder.AudioSource.VOICE_CALL ||
                                    src == MediaRecorder.AudioSource.VOICE_COMMUNICATION) {
                                    emitCallAnswered("AUDIO_RECORDING_CONFIG", "source_$src")
                                }
                            }
                        }
                    }
                    audioManager.registerAudioRecordingCallback(cb, Handler(Looper.getMainLooper()))
                    audioRecordingCallback = cb
                    android.util.Log.d("PTA_TELEPHONY", "AudioManager AudioRecordingCallback registered")
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("PTA_TELEPHONY", "Error registering AudioRecordingCallback: ${e.message}")
        }
    }

    private fun stopCallAnswerMonitoring() {
        isCallMonitoringActive = false
        try {
            recordingFileObserver?.stopWatching()
            recordingFileObserver = null
        } catch (_: Exception) {}

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && audioRecordingCallback != null) {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                audioManager?.unregisterAudioRecordingCallback(audioRecordingCallback!!)
                audioRecordingCallback = null
            }
        } catch (_: Exception) {}
    }

    private fun emitCallAnswered(source: String, detail: String) {
        if (!isCallMonitoringActive) return
        val now = System.currentTimeMillis()
        if (now - lastEmittedActiveTimestamp < 4000) return
        lastEmittedActiveTimestamp = now

        runOnUiThread {
            android.util.Log.d("PTA_TELEPHONY", "Call Answered detected via $source ($detail) at $now")
            val payload = HashMap<String, Any>()
            payload["type"] = "CALL"
            payload["state"] = "ACTIVE"
            payload["timestamp"] = now
            payload["source"] = source
            payload["incomingNumber"] = ""
            payload["detail"] = detail
            eventSink?.success(payload)
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

    private fun getAudioRouteNative(): Map<String, Any> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val result = HashMap<String, Any>()
        if (audioManager == null) {
            result["currentRoute"] = "EARPIECE"
            result["bluetoothConnected"] = false
            result["bluetoothName"] = ""
            result["availableRoutes"] = listOf("EARPIECE", "SPEAKER")
            return result
        }

        var isBtConnected = false
        var btDeviceName = ""

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (d in devices) {
                if (d.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    d.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && d.type == AudioDeviceInfo.TYPE_BLE_HEADSET)) {
                    isBtConnected = true
                    btDeviceName = d.productName?.toString() ?: "Bluetooth Audio"
                    break
                }
            }
        }

        val available = ArrayList<String>()
        available.add("EARPIECE")
        available.add("SPEAKER")
        if (isBtConnected) {
            available.add("BLUETOOTH")
        }

        val currentRoute = when {
            audioManager.isSpeakerphoneOn -> "SPEAKER"
            audioManager.isBluetoothScoOn -> "BLUETOOTH"
            else -> "EARPIECE"
        }

        result["currentRoute"] = currentRoute
        result["bluetoothConnected"] = isBtConnected
        result["bluetoothName"] = btDeviceName
        result["availableRoutes"] = available
        return result
    }

    private fun setAudioRouteNative(route: String): Map<String, Any> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return getAudioRouteNative()
        android.util.Log.d("PTA_AUDIO", "setAudioRouteNative requested: $route")

        when (route.uppercase()) {
            "SPEAKER" -> {
                audioManager.mode = AudioManager.MODE_IN_CALL
                if (audioManager.isBluetoothScoOn) {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                }
                audioManager.isSpeakerphoneOn = true
                try {
                    Runtime.getRuntime().exec(arrayOf("cmd", "telecom", "set-audio-route", "4"))
                } catch (_: Exception) {}
            }
            "BLUETOOTH" -> {
                audioManager.mode = AudioManager.MODE_IN_CALL
                audioManager.isSpeakerphoneOn = false
                audioManager.startBluetoothSco()
                audioManager.isBluetoothScoOn = true
                try {
                    Runtime.getRuntime().exec(arrayOf("cmd", "telecom", "set-audio-route", "2"))
                } catch (_: Exception) {}
            }
            "EARPIECE" -> {
                audioManager.mode = AudioManager.MODE_IN_CALL
                audioManager.isSpeakerphoneOn = false
                if (audioManager.isBluetoothScoOn) {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                }
                try {
                    Runtime.getRuntime().exec(arrayOf("cmd", "telecom", "set-audio-route", "1"))
                } catch (_: Exception) {}
            }
        }

        val updated = getAudioRouteNative()
        runOnUiThread {
            val payload = HashMap<String, Any>()
            payload["type"] = "AUDIO_ROUTE"
            payload.putAll(updated)
            eventSink?.success(payload)
        }
        return updated
    }

    private fun sendDtmfNative(digit: String): Boolean {
        android.util.Log.d("PTA_DTMF", "sendDtmfNative: digit=$digit")
        val tone = when (digit) {
            "0" -> ToneGenerator.TONE_DTMF_0
            "1" -> ToneGenerator.TONE_DTMF_1
            "2" -> ToneGenerator.TONE_DTMF_2
            "3" -> ToneGenerator.TONE_DTMF_3
            "4" -> ToneGenerator.TONE_DTMF_4
            "5" -> ToneGenerator.TONE_DTMF_5
            "6" -> ToneGenerator.TONE_DTMF_6
            "7" -> ToneGenerator.TONE_DTMF_7
            "8" -> ToneGenerator.TONE_DTMF_8
            "9" -> ToneGenerator.TONE_DTMF_9
            "*" -> ToneGenerator.TONE_DTMF_S
            "#" -> ToneGenerator.TONE_DTMF_P
            else -> -1
        }
        if (tone != -1) {
            try {
                if (toneGenerator == null) {
                    toneGenerator = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 100)
                }
                toneGenerator?.startTone(tone, 200)
            } catch (e: Exception) {
                android.util.Log.e("PTA_DTMF", "ToneGenerator error: ${e.message}")
            }
        }

        // Tier 2: Shell input keyevent simulation
        val keycode = when (digit) {
            "0" -> 7
            "1" -> 8
            "2" -> 9
            "3" -> 10
            "4" -> 11
            "5" -> 12
            "6" -> 13
            "7" -> 14
            "8" -> 15
            "9" -> 16
            "*" -> 17
            "#" -> 18
            else -> -1
        }
        if (keycode != -1) {
            try {
                Runtime.getRuntime().exec(arrayOf("input", "keyevent", keycode.toString()))
            } catch (_: Exception) {}
        }
        return true
    }

    private fun getAllSmsNative(limit: Int): List<Map<String, Any>> {
        val result = ArrayList<Map<String, Any>>()
        try {
            val uri = Uri.parse("content://sms")
            val projection = arrayOf("_id", "address", "body", "date", "type", "read")
            val cursor = contentResolver.query(uri, projection, null, null, "date DESC LIMIT $limit")
            cursor?.use {
                val idCol = it.getColumnIndex("_id")
                val addressCol = it.getColumnIndex("address")
                val bodyCol = it.getColumnIndex("body")
                val dateCol = it.getColumnIndex("date")
                val typeCol = it.getColumnIndex("type")
                val readCol = it.getColumnIndex("read")

                while (it.moveToNext()) {
                    val id = if (idCol >= 0) it.getLong(idCol) else 0L
                    val address = if (addressCol >= 0) it.getString(addressCol) ?: "" else ""
                    val body = if (bodyCol >= 0) it.getString(bodyCol) ?: "" else ""
                    val date = if (dateCol >= 0) it.getLong(dateCol) else 0L
                    val type = if (typeCol >= 0) it.getInt(typeCol) else 1
                    val read = if (readCol >= 0) it.getInt(readCol) == 1 else true

                    val item = HashMap<String, Any>()
                    item["id"] = id
                    // Outgoing message (type 2) marked with "To: " so iOS matches cleanly
                    item["sender"] = if (type == 2) "To: $address" else address
                    item["body"] = body
                    item["timestamp"] = date
                    item["isRead"] = read
                    result.add(item)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return result
    }

    private fun setMobileDataNative(enabled: Boolean): Boolean {
        var success = false
        val intVal = if (enabled) 1 else 0
        // Tier 1: Settings.Global (works with WRITE_SECURE_SETTINGS)
        try {
            Settings.Global.putInt(contentResolver, "mobile_data", intVal)
            Settings.Global.putInt(contentResolver, "mobile_data1", intVal)
            Settings.Global.putInt(contentResolver, "mobile_data2", intVal)
            success = true
        } catch (e: Exception) {
            // WRITE_SECURE_SETTINGS not yet granted
        }

        // Tier 2: TelephonyManager setDataEnabled
        try {
            val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            if (telephonyManager != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    telephonyManager.isDataEnabled = enabled
                    success = true
                } else {
                    val method = telephonyManager.javaClass.getDeclaredMethod("setDataEnabled", Boolean::class.javaPrimitiveType)
                    method.isAccessible = true
                    method.invoke(telephonyManager, enabled)
                    success = true
                }
            }
        } catch (e: Exception) {
            // Requires MODIFY_PHONE_STATE
        }

        return success
    }

    private fun setDataSimNative(subId: Int): Boolean {
        var success = false
        // Tier 1: Settings.Global (works with WRITE_SECURE_SETTINGS)
        try {
            Settings.Global.putInt(contentResolver, "user_preferred_data_sub", subId)
            Settings.Global.putInt(contentResolver, "multi_sim_data_call", subId)
            success = true
        } catch (e: Exception) {
            // WRITE_SECURE_SETTINGS not yet granted
        }

        // Tier 2: SubscriptionManager setDefaultDataSubId via reflection
        try {
            val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
            if (subManager != null) {
                val method = subManager.javaClass.getDeclaredMethod("setDefaultDataSubId", Int::class.javaPrimitiveType)
                method.isAccessible = true
                method.invoke(subManager, subId)
                success = true
            }
        } catch (e: Exception) {
            // Requires system permission
        }

        return success
    }
}

