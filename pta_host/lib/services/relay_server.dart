import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

class RelayServer {
  static const int port = 8080;
  static const int udpPort = 8081;
  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  final TelephonyController telephonyController;
  AndroidContentService? contentService;
  final voiceTunnel = VoiceTunnelService();

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

  void logEvent(String title, String subtitle, ActivityType type) {
    final entry = ActivityLog(title: title, subtitle: subtitle, type: type);
    activityLogs.insert(0, entry);
    if (activityLogs.length > 200) activityLogs.removeLast();
    _activityStream.add(entry);
    debugPrint('[ACTIVITY] ${entry.timeFormatted} | $title - $subtitle');
  }

  Timer? _idleTimer;
  int _lastDisconnectTime = 0;
  bool enable30MinIdleShutdown = false; // Default false (Relay stays ON permanently)

  void startVoiceTunnel() {
    logEvent('Starting Voice Tunnel', 'Initiating WebRTC Audio Stream with iPhone', ActivityType.info);
    voiceTunnel.startVoiceTunnel(
      isCaller: true,
      sendSignaling: (msg) {
        broadcast(msg);
      },
    );
  }

  void stopVoiceTunnel() {
    logEvent('Stopping Voice Tunnel', 'Closing WebRTC Audio Stream', ActivityType.info);
    voiceTunnel.closeVoiceTunnel();
  }

  /// Starts the embedded HTTP & WebSocket server on 0.0.0.0:8080 and UDP discovery on 8081
  Future<bool> startServer() async {
    if (_server != null) return true;

    try {
      final wsHandler = webSocketHandler((WebSocketChannel socket, String? protocol) {
        _connectedSockets.add(socket);
        _lastDisconnectTime = 0;
        logEvent('Client Connected', 'iPhone paired via WebSocket', ActivityType.success);

        // Send initial state & device status
        socket.sink.add(jsonEncode({
          'type': 'SYNC_STATE',
          'data': currentCallState,
        }));

        socket.stream.listen(
          (message) {
            final raw = message.toString();
            try {
              final msg = RelayMessage.fromJsonString(raw);
              if (msg.type == 'PING') {
                socket.sink.add(RelayMessage.pong().toJsonString());
                return;
              }
            } catch (_) {}
            _handleIncomingSocketMessage(raw);
          },
          onDone: () {
            _connectedSockets.remove(socket);
            _lastDisconnectTime = DateTime.now().millisecondsSinceEpoch;
            logEvent('Client Disconnected', 'iPhone socket closed', ActivityType.info);
          },
          onError: (err) {
            _connectedSockets.remove(socket);
            _lastDisconnectTime = DateTime.now().millisecondsSinceEpoch;
            logEvent('Socket Error', err.toString(), ActivityType.error);
          },
        );
      });

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

  void _startUdpDiscoveryListener() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      _udpSocket?.broadcastEnabled = true;
      _udpSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket?.receive();
          if (dg != null) {
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

    if (isCloudConnected && _cloudSocket != null) {
      try {
        _cloudSocket!.sink.add(jsonStr);
      } catch (_) {}
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
      final msg = RelayMessage.fromJsonString(rawJson);
      switch (msg.type) {
        case 'ACTION_DIAL':
          final num = msg.data['number']?.toString() ?? '';
          logEvent('Dial Request', 'Calling $num from iPhone', ActivityType.call);
          telephonyController.dialNumber(num);
          break;
        case 'ACTION_ANSWER':
          logEvent('Answer Request', 'Call accepted on iPhone', ActivityType.call);
          telephonyController.answerCall();
          break;
        case 'ACTION_HANGUP':
          logEvent('Hangup Request', 'Call dropped from iPhone', ActivityType.call);
          telephonyController.hangupCall();
          break;
        case 'ACTION_DTMF':
          final digit = msg.data['digit']?.toString() ?? '';
          logEvent('DTMF Keypress', 'Transmitted digit $digit', ActivityType.info);
          telephonyController.sendDtmf(digit);
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
    if (cachedCallHistory.isEmpty && contentService != null) {
      await contentService!.fetchCallHistory();
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

    return Response.notFound('Not found');
  }
}

