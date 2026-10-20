import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/activity_log.dart';
import 'telephony_controller.dart';
import 'android_content_service.dart';
import 'vivo_recording_service.dart';
import 'package:fast_contacts/fast_contacts.dart';

class RelayServer {
  static const int port = 8080;
  static const int udpPort = 8081;
  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  final TelephonyController telephonyController;
  final VoiceTunnelService voiceTunnel = VoiceTunnelService();
  AndroidContentService? contentService;
  dynamic telephonyMonitor;
  dynamic telemetryService;

  final List<WebSocketChannel> _connectedSockets = [];
  final List<ActivityLog> activityLogs = [];
  final StreamController<ActivityLog> _activityStream = StreamController<ActivityLog>.broadcast();

  Stream<ActivityLog> get onActivity => _activityStream.stream;

  bool get isRunning => _server != null;
  int get clientCount => _connectedSockets.length;

  // Cached state
  Map<String, dynamic> currentCallState = {
    'is_in_call': false,
    'is_connected': false,
    'status': 'Ready',
    'number': '',
    'direction': '',
    'start_time': 0,
    'duration_seconds': 0,
    'duration_formatted': '00:00',
  };

  List<ContactModel> cachedContacts = [];
  List<CallLogModel> cachedCallHistory = [];

  RelayServer({required this.telephonyController});

  int get connectedClientCount => _connectedSockets.length;

  void logEvent(String title, String subtitle, ActivityType type) {
    final entry = ActivityLog(title: title, subtitle: subtitle, type: type);
    activityLogs.insert(0, entry);
    if (activityLogs.length > 200) activityLogs.removeLast();
    _activityStream.add(entry);
    debugPrint('[ACTIVITY] ${entry.timeFormatted} | $title - $subtitle');
  }

  Timer? _idleTimer;
  int _lastDisconnectTime = 0;
  int _lastAnswerRequestTime = 0;
  bool enable30MinIdleShutdown = false; // Default false (Relay stays ON permanently)

  void handleIncomingSms(String sender, String body, int timestamp) {
    logEvent('SMS Received', 'From $sender: ${body.length > 35 ? "${body.substring(0, 35)}..." : body}', ActivityType.sms);
    broadcast(RelayMessage.smsReceived(
      sender: sender,
      body: body,
      timestamp: timestamp,
    ));
  }

  /// Starts the embedded HTTP & WebSocket server on 0.0.0.0:8080 and UDP discovery on 8081
  Future<bool> startServer() async {
    if (_server != null) return true;

    try {
      final innerWs = webSocketHandler(
        (WebSocketChannel socket, String? protocol) {
          _connectedSockets.add(socket);
          _lastDisconnectTime = 0;
          final clientIp = _lastKnownClientAddress?.address ?? 'Unknown';
          final connectTime = DateTime.now().millisecondsSinceEpoch;
          int clientPingCount = 0;
          int lastPingReceivedTime = connectTime;

          logEvent('Client Connected', 'iPhone connected from $clientIp. Total active: ${_connectedSockets.length}', ActivityType.success);
          debugPrint('[HOST-RELAY-DIAGNOSTIC] 🟢 iPhone WebSocket connected from $clientIp. Total active sockets: ${_connectedSockets.length}');

          // Send initial state & device status
          socket.sink.add(jsonEncode({
            'type': 'SYNC_STATE',
            'data': currentCallState,
          }));
          try {
            telemetryService?.updateAndBroadcast(force: true);
          } catch (_) {}

          socket.stream.listen(
            (message) {
              final raw = message.toString();
              try {
                final msg = RelayMessage.fromJsonString(raw);
                if (msg.type == 'PING') {
                  clientPingCount++;
                  lastPingReceivedTime = DateTime.now().millisecondsSinceEpoch;
                  socket.sink.add(RelayMessage.pong().toJsonString());
                  if (clientPingCount == 1 || clientPingCount % 6 == 0) {
                    debugPrint('[HOST-RELAY-DIAGNOSTIC] 💓 Received PING #$clientPingCount from iPhone ($clientIp). Replied with PONG.');
                  }
                  return;
                }
              } catch (_) {}
              _handleIncomingSocketMessage(raw);
            },
            onDone: () {
              _connectedSockets.remove(socket);
              _lastDisconnectTime = DateTime.now().millisecondsSinceEpoch;
              final durationSec = (_lastDisconnectTime - connectTime) ~/ 1000;
              final idleSincePingMs = _lastDisconnectTime - lastPingReceivedTime;
              final closeCode = socket.closeCode;
              final closeReason = socket.closeReason;
              logEvent(
                'Client Disconnected',
                'iPhone closed. Code: $closeCode, Reason: "$closeReason", Connected: ${durationSec}s, Pings: $clientPingCount, IdleSincePing: ${idleSincePingMs}ms',
                ActivityType.info,
              );
              debugPrint('[HOST-RELAY-DIAGNOSTIC] 🔴 iPhone WebSocket onDone fired! CloseCode: $closeCode, Reason: "$closeReason", ClientIp: $clientIp, Duration: ${durationSec}s, TotalPings: $clientPingCount, IdleSincePing: ${idleSincePingMs}ms. Remaining sockets: ${_connectedSockets.length}');
            },
            onError: (err) {
              _connectedSockets.remove(socket);
              _lastDisconnectTime = DateTime.now().millisecondsSinceEpoch;
              final durationSec = (_lastDisconnectTime - connectTime) ~/ 1000;
              final closeCode = socket.closeCode;
              final closeReason = socket.closeReason;
              logEvent(
                'Socket Error',
                'Error: $err, Code: $closeCode, Connected: ${durationSec}s',
                ActivityType.error,
              );
              debugPrint('[HOST-RELAY-DIAGNOSTIC] ❌ iPhone WebSocket onError: $err, CloseCode: $closeCode, Reason: "$closeReason", ClientIp: $clientIp, Duration: ${durationSec}s. Remaining: ${_connectedSockets.length}');
            },
          );
        },
        pingInterval: const Duration(seconds: 45),
      );

      FutureOr<Response> wsHandler(Request request) {
        try {
          final info = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
          final remote = info?.remoteAddress;
          if (remote != null && !remote.isLoopback) {
            _lastKnownClientAddress = remote;
          }
        } catch (_) {}
        return innerWs(request);
      }

      final cascade = Cascade().add(wsHandler).add(_handleRestApi);

      _server = await shelf_io.serve(cascade.handler, InternetAddress.anyIPv4, port);
      logEvent('Server Started', 'Listening on 0.0.0.0:$port', ActivityType.success);

      // Start Unkillable Native Android Foreground Service
      try {
        const MethodChannel('com.pta.host/telephony_methods').invokeMethod('startService');
      } catch (_) {}

      _startUdpDiscoveryListener();
      _startIdleCheckTimer();
      connectCloudBridge();

      return true;
    } catch (e) {
      logEvent('Server Error', 'Failed to bind port $port: $e', ActivityType.error);
      return false;
    }
  }

  void _startIdleCheckTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!enable30MinIdleShutdown) return;
      if (_connectedSockets.isEmpty && _lastDisconnectTime > 0) {
        final elapsed = (DateTime.now().millisecondsSinceEpoch - _lastDisconnectTime) ~/ 1000;
        if (elapsed >= 1800) { // 30 minutes = 1800 seconds
          logEvent('Idle Timeout', 'No iPhone connected for 30 mins. Auto-stopping relay.', ActivityType.info);
          stopServer();
        }
      }
    });
  }

  InternetAddress? _lastKnownClientAddress;

  void _startUdpDiscoveryListener() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      _udpSocket?.broadcastEnabled = true;
      _udpSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket?.receive();
          if (dg != null) {
            _lastKnownClientAddress = dg.address;
            final msg = String.fromCharCodes(dg.data).trim();
            if (msg == 'PTA_DISCOVER_REQUEST' || msg.contains('DISCOVER')) {
              final reply = jsonEncode({
                'app': 'pta_host',
                'port': port,
                'status': 'online',
              });
              _udpSocket?.send(reply.codeUnits, dg.address, dg.port);
              logEvent('Discovery Beacon', 'Replied to auto-discovery request from ${dg.address.address}', ActivityType.info);
            }
          }
        }
      });
      debugPrint('[UDP DISCOVERY] Listening on 0.0.0.0:$udpPort');
    } catch (e) {
      debugPrint('[UDP DISCOVERY] Port $udpPort notice: $e');
    }
  }

  /// Blasts high-priority signaling frames (incoming calls, SMS, hangups) over local UDP.
  /// Works with sub-5ms latency even if cellular mobile data is dry (CSFB) or iPhone screen is locked.
  void broadcastUdpBurst(RelayMessage msg, {int count = 5}) async {
    final payload = msg.toJsonString().codeUnits;
    final targets = <InternetAddress>{
      InternetAddress('255.255.255.255'),
      InternetAddress('192.168.43.255'), // Standard Vivo S1 Android Hotspot subnet broadcast
    };

    if (_lastKnownClientAddress != null) {
      targets.add(_lastKnownClientAddress!);
    }

    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            targets.add(InternetAddress(subnetBroadcast));
          }
        }
      }
    } catch (_) {}

    for (int i = 0; i < count; i++) {
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (_udpSocket != null) {
          for (final target in targets) {
            try {
              _udpSocket!.send(payload, target, udpPort);
            } catch (_) {}
          }
        }
      });
    }
  }

  /// Stops the server cleanly
  Future<void> stopServer() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _udpSocket?.close();
    _udpSocket = null;

    try {
      const MethodChannel('com.pta.host/telephony_methods').invokeMethod('stopService');
    } catch (_) {}

    for (final s in _connectedSockets) {
      try {
        s.sink.close();
      } catch (_) {}
    }
    _connectedSockets.clear();
    await _server?.close(force: true);
    _server = null;
    logEvent('Server Stopped', 'Offline', ActivityType.info);
  }

  WebSocketChannel? _cloudSocket;
  Timer? _cloudReconnectTimer;
  bool isCloudConnected = false;
  bool enableCloudBridge = false; // Default false to prevent dummy connection spam
  String cloudRelayUrl = '';
  String pairingKey = 'pta_native_default';

  /// Broadcasts a RelayMessage event to all connected iPhone clients in <10ms
  void broadcast(RelayMessage msg) {
    final jsonStr = msg.toJsonString();
    for (final socket in List<WebSocketChannel>.from(_connectedSockets)) {
      try {
        socket.sink.add(jsonStr);
      } catch (e) {
        _connectedSockets.remove(socket);
      }
    }

    // High-priority local UDP burst for call rings, dialing, connects, disconnects, and SMS (survives screen-lock & dry hotspot)
    if (msg.type == 'RINGING' || msg.type == 'INCOMING_RING' || msg.type == 'CALL_DIALING' || msg.type == 'CALL_ACTIVE' || msg.type == 'CALL_DISCONNECTED' || msg.type == 'SMS_RECEIVED') {
      broadcastUdpBurst(msg);
    }

    if (msg.type == 'CALL_DIALING' || msg.type == 'CALL_ACTIVE' || msg.type == 'CALL_TICK' || msg.type == 'CALL_DISCONNECTED') {
      final dur = currentCallState['duration_seconds'] as int? ?? 0;
      if (msg.type != 'CALL_TICK' || dur == 0 || dur % 5 == 0) {
        debugPrint('[HOST-CALL-BROADCAST] 📢 Broadcast [${msg.type}] to ${_connectedSockets.length} sockets (UDP: ${msg.type != 'CALL_TICK'}). Payload: $jsonStr');
      }
    }

    if (isCloudConnected && _cloudSocket != null) {
      try {
        final cipher = E2eeCipher.fromKey(pairingKey);
        final enc = cipher.encrypt(jsonStr);
        _cloudSocket!.sink.add(RelayMessage.encryptedFrame(enc).toJsonString());
      } catch (_) {
        _cloudSocket!.sink.add(jsonStr);
      }
    }

    // WebRTC Voice Tunnel management (cellular voice audio is handled natively by Vivo S1/AirPods)
    if (msg.type == 'CALL_DISCONNECTED') {
      voiceTunnel.closeVoiceTunnel();
    }
  }

  void connectCloudBridge() {
    if (!enableCloudBridge || cloudRelayUrl.trim().isEmpty || cloudRelayUrl.contains('yourdomain') || cloudRelayUrl.contains('onrender.com')) {
      logEvent('Cloud Bridge', 'Cloud bridge inactive (Local Wi-Fi / Hotspot Direct Mode)', ActivityType.info);
      return;
    }

    if (isCloudConnected) return;

    try {
      final uri = Uri.parse(cloudRelayUrl);
      _cloudSocket = WebSocketChannel.connect(uri);
      isCloudConnected = true;

      // Register host role
      _cloudSocket!.sink.add(RelayMessage.registerCloudSession(
        pairingKey: pairingKey,
        role: 'host',
      ).toJsonString());

      logEvent('Cloud Bridge', 'Connected to remote Cloud Relay ($cloudRelayUrl)', ActivityType.success);

      _cloudSocket!.stream.listen(
        (message) {
          final raw = message.toString();
          try {
            final msg = RelayMessage.fromJsonString(raw);
            if (msg.type == 'PING') {
              _cloudSocket?.sink.add(RelayMessage.pong().toJsonString());
              return;
            }
          } catch (_) {}
          _handleIncomingSocketMessage(raw);
        },
        onDone: () {
          isCloudConnected = false;
          _cloudSocket = null;
          if (enableCloudBridge) {
            logEvent('Cloud Bridge', 'Cloud socket disconnected. Retrying in 10s...', ActivityType.info);
            _scheduleCloudReconnect();
          }
        },
        onError: (_) {
          isCloudConnected = false;
          _cloudSocket = null;
          if (enableCloudBridge) {
            _scheduleCloudReconnect();
          }
        },
      );
    } catch (e) {
      isCloudConnected = false;
      _cloudSocket = null;
      if (enableCloudBridge) {
        _scheduleCloudReconnect();
      }
    }
  }

  void _scheduleCloudReconnect() {
    _cloudReconnectTimer?.cancel();
    _cloudReconnectTimer = Timer(const Duration(seconds: 10), () {
      if (!isCloudConnected && isRunning && enableCloudBridge) {
        connectCloudBridge();
      }
    });
  }

  void _handleIncomingSocketMessage(String rawJson) {
    try {
      var msg = RelayMessage.fromJsonString(rawJson);
      if (msg.type == 'ENCRYPTED_FRAME') {
        final cipher = E2eeCipher.fromKey(pairingKey);
        final dec = cipher.decrypt(msg.data['ciphertext']?.toString() ?? '');
        if (dec != null) {
          msg = RelayMessage.fromJsonString(dec);
        } else {
          debugPrint('[E2EE] Could not decrypt incoming cloud frame (key mismatch)');
          return;
        }
      }

      switch (msg.type) {
        case 'ACTION_DIAL':
          final num = msg.data['number']?.toString() ?? '';
          logEvent('Dial Request', 'Calling $num from iPhone', ActivityType.call);
          try {
            telephonyMonitor?.setActiveDialNumber(num);
          } catch (_) {}
          telephonyController.dialNumber(num);
          break;
        case 'ACTION_ANSWER':
          final nowAnswer = DateTime.now().millisecondsSinceEpoch;
          if (nowAnswer - _lastAnswerRequestTime < 2500) {
            debugPrint('[RELAY] ⚡ Ignored duplicate ACTION_ANSWER from client (${nowAnswer - _lastAnswerRequestTime}ms ago)');
            break;
          }
          _lastAnswerRequestTime = nowAnswer;
          logEvent('Answer Request', 'Call accepted on iPhone', ActivityType.call);
          telephonyController.answerCall();
          break;
        case 'ACTION_HANGUP':
          logEvent('Hangup Request', 'Call dropped from iPhone', ActivityType.call);
          telephonyController.hangupCall();
          voiceTunnel.closeVoiceTunnel();
          break;
        case 'ACTION_DTMF':
          final digit = msg.data['digit']?.toString() ?? '';
          logEvent('DTMF Keypress', 'Transmitted digit $digit', ActivityType.info);
          telephonyController.sendDtmf(digit);
          break;
        case 'ACTION_SEND_SMS':
          final recipient = msg.data['recipient']?.toString() ?? '';
          final message = msg.data['message']?.toString() ?? '';
          logEvent('Outgoing SMS', 'Sending SMS to $recipient: $message', ActivityType.info);
          telephonyController.sendSms(recipient, message).then((ok) {
            broadcast(RelayMessage.smsSentStatus(success: ok, recipient: recipient));
            logEvent('SMS Delivery', ok ? 'Dispatched successfully' : 'Failed to send', ok ? ActivityType.success : ActivityType.call);
          });
          break;
        case 'ACTION_SET_MOBILE_DATA':
          final enabled = msg.data['enabled'] as bool? ?? false;
          logEvent('Mobile Data', 'Setting mobile data to ${enabled ? "ON" : "OFF"} from iPhone', ActivityType.info);
          telephonyController.setMobileData(enabled).then((ok) {
            telemetryService?.updateAndBroadcast(force: true);
          });
          break;
        case 'ACTION_SET_DATA_SIM':
          final subId = msg.data['subId'] as int?;
          final slotIndex = msg.data['slotIndex'] as int? ?? 0;
          logEvent('Data SIM Switch', 'Switching data SIM to subId $subId (slot $slotIndex) from iPhone', ActivityType.info);
          if (subId != null) {
            telephonyController.setDataSim(subId).then((ok) {
              telemetryService?.updateAndBroadcast(force: true);
            });
          }
          break;
        case 'WEBRTC_OFFER':
        case 'WEBRTC_ANSWER':
        case 'WEBRTC_ICE_CANDIDATE':
          voiceTunnel.handleSignalingMessage(msg);
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('[ROUTER] Invalid frame: $e');
    }
  }

  Future<Response> _handleRestApi(Request request) async {
    try {
      final info = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final remote = info?.remoteAddress;
      if (remote != null && !remote.isLoopback) {
        _lastKnownClientAddress = remote;
      }
    } catch (_) {}

    final path = request.url.path;

    // 1. Status
    if (path == 'api/status') {
      return Response.ok(
        jsonEncode(currentCallState),
        headers: {'content-type': 'application/json', 'access-control-allow-origin': '*'},
      );
    }

    // 2. Answer
    if (path == 'api/answer') {
      telephonyController.answerCall();
      logEvent('Answer Triggered', 'via REST /api/answer', ActivityType.call);
      return Response.ok('{"status":"ok"}', headers: {'content-type': 'application/json'});
    }

    // 3. Hangup
    if (path == 'api/hangup') {
      telephonyController.hangupCall();
      logEvent('Hangup Triggered', 'via REST /api/hangup', ActivityType.call);
      return Response.ok('{"status":"ok"}', headers: {'content-type': 'application/json'});
    }

    // 4. Dial
    if (path == 'api/call') {
      String num = request.url.queryParameters['number'] ?? '';
      if (num.isEmpty) {
        try {
          final bodyStr = await request.readAsString();
          if (bodyStr.isNotEmpty) {
            final json = jsonDecode(bodyStr) as Map<String, dynamic>;
            num = json['number']?.toString() ?? '';
          }
        } catch (_) {}
      }
      if (num.isNotEmpty) {
        try {
          telephonyMonitor?.setActiveDialNumber(num);
        } catch (_) {}
        telephonyController.dialNumber(num);
        logEvent('Dial Triggered', 'Calling $num via REST', ActivityType.call);
      }
      return Response.ok('{"status":"ok","dialing":"$num"}', headers: {'content-type': 'application/json'});
    }

    // 5. DTMF
    if (path == 'api/dtmf') {
      String digit = request.url.queryParameters['digit'] ?? '';
      if (digit.isEmpty) {
        try {
          final bodyStr = await request.readAsString();
          if (bodyStr.isNotEmpty) {
            final json = jsonDecode(bodyStr) as Map<String, dynamic>;
            digit = json['digit']?.toString() ?? '';
          }
        } catch (_) {}
      }
      if (digit.isNotEmpty) {
        telephonyController.sendDtmf(digit);
      }
      return Response.ok('{"status":"ok","dtmf":"$digit"}', headers: {'content-type': 'application/json'});
    }

    // 6. History
  if (path == 'api/history') {
    if (contentService != null) {
      final daysStr = request.url.queryParameters['days'] ?? '60';
      final days = int.tryParse(daysStr) ?? 60;
      await contentService!.fetchCallHistory(days: days);
    }
    final list = cachedCallHistory.map((c) => c.toJson()).toList();
    return Response.ok(jsonEncode(list), headers: {'content-type': 'application/json'});
  }

  // 7. Contacts
  if (path == 'api/contacts') {
    if (cachedContacts.isEmpty && contentService != null) {
      await contentService!.fetchContacts();
    }
    final list = cachedContacts.map((c) => c.toJson()).toList();
    return Response.ok(jsonEncode(list), headers: {'content-type': 'application/json'});
  }

  // 8. Latest Call Recordings (Permanent sync)
  if (path == 'api/recordings/latest') {
    if (cachedContacts.isEmpty && contentService != null) {
      await contentService!.fetchContacts();
    }
    if (cachedCallHistory.isEmpty && contentService != null) {
      await contentService!.fetchCallHistory();
    }
    final limitStr = request.url.queryParameters['limit'] ?? '25';
    final limit = int.tryParse(limitStr) ?? 25;
    final recordings = await VivoRecordingService.instance.getLatestRecordings(
      limit: limit,
      cachedCallHistory: cachedCallHistory,
      cachedContacts: cachedContacts,
    );
    final list = recordings.map((r) => r.toJson()).toList();
    return Response.ok(jsonEncode(list), headers: {
      'content-type': 'application/json',
      'access-control-allow-origin': '*',
    });
  }

  // 8b. Call Recordings Listing by Number / Contact / Call Timestamp
  if (path == 'api/recordings') {
    if (cachedContacts.isEmpty && contentService != null) {
      await contentService!.fetchContacts();
    }
    if (cachedCallHistory.isEmpty && contentService != null) {
      await contentService!.fetchCallHistory();
    }

    final number = request.url.queryParameters['number'] ?? '';
    final nameParam = request.url.queryParameters['name'] ?? '';
    final tsStr = request.url.queryParameters['timestamp'] ?? '';
    final callTimestamp = int.tryParse(tsStr);
    final durStr = request.url.queryParameters['duration'] ?? '';
    final duration = int.tryParse(durStr);

    List<String> contactNames = [];
    if (nameParam.isNotEmpty) {
      contactNames.add(nameParam);
    }
    if (number.isNotEmpty) {
      for (final c in cachedContacts) {
        if (c.matchesNumber(number)) {
          if (!contactNames.contains(c.displayName)) {
            contactNames.add(c.displayName);
          }
        }
      }
    }
    final recordings = await VivoRecordingService.instance.getRecordingsForNumber(
      number,
      contactNames: contactNames,
      callTimestamp: callTimestamp,
      durationSeconds: duration,
      cachedCallHistory: cachedCallHistory,
      cachedContacts: cachedContacts,
    );
    final list = recordings.map((r) => r.toJson()).toList();
    return Response.ok(jsonEncode(list), headers: {
      'content-type': 'application/json',
      'access-control-allow-origin': '*',
    });
  }

  // 9. Call Recording Audio Streaming / Download
  if (path == 'api/recordings/audio') {
    final filename = request.url.queryParameters['file'] ?? '';
    final file = VivoRecordingService.instance.getRecordingFile(filename);
    if (file == null || !file.existsSync()) {
      return Response.notFound('Audio file not found');
    }

    final ext = filename.split('.').last.toLowerCase();
    String contentType = 'audio/mpeg';
    if (ext == 'm4a' || ext == 'mp4' || ext == 'aac') {
      contentType = 'audio/mp4';
    } else if (ext == 'amr') {
      contentType = 'audio/amr';
    } else if (ext == 'wav') {
      contentType = 'audio/wav';
    } else if (ext == 'ogg') {
      contentType = 'audio/ogg';
    }

    final length = file.lengthSync();
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': contentType,
        'content-length': length.toString(),
        'accept-ranges': 'bytes',
        'access-control-allow-origin': '*',
        'content-disposition': 'inline; filename="$filename"',
      },
    );
  }

  // 10. All SMS Messages Sync
  if (path == 'api/messages' || path == 'api/sms') {
    final limitStr = request.url.queryParameters['limit'] ?? '500';
    final limit = int.tryParse(limitStr) ?? 500;
    final list = await telephonyController.getAllSms(limit: limit);
    return Response.ok(
      jsonEncode(list),
      headers: {'content-type': 'application/json', 'access-control-allow-origin': '*'},
    );
  }

  // 11. Outgoing SMS Dispatch via REST
  if (path == 'api/sms/send') {
    try {
      final bodyStr = await request.readAsString();
      final json = jsonDecode(bodyStr) as Map<String, dynamic>;
      final recipient = json['recipient']?.toString() ?? '';
      final message = json['message']?.toString() ?? '';
      final ok = await telephonyController.sendSms(recipient, message);
      logEvent('SMS Dispatched', 'Sent SMS to $recipient via REST (${ok ? "Success" : "Failed"})', ok ? ActivityType.success : ActivityType.call);
      return Response.ok(
        jsonEncode({'status': ok ? 'ok' : 'error', 'recipient': recipient}),
        headers: {'content-type': 'application/json', 'access-control-allow-origin': '*'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // 11. Contact Avatar JPEG Stream
  if (path == 'api/contacts/avatar') {
    final id = request.url.queryParameters['id'] ?? '';
    if (id.isNotEmpty) {
      try {
        final bytes = await FastContacts.getContactImage(id);
        if (bytes != null && bytes.isNotEmpty) {
          return Response.ok(
            bytes,
            headers: {
              'content-type': 'image/jpeg',
              'cache-control': 'public, max-age=86400',
              'access-control-allow-origin': '*',
            },
          );
        }
      } catch (_) {}
    }
    return Response.notFound('No avatar found');
  }

  // 12. Hotspot State & Tethering Management
  if (path == 'api/hotspot/status') {
    final active = await telephonyController.isHotspotActive();
    return Response.ok(
      jsonEncode({'active': active, 'gateway': '192.168.43.1'}),
      headers: {'content-type': 'application/json', 'access-control-allow-origin': '*'},
    );
  }

  if (path == 'api/hotspot/start') {
    final res = await telephonyController.openTetherSettings();
    return Response.ok(
      jsonEncode({'success': res}),
      headers: {'content-type': 'application/json', 'access-control-allow-origin': '*'},
    );
  }

  // 13. Cellular Mobile Data Toggle via REST
  if (path == 'api/data/toggle' || path == 'api/data/enable' || path == 'api/data/disable') {
    try {
      bool enable = true;
      if (path == 'api/data/disable') {
        enable = false;
      } else if (request.url.queryParameters.containsKey('enabled')) {
        enable = request.url.queryParameters['enabled'] == 'true' || request.url.queryParameters['enabled'] == '1';
      } else {
        try {
          final bodyStr = await request.readAsString();
          if (bodyStr.isNotEmpty) {
            final json = jsonDecode(bodyStr) as Map<String, dynamic>;
            if (json.containsKey('enabled')) {
              enable = json['enabled'] == true || json['enabled'] == 'true' || json['enabled'] == 1;
            }
          }
        } catch (_) {}
      }
      final ok = await telephonyController.setMobileData(enable);
      telemetryService?.updateAndBroadcast(force: true);
      logEvent('Mobile Data', 'Cellular data toggled ${enable ? "ON" : "OFF"} via REST ($ok)', ActivityType.info);
      return Response.ok(
        jsonEncode({'status': ok ? 'ok' : 'error', 'enabled': enable}),
        headers: {'content-type': 'application/json', 'access-control-allow-origin': '*'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // 14. Cellular Data SIM Switch via REST
  if (path == 'api/data/sim') {
    try {
      int? subId;
      if (request.url.queryParameters.containsKey('subId')) {
        subId = int.tryParse(request.url.queryParameters['subId']!);
      } else {
        try {
          final bodyStr = await request.readAsString();
          if (bodyStr.isNotEmpty) {
            final json = jsonDecode(bodyStr) as Map<String, dynamic>;
            subId = json['subId'] as int?;
          }
        } catch (_) {}
      }
      if (subId != null) {
        final ok = await telephonyController.setDataSim(subId);
        telemetryService?.updateAndBroadcast(force: true);
        logEvent('Data SIM Switch', 'Switched data SIM to subId: $subId via REST ($ok)', ActivityType.info);
        return Response.ok(
          jsonEncode({'status': ok ? 'ok' : 'error', 'subId': subId}),
          headers: {'content-type': 'application/json', 'access-control-allow-origin': '*'},
        );
      } else {
        return Response.badRequest(body: '{"error":"Missing subId"}', headers: {'content-type': 'application/json'});
      }
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // 13. Low-Bitrate Silence Stream (Maintains iOS Wi-Fi interface in deep sleep)
  if (path == 'api/stream/silence') {
    StreamController<List<int>>? streamController;
    Timer? pushTimer;

    streamController = StreamController<List<int>>(
      onListen: () {
        streamController!.add(_createSilenceWavHeader(sampleRate: 8000));
        final chunk = _createSubBassPcmChunk(sampleRate: 8000, durationSeconds: 1.0);
        streamController.add(chunk);
        pushTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!streamController!.isClosed) {
            streamController.add(chunk);
          }
        });
      },
      onCancel: () {
        pushTimer?.cancel();
        streamController?.close();
      },
    );

    return Response.ok(
      streamController.stream,
      headers: {
        'content-type': 'audio/wav',
        'cache-control': 'no-cache, no-store',
        'connection': 'keep-alive',
        'access-control-allow-origin': '*',
      },
    );
  }

    return Response.notFound('Not found');
  }

  /// Generates a valid RIFF/WAVE header for infinite low-power 8kHz mono audio
  List<int> _createSilenceWavHeader({int sampleRate = 8000}) {
    final byteRate = sampleRate * 1 * 2;
    const blockAlign = 2;
    const bitsPerSample = 16;
    const dataSize = 0x7FFFF000;
    final chunkSize = 36 + dataSize;

    final bytes = BytesBuilder();
    bytes.add('RIFF'.codeUnits);
    bytes.add([
      chunkSize & 0xFF,
      (chunkSize >> 8) & 0xFF,
      (chunkSize >> 16) & 0xFF,
      (chunkSize >> 24) & 0xFF,
    ]);
    bytes.add('WAVE'.codeUnits);
    bytes.add('fmt '.codeUnits);
    bytes.add([16, 0, 0, 0]);
    bytes.add([1, 0]);
    bytes.add([1, 0]);
    bytes.add([
      sampleRate & 0xFF,
      (sampleRate >> 8) & 0xFF,
      (sampleRate >> 16) & 0xFF,
      (sampleRate >> 24) & 0xFF,
    ]);
    bytes.add([
      byteRate & 0xFF,
      (byteRate >> 8) & 0xFF,
      (byteRate >> 16) & 0xFF,
      (byteRate >> 24) & 0xFF,
    ]);
    bytes.add([blockAlign, 0]);
    bytes.add([bitsPerSample, 0]);
    bytes.add('data'.codeUnits);
    bytes.add([
      dataSize & 0xFF,
      (dataSize >> 8) & 0xFF,
      (dataSize >> 16) & 0xFF,
      (dataSize >> 24) & 0xFF,
    ]);
    return bytes.toBytes();
  }

  /// Generates a lightweight 1-second 20Hz sub-bass PCM chunk (inaudible, prevents mediaserverd idle kill)
  Uint8List _createSubBassPcmChunk({int sampleRate = 8000, double durationSeconds = 1.0}) {
    final totalSamples = (sampleRate * durationSeconds).toInt();
    final pcmBytes = Uint8List(totalSamples * 2);
    final buffer = ByteData.view(pcmBytes.buffer);
    const frequency = 20.0;
    const amplitude = 30.0;
    for (int i = 0; i < totalSamples; i++) {
      final angle = 2.0 * math.pi * frequency * i / sampleRate;
      final sample = (math.sin(angle) * amplitude).toInt();
      buffer.setInt16(i * 2, sample, Endian.little);
    }
    return pcmBytes;
  }
}

