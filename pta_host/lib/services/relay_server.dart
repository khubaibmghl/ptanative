import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pta_shared/pta_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/activity_log.dart';
import 'telephony_controller.dart';

class RelayServer {
  static const int port = 8080;
  HttpServer? _server;
  final TelephonyController telephonyController;

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

  /// Starts the embedded HTTP & WebSocket server on 0.0.0.0:8080
  Future<bool> startServer() async {
    if (_server != null) return true;

    try {
      final wsHandler = webSocketHandler((WebSocketChannel socket, String? protocol) {
        _connectedSockets.add(socket);
        logEvent('Client Connected', 'iPhone 15 Pro paired via WebSocket', ActivityType.success);

        // Send initial state & device status
        socket.sink.add(jsonEncode({
          'type': 'SYNC_STATE',
          'data': currentCallState,
        }));

        socket.stream.listen(
          (message) {
            _handleIncomingSocketMessage(message.toString());
          },
          onDone: () {
            _connectedSockets.remove(socket);
            logEvent('Client Disconnected', 'iPhone socket closed', ActivityType.info);
          },
          onError: (err) {
            _connectedSockets.remove(socket);
            logEvent('Socket Error', err.toString(), ActivityType.error);
          },
        );
      });

      final cascade = Cascade().add(wsHandler).add(_handleRestApi);

      _server = await shelf_io.serve(cascade.handler, InternetAddress.anyIPv4, port);
      logEvent('Server Started', 'Listening on 0.0.0.0:$port', ActivityType.success);
      return true;
    } catch (e) {
      logEvent('Server Error', 'Failed to bind port $port: $e', ActivityType.error);
      return false;
    }
  }

  /// Stops the server cleanly
  Future<void> stopServer() async {
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
        default:
          break;
      }
    } catch (e) {
      debugPrint('[ROUTER] Invalid frame: $e');
    }
  }

  Response _handleRestApi(Request request) {
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
      final num = request.url.queryParameters['number'] ?? '';
      if (num.isNotEmpty) {
        telephonyController.dialNumber(num);
        logEvent('Dial Triggered', 'Calling $num via REST', ActivityType.call);
      }
      return Response.ok('{"status":"ok","dialing":"$num"}', headers: {'content-type': 'application/json'});
    }

    // 5. DTMF
    if (path == 'api/dtmf') {
      final digit = request.url.queryParameters['digit'] ?? '';
      if (digit.isNotEmpty) {
        telephonyController.sendDtmf(digit);
      }
      return Response.ok('{"status":"ok","dtmf":"$digit"}', headers: {'content-type': 'application/json'});
    }

    // 6. History
    if (path == 'api/history') {
      final list = cachedCallHistory.map((c) => c.toJson()).toList();
      return Response.ok(jsonEncode(list), headers: {'content-type': 'application/json'});
    }

    // 7. Contacts
    if (path == 'api/contacts') {
      final list = cachedContacts.map((c) => c.toJson()).toList();
      return Response.ok(jsonEncode(list), headers: {'content-type': 'application/json'});
    }

    return Response.notFound('Not found');
  }
}

