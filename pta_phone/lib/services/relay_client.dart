import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import 'callkit_service.dart';

enum PhoneCallState { dialing, ringing, connected }

class ActiveCallInfo {
  final String number;
  final String callerName;
  final String? label;
  final int startTime; // Epoch millis (0 if not answered yet)
  final bool isIncoming;
  final PhoneCallState state;

  ActiveCallInfo({
    required this.number,
    required this.callerName,
    this.label,
    required this.startTime,
    required this.isIncoming,
    this.state = PhoneCallState.connected,
  });
}

/// WebSocket Client & REST Bridge connecting to Vivo S1 Host Engine
class RelayClient {
  static final RelayClient instance = RelayClient._init();
  RelayClient._init();

  String hostIp = '192.168.23.68';
  int hostPort = 8080;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _lastPongTime = 0;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  // Stream Controllers
  final _connectionController = StreamController<bool>.broadcast();
  final _statusController = StreamController<DeviceStatusModel>.broadcast();
  final _activeCallController = StreamController<ActiveCallInfo?>.broadcast();
  final _smsController = StreamController<SmsMessageModel>.broadcast();
  final _syncController = StreamController<void>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<DeviceStatusModel> get statusStream => _statusController.stream;
  Stream<ActiveCallInfo?> get activeCallStream => _activeCallController.stream;
  Stream<SmsMessageModel> get smsStream => _smsController.stream;
  Stream<void> get syncStream => _syncController.stream;

  ActiveCallInfo? currentActiveCall;
  DeviceStatusModel? lastStatus;

  String cloudRelayUrl = '';
  String pairingKey = 'pta_native_default';
  bool isConnectedViaCloud = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    hostIp = prefs.getString('host_ip') ?? '192.168.23.68';
    hostPort = prefs.getInt('host_port') ?? 8080;
    cloudRelayUrl = prefs.getString('cloud_url') ?? '';
    pairingKey = prefs.getString('pairing_key') ?? 'pta_native_default';

    // Try auto-discovering Vivo S1 host on startup
    final discoveredIp = await discoverHostIp();
    if (discoveredIp != null && discoveredIp.isNotEmpty) {
      hostIp = discoveredIp;
      await prefs.setString('host_ip', hostIp);
    }

    connect();
    _startReconnectLoop();
  }

  /// UDP Broadcast Auto-Discovery across local subnet and hotspot interfaces
  Future<String?> discoverHostIp() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final msg = 'PTA_DISCOVER_REQUEST'.codeUnits;

      // Broadcast to standard broadcast address & port 8081
      socket.send(msg, InternetAddress('255.255.255.255'), 8081);

      // Probe common Android hotspot default gateways (Vivo / Samsung / Pixel)
      const commonHotspotGateways = [
        '192.168.43.1',
        '192.168.170.1',
        '192.168.23.1',
        '192.168.1.1',
        '10.0.0.1',
      ];
      for (final gw in commonHotspotGateways) {
        socket.send(msg, InternetAddress(gw), 8081);
      }

      // Probe active local subnets
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            socket.send(msg, InternetAddress(subnetBroadcast), 8081);
            final hotspotGateway = '${parts[0]}.${parts[1]}.${parts[2]}.1';
            socket.send(msg, InternetAddress(hotspotGateway), 8081);
          }
        }
      }

      final completer = Completer<String?>();
      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg != null) {
            try {
              final reply = String.fromCharCodes(dg.data);
              if (reply.contains('pta_host')) {
                if (!completer.isCompleted) {
                  completer.complete(dg.address.address);
                }
              }
            } catch (_) {}
          }
        }
      });

      final discoveredIp = await completer.future.timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
      socket.close();

      if (discoveredIp != null && discoveredIp.isNotEmpty) {
        hostIp = discoveredIp;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('host_ip', hostIp);
      }
      return discoveredIp;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateHostConfig(String ip, int port, {String? cloudUrl, String? key}) async {
    hostIp = ip.trim();
    hostPort = port;
    if (cloudUrl != null) cloudRelayUrl = cloudUrl.trim();
    if (key != null) pairingKey = key.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host_ip', hostIp);
    await prefs.setInt('host_port', hostPort);
    await prefs.setString('cloud_url', cloudRelayUrl);
    await prefs.setString('pairing_key', pairingKey);

    disconnect();
    connect();
  }

  bool _shouldUseCloudFallback() {
    final url = cloudRelayUrl.trim();
    return url.isNotEmpty && !url.contains('onrender.com') && !url.contains('yourdomain');
  }

  void connect() {
    if (_isConnected) return;

    try {
      final wsUrl = Uri.parse('ws://$hostIp:$hostPort/ws');
      _channel = WebSocketChannel.connect(wsUrl);

      _wsSubscription?.cancel();
      _wsSubscription = _channel!.stream.listen(
        _onMessageReceived,
        onDone: _onDisconnected,
        onError: (err) {
          if (_shouldUseCloudFallback()) {
            _connectCloudFallback();
          } else {
            _onDisconnected();
          }
        },
        cancelOnError: true,
      );

      _lastPongTime = DateTime.now().millisecondsSinceEpoch;
      _startPingHeartbeat();
    } catch (e) {
      if (_shouldUseCloudFallback()) {
        _connectCloudFallback();
      } else {
        _onDisconnected();
      }
    }
  }

  void _connectCloudFallback() {
    if (_isConnected) return;

    try {
      final wsUrl = Uri.parse(cloudRelayUrl);
      _channel = WebSocketChannel.connect(wsUrl);

      _wsSubscription?.cancel();
      _wsSubscription = _channel!.stream.listen(
        _onMessageReceived,
        onDone: _onDisconnected,
        onError: (err) => _onDisconnected(),
        cancelOnError: true,
      );

      _lastPongTime = DateTime.now().millisecondsSinceEpoch;

      // Send cloud session registration
      _channel!.sink.add(RelayMessage.registerCloudSession(
        pairingKey: pairingKey,
        role: 'client',
      ).toJsonString());

      _startPingHeartbeat();
    } catch (_) {
      _onDisconnected();
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _isConnected = false;
    isConnectedViaCloud = false;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _connectionController.add(false);
  }

  void _onDisconnected() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _isConnected = false;
    isConnectedViaCloud = false;
    _connectionController.add(false);
  }

  void _startPingHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_isConnected && _channel != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastPongTime > 24000) {
          // Socket dead timeout
          disconnect();
          return;
        }
        try {
          _channel!.sink.add(RelayMessage.ping().toJsonString());
        } catch (_) {
          _onDisconnected();
        }
      }
    });
  }

  void _startReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!_isConnected) {
        // Attempt UDP discovery on reconnect if lost
        final discoveredIp = await discoverHostIp();
        if (discoveredIp != null && discoveredIp.isNotEmpty && discoveredIp != hostIp) {
          hostIp = discoveredIp;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('host_ip', hostIp);
        }
        connect();
      }
    });
  }

  void _onMessageReceived(dynamic message) async {
    try {
      final raw = message.toString();
      final msg = RelayMessage.fromJsonString(raw);

      if (!_isConnected) {
        _isConnected = true;
        _connectionController.add(true);
        syncAll();
      }

      switch (msg.type) {
        case 'PONG':
          _lastPongTime = DateTime.now().millisecondsSinceEpoch;
          break;

        case 'INCOMING_RING':
          final number = msg.data['number'] as String? ?? 'Cellular Call';
          final name = msg.data['name'] as String? ?? '';
          final label = msg.data['label'] as String?;

          // Show native Apple CallKit Incoming Screen (Slide to Answer)
          try {
            await CallKitService.instance.showIncomingCall(
              callId: CallKitService.generateUuid(),
              callerName: name,
              handle: number,
              label: label,
            );
          } catch (e) {
            debugPrint('[RELAY] Exception showing CallKit incoming call: $e');
          }

          currentActiveCall = ActiveCallInfo(
            number: number,
            callerName: name,
            label: label,
            startTime: 0,
            isIncoming: true,
            state: PhoneCallState.ringing,
          );
          _activeCallController.add(currentActiveCall);
          break;

        case 'CALL_DIALING':
          final dialNum = msg.data['number'] as String? ?? '';
          final dialContact = await DatabaseHelper.instance.findContactByNumber(dialNum);
          currentActiveCall = ActiveCallInfo(
            number: dialNum.isNotEmpty ? dialNum : (currentActiveCall?.number ?? 'Cellular Call'),
            callerName: dialContact?.displayName ?? (currentActiveCall?.callerName ?? ''),
            label: dialContact?.getLabelForNumber(dialNum) ?? currentActiveCall?.label,
            startTime: 0,
            isIncoming: false,
            state: PhoneCallState.dialing,
          );
          _activeCallController.add(currentActiveCall);
          break;

        case 'CALL_ACTIVE':
          final number = msg.data['number'] as String? ?? '';
          final isAnswered = msg.data['isAnswered'] as bool? ?? (msg.data['startTime'] != null && (msg.data['startTime'] as int) > 0);
          final startTimeRaw = msg.data['startTime'] as int? ?? 0;
          final startTimeMs = (isAnswered && startTimeRaw > 0)
              ? (startTimeRaw < 100000000000 ? startTimeRaw * 1000 : startTimeRaw)
              : 0;

          final contact = await DatabaseHelper.instance.findContactByNumber(number);
          currentActiveCall = ActiveCallInfo(
            number: number.isNotEmpty ? number : (currentActiveCall?.number ?? 'Cellular Call'),
            callerName: contact?.displayName ?? (currentActiveCall?.callerName ?? ''),
            label: contact?.getLabelForNumber(number) ?? currentActiveCall?.label,
            startTime: startTimeMs,
            isIncoming: currentActiveCall?.isIncoming ?? false,
            state: isAnswered && startTimeMs > 0 ? PhoneCallState.connected : PhoneCallState.dialing,
          );
          _activeCallController.add(currentActiveCall);
          break;

        case 'CALL_DISCONNECTED':
          final number = msg.data['number'] as String? ?? (currentActiveCall?.number ?? 'Unknown');
          final duration = msg.data['duration'] as int? ?? 0;

          // End native Apple CallKit
          await CallKitService.instance.endAllCalls();

          // Save to local SQLite call log
          final contact = await DatabaseHelper.instance.findContactByNumber(number);
          final log = CallLogModel(
            id: DateTime.now().millisecondsSinceEpoch,
            remoteNumber: number,
            callerName: contact?.displayName ?? (currentActiveCall?.callerName ?? ''),
            numberLabel: contact?.getLabelForNumber(number) ?? currentActiveCall?.label,
            callType: duration == 0 && (currentActiveCall?.isIncoming ?? false)
                ? CallType.missed
                : (currentActiveCall?.isIncoming ?? false ? CallType.incoming : CallType.outgoing),
            serviceType: ServiceType.zongGsm,
            durationSeconds: duration,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
          await DatabaseHelper.instance.saveCallLog(log);
          _syncController.add(null);

          currentActiveCall = null;
          _activeCallController.add(null);
          break;

        case 'CONTACTS_LIST':
          try {
            final List<dynamic> list = msg.data['contacts'] as List<dynamic>? ?? [];
            final contacts = list.map((c) => ContactModel.fromJson(Map<String, dynamic>.from(c))).toList();
            await DatabaseHelper.instance.syncContacts(contacts);
            _syncController.add(null);
          } catch (e) {
            debugPrint('[RELAY] Exception processing CONTACTS_LIST: $e');
          }
          break;

        case 'CALL_HISTORY':
          try {
            final List<dynamic> list = msg.data['history'] as List<dynamic>? ?? [];
            for (final item in list) {
              final log = CallLogModel.fromJson(Map<String, dynamic>.from(item));
              await DatabaseHelper.instance.saveCallLog(log);
            }
            _syncController.add(null);
          } catch (e) {
            debugPrint('[RELAY] Exception processing CALL_HISTORY: $e');
          }
          break;

        case 'SMS_RECEIVED':
          final sms = SmsMessageModel.fromJson(msg.data);
          await DatabaseHelper.instance.saveMessage(sms);
          _smsController.add(sms);
          break;

        case 'DEVICE_STATUS':
          final status = DeviceStatusModel.fromJson(msg.data);
          lastStatus = status;
          _statusController.add(status);
          break;
      }
    } catch (_) {}
  }

  // --- Real-time Commands (WebSocket Priority with REST Fallback) ---

  Future<bool> dialNumber(String number) async {
    final clean = number.trim();
    if (clean.isEmpty) return false;

    final contact = await DatabaseHelper.instance.findContactByNumber(clean);
    currentActiveCall = ActiveCallInfo(
      number: clean,
      callerName: contact?.displayName ?? '',
      label: contact?.getLabelForNumber(clean),
      startTime: 0,
      isIncoming: false,
      state: PhoneCallState.dialing,
    );
    _activeCallController.add(currentActiveCall);

    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(RelayMessage.actionDial(clean).toJsonString());
        return true;
      } catch (_) {}
    }

    // REST Fallback
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/call?number=${Uri.encodeComponent(clean)}');
      final res = await http.post(uri);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> answerCall() async {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(RelayMessage.actionAnswer().toJsonString());
        return true;
      } catch (_) {}
    }

    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/answer');
      final res = await http.post(uri);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hangupCall() async {
    await CallKitService.instance.endAllCalls();
    currentActiveCall = null;
    _activeCallController.add(null);

    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(RelayMessage.actionHangup().toJsonString());
        return true;
      } catch (_) {}
    }

    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/hangup');
      final res = await http.post(uri);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendDtmf(String digit) async {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(RelayMessage.actionDtmf(digit).toJsonString());
        return true;
      } catch (_) {}
    }

    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/dtmf?digit=${Uri.encodeComponent(digit)}');
      final res = await http.post(uri);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncAll() async {
    await fetchContacts();
    await fetchHistory();
  }

  Future<void> fetchContacts() async {
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/contacts');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        final contacts = list.map((c) => ContactModel.fromJson(Map<String, dynamic>.from(c))).toList();
        await DatabaseHelper.instance.syncContacts(contacts);
        _syncController.add(null);
      }
    } catch (_) {}
  }

  Future<void> fetchHistory() async {
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/history');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        for (final item in list) {
          final log = CallLogModel.fromJson(Map<String, dynamic>.from(item));
          await DatabaseHelper.instance.saveCallLog(log);
        }
        _syncController.add(null);
      }
    } catch (_) {}
  }
}

