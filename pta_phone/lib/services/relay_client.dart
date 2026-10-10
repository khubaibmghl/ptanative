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
  final int durationSeconds;
  final bool isIncoming;
  final PhoneCallState state;

  ActiveCallInfo({
    required this.number,
    required this.callerName,
    this.label,
    required this.startTime,
    this.durationSeconds = 0,
    required this.isIncoming,
    this.state = PhoneCallState.connected,
  });
}

/// WebSocket Client & REST Bridge connecting to Vivo S1 Host Engine
class RelayClient {
  static final RelayClient instance = RelayClient._init();
  RelayClient._init();

  String hostIp = '192.168.43.1';
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
  final _missedCallController = StreamController<CallLogModel>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<DeviceStatusModel> get statusStream => _statusController.stream;
  Stream<ActiveCallInfo?> get activeCallStream => _activeCallController.stream;
  Stream<SmsMessageModel> get smsStream => _smsController.stream;
  Stream<void> get syncStream => _syncController.stream;
  Stream<CallLogModel> get missedCallStream => _missedCallController.stream;

  ActiveCallInfo? currentActiveCall;
  DeviceStatusModel? lastStatus;
  final List<String> diagnosticLogs = [];
  final VoiceTunnelService voiceTunnel = VoiceTunnelService();

  List<SavedConnection> savedConnections = [
    SavedConnection(id: 'hotspot_default', name: 'Vivo S1 Hotspot', ip: '192.168.43.1', port: 8080, isDefaultHotspot: true),
    SavedConnection(id: 'home_wifi', name: 'Home Wi-Fi', ip: '192.168.23.68', port: 8080, isDefaultHotspot: false),
  ];

  Future<void> loadSavedConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_connections');
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        savedConnections = list.map((item) => SavedConnection.fromJson(Map<String, dynamic>.from(item))).toList();
      }
      if (savedConnections.isEmpty) {
        savedConnections = [
          SavedConnection(id: 'hotspot_default', name: 'Vivo S1 Hotspot', ip: '192.168.43.1', port: 8080, isDefaultHotspot: true),
          SavedConnection(id: 'home_wifi', name: 'Home Wi-Fi', ip: '192.168.23.68', port: 8080, isDefaultHotspot: false),
        ];
      }
    } catch (_) {}
  }

  Future<void> saveSavedConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(savedConnections.map((c) => c.toJson()).toList());
      await prefs.setString('saved_connections', raw);
    } catch (_) {}
  }

  Future<void> addSavedConnection(String name, String ip, int port) async {
    final cleanIp = ip.trim();
    if (cleanIp.isEmpty) return;
    final newConn = SavedConnection(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim().isNotEmpty ? name.trim() : cleanIp,
      ip: cleanIp,
      port: port,
      isDefaultHotspot: cleanIp == '192.168.43.1',
    );
    savedConnections.add(newConn);
    await saveSavedConnections();
    _connectionController.add(_isConnected);
  }

  Future<void> removeSavedConnection(String id) async {
    savedConnections.removeWhere((c) => c.id == id);
    await saveSavedConnections();
    _connectionController.add(_isConnected);
  }

  Future<void> switchToConnection(SavedConnection conn) async {
    logDiagnostic('⚡ 1-Tap switching to: ${conn.name} (${conn.ip}:${conn.port})');
    hostIp = conn.ip.trim();
    hostPort = conn.port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host_ip', hostIp);
    await prefs.setInt('host_port', hostPort);
    disconnect();
    connect();
  }

  void logDiagnostic(String text) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final entry = '[$timeStr] $text';
    diagnosticLogs.insert(0, entry);
    if (diagnosticLogs.length > 150) diagnosticLogs.removeLast();
    debugPrint('[DIAGNOSTIC] $entry');
  }

  String cloudRelayUrl = '';
  String pairingKey = 'pta_native_default';
  bool isConnectedViaCloud = false;

  Future<void> init() async {
    await loadSavedConnections();
    final prefs = await SharedPreferences.getInstance();
    hostIp = prefs.getString('host_ip') ?? '192.168.43.1';
    hostPort = prefs.getInt('host_port') ?? 8080;
    cloudRelayUrl = prefs.getString('cloud_url') ?? '';
    pairingKey = prefs.getString('pairing_key') ?? 'pta_native_default';

    // Instant gateway probe / discovery on startup
    final discoveredIp = await discoverHostIp();
    if (discoveredIp != null && discoveredIp.isNotEmpty) {
      hostIp = discoveredIp;
      await prefs.setString('host_ip', hostIp);
    }

    connect();
    _startReconnectLoop();
  }

  /// Instant HTTP check of the local Hotspot / Wi-Fi router gateway
  Future<String?> probeDirectGateway() async {
    try {
      final candidateIps = <String>{'192.168.43.1', '192.168.23.1', '192.168.1.1'};
      try {
        final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4 && parts[0] != '127') {
              candidateIps.add('${parts[0]}.${parts[1]}.${parts[2]}.1');
            }
          }
        }
      } catch (_) {}

      for (final ip in candidateIps) {
        try {
          final uri = Uri.parse('http://$ip:$hostPort/api/status');
          final res = await http.get(uri).timeout(const Duration(milliseconds: 600));
          if (res.statusCode == 200) {
            logDiagnostic('⚡ Gateway direct-probe found host: $ip');
            return ip;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  /// UDP Broadcast & Direct Gateway Auto-Discovery
  Future<String?> discoverHostIp() async {
    // 1. First probe Hotspot / Wi-Fi Gateway (<subnet>.1) directly for instant sub-600ms match
    final directIp = await probeDirectGateway();
    if (directIp != null && directIp.isNotEmpty) {
      hostIp = directIp;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('host_ip', hostIp);
      return directIp;
    }

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
    // If targeting local hotspot or private subnet, NEVER attempt cloud fallback to avoid DNS lockup on dry connection
    if (hostIp.startsWith('192.168.') || hostIp.startsWith('10.') || hostIp.startsWith('172.')) {
      return false;
    }
    final url = cloudRelayUrl.trim();
    return url.isNotEmpty && !url.contains('onrender.com') && !url.contains('yourdomain');
  }

  /// Transmits a RelayMessage frame with automatic E2EE encryption over WAN/Cloud
  void _sendRawMessage(RelayMessage msg) {
    if (_channel == null) return;
    try {
      final jsonStr = msg.toJsonString();
      if (isConnectedViaCloud) {
        final cipher = E2eeCipher.fromKey(pairingKey);
        final enc = cipher.encrypt(jsonStr);
        _channel!.sink.add(RelayMessage.encryptedFrame(enc).toJsonString());
      } else {
        _channel!.sink.add(jsonStr);
      }
    } catch (e) {
      logDiagnostic('Socket send error: $e');
    }
  }

  void connect() {
    if (_isConnected) return;
    isConnectedViaCloud = false;

    try {
      final wsUrl = Uri.parse('ws://$hostIp:$hostPort/ws');
      logDiagnostic('Connecting to WebSocket: $wsUrl');
      _channel = WebSocketChannel.connect(wsUrl);

      _wsSubscription?.cancel();
      _wsSubscription = _channel!.stream.listen(
        _onMessageReceived,
        onDone: _onDisconnected,
        onError: (err) {
          logDiagnostic('Socket Error: $err');
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
      logDiagnostic('Connect Exception: $e');
      if (_shouldUseCloudFallback()) {
        _connectCloudFallback();
      } else {
        _onDisconnected();
      }
    }
  }

  void _connectCloudFallback() {
    if (_isConnected) return;
    isConnectedViaCloud = true;

    try {
      final wsUrl = Uri.parse(cloudRelayUrl);
      logDiagnostic('Connecting to Cloud Fallback: $wsUrl');
      _channel = WebSocketChannel.connect(wsUrl);

      _wsSubscription?.cancel();
      _wsSubscription = _channel!.stream.listen(
        _onMessageReceived,
        onDone: _onDisconnected,
        onError: (err) {
          logDiagnostic('Cloud Socket Error: $err');
          _onDisconnected();
        },
        cancelOnError: true,
      );

      _lastPongTime = DateTime.now().millisecondsSinceEpoch;

      // Send cloud session registration
      _channel!.sink.add(RelayMessage.registerCloudSession(
        pairingKey: pairingKey,
        role: 'client',
      ).toJsonString());

      _startPingHeartbeat();
    } catch (e) {
      logDiagnostic('Cloud Connect Exception: $e');
      _onDisconnected();
    }
  }

  void disconnect() {
    logDiagnostic('Disconnect requested explicitly');
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
    logDiagnostic('Socket Disconnected (onDone/onError fired)');
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
        final elapsedSincePong = now - _lastPongTime;
        if (elapsedSincePong > 30000) {
          logDiagnostic('Ping watchdog timeout (>30s no pong). Disconnecting to trigger instant reconnect.');
          disconnect();
          connect();
          return;
        }
        try {
          _channel!.sink.add(RelayMessage.ping().toJsonString());
        } catch (e) {
          logDiagnostic('Ping Send Error: $e');
          _onDisconnected();
          connect();
        }
      }
    });
  }

  void onAppResumed() {
    logDiagnostic('App Resumed from screen lock/background');
    _lastPongTime = DateTime.now().millisecondsSinceEpoch;
    if (!_isConnected || _channel == null) {
      logDiagnostic('Instant wake reconnect starting...');
      discoverHostIp().then((_) {
        connect();
      });
    } else {
      try {
        _channel!.sink.add(RelayMessage.ping().toJsonString());
      } catch (_) {
        _onDisconnected();
        connect();
      }
    }
  }

  void onAppPaused() {
    logDiagnostic('App entered background/screen locked');
    _lastPongTime = DateTime.now().millisecondsSinceEpoch;
  }

  void _startReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isConnected) {
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
      var msg = RelayMessage.fromJsonString(raw);

      // Handle E2EE Decryption for remote cloud relay frames
      if (msg.type == 'ENCRYPTED_FRAME') {
        final cipher = E2eeCipher.fromKey(pairingKey);
        final dec = cipher.decrypt(msg.data['ciphertext']?.toString() ?? '');
        if (dec != null) {
          msg = RelayMessage.fromJsonString(dec);
        } else {
          logDiagnostic('⚠️ E2EE decryption failed (pairing key mismatch)');
          return;
        }
      }

      if (!_isConnected) {
        _isConnected = true;
        logDiagnostic('Socket Connected Successfully!');
        _connectionController.add(true);
        syncAll();
      }

      if (msg.type != 'PONG') {
        logDiagnostic('RX [${msg.type}]: ${msg.toJsonString()}');
      }

      switch (msg.type) {
        case 'PONG':
          _lastPongTime = DateTime.now().millisecondsSinceEpoch;
          break;

        case 'WEBRTC_OFFER':
        case 'WEBRTC_ANSWER':
        case 'WEBRTC_ICE_CANDIDATE':
          voiceTunnel.handleSignalingMessage(msg);
          break;

        case 'SMS_SENT_STATUS':
          final success = msg.data['success'] as bool? ?? false;
          final recipient = msg.data['recipient'] as String? ?? '';
          logDiagnostic('SMS Sent Status: ${success ? "Delivered" : "Failed"} to $recipient');
          break;

        case 'SYNC_STATE':
          try {
            final status = msg.data['status'] as String? ?? '';
            final isInCall = msg.data['is_in_call'] as bool? ?? false;
            final isConnected = msg.data['is_connected'] as bool? ?? false;
            final number = msg.data['number'] as String? ?? '';

            if (isInCall) {
              if (status == 'Incoming Call') {
                currentActiveCall = ActiveCallInfo(
                  number: number.isNotEmpty ? number : 'Cellular Call',
                  callerName: '',
                  startTime: 0,
                  isIncoming: true,
                  state: PhoneCallState.ringing,
                );
                _activeCallController.add(currentActiveCall);
                try {
                  await CallKitService.instance.showIncomingCall(
                    callId: CallKitService.generateUuid(),
                    callerName: number,
                    handle: number,
                  );
                } catch (_) {}
              } else if (isConnected) {
                final dur = msg.data['duration_seconds'] as int? ?? 0;
                final startMs = DateTime.now().millisecondsSinceEpoch - (dur * 1000);
                final contact = await DatabaseHelper.instance.findContactByNumber(number);
                currentActiveCall = ActiveCallInfo(
                  number: number.isNotEmpty ? number : (currentActiveCall?.number ?? 'Cellular Call'),
                  callerName: contact?.displayName ?? (currentActiveCall?.callerName ?? ''),
                  label: contact?.getLabelForNumber(number) ?? currentActiveCall?.label,
                  startTime: startMs,
                  isIncoming: currentActiveCall?.isIncoming ?? false,
                  state: PhoneCallState.connected,
                );
                _activeCallController.add(currentActiveCall);
              }
            } else {
              if (currentActiveCall != null) {
                currentActiveCall = null;
                _activeCallController.add(null);
                voiceTunnel.closeVoiceTunnel();
                await CallKitService.instance.endAllCalls();
              }
            }
          } catch (e) {
            debugPrint('[RELAY] Exception processing SYNC_STATE: $e');
          }
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
            durationSeconds: 0,
            isIncoming: currentActiveCall?.isIncoming ?? false,
            state: isAnswered && startTimeMs > 0 ? PhoneCallState.connected : PhoneCallState.dialing,
          );
          _activeCallController.add(currentActiveCall);

          if (isAnswered) {
            await CallKitService.instance.setCallConnected();
            logDiagnostic('🎙️ Active cellular call established -> Starting lossless WebRTC Voice Tunnel');
            voiceTunnel.startVoiceTunnel(
              isCaller: true,
              sendSignaling: (sMsg) => _sendRawMessage(sMsg),
              logCallback: (txt) => logDiagnostic('[WEBRTC] $txt'),
            );
          }
          break;

        case 'CALL_TICK':
          final dur = msg.data['duration'] as int? ?? 0;
          if (currentActiveCall != null) {
            currentActiveCall = ActiveCallInfo(
              number: currentActiveCall!.number,
              callerName: currentActiveCall!.callerName,
              label: currentActiveCall!.label,
              startTime: currentActiveCall!.startTime,
              durationSeconds: dur,
              isIncoming: currentActiveCall!.isIncoming,
              state: PhoneCallState.connected,
            );
            _activeCallController.add(currentActiveCall);
          }
          break;

        case 'CALL_DISCONNECTED':
          voiceTunnel.closeVoiceTunnel();
          final number = msg.data['number'] as String? ?? (currentActiveCall?.number ?? 'Unknown');
          final duration = msg.data['duration'] as int? ?? 0;
          final msgIsMissed = msg.data['isMissed'] as bool? ?? false;

          // End native Apple CallKit
          await CallKitService.instance.endAllCalls();

          // Save to local SQLite call log
          final contact = await DatabaseHelper.instance.findContactByNumber(number);
          final bool wasRinging = currentActiveCall?.state == PhoneCallState.ringing;
          final bool wasIncoming = currentActiveCall?.isIncoming ?? false;
          final bool isMissed = msgIsMissed || (wasRinging && wasIncoming) || (duration == 0 && wasIncoming);

          final log = CallLogModel(
            id: DateTime.now().millisecondsSinceEpoch,
            remoteNumber: number,
            callerName: contact?.displayName ?? (currentActiveCall?.callerName ?? ''),
            numberLabel: contact?.getLabelForNumber(number) ?? currentActiveCall?.label,
            callType: isMissed
                ? CallType.missed
                : (wasIncoming ? CallType.incoming : CallType.outgoing),
            serviceType: ServiceType.zongGsm,
            durationSeconds: duration,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
          await DatabaseHelper.instance.saveCallLog(log);
          _syncController.add(null);

          if (isMissed) {
            _missedCallController.add(log);
          }

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

    try {
      await CallKitService.instance.startCall(
        callId: CallKitService.generateUuid(),
        callerName: contact?.displayName ?? clean,
        handle: clean,
      );
    } catch (_) {}

    if (_isConnected && _channel != null) {
      try {
        _sendRawMessage(RelayMessage.actionDial(clean));
        return true;
      } catch (_) {}
    }

    // REST Fallback
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/call?number=${Uri.encodeComponent(clean)}');
      final res = await http.post(uri).timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> answerCall() async {
    if (_isConnected && _channel != null) {
      try {
        _sendRawMessage(RelayMessage.actionAnswer());
        voiceTunnel.startVoiceTunnel(
          isCaller: false,
          sendSignaling: (sMsg) => _sendRawMessage(sMsg),
          logCallback: (txt) => logDiagnostic('[WEBRTC] $txt'),
        );
        return true;
      } catch (_) {}
    }

    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/answer');
      final res = await http.post(uri).timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hangupCall() async {
    voiceTunnel.closeVoiceTunnel();
    await CallKitService.instance.endAllCalls();
    currentActiveCall = null;
    _activeCallController.add(null);

    if (_isConnected && _channel != null) {
      try {
        _sendRawMessage(RelayMessage.actionHangup());
        return true;
      } catch (_) {}
    }

    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/hangup');
      final res = await http.post(uri).timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendDtmf(String digit) async {
    if (_isConnected && _channel != null) {
      try {
        _sendRawMessage(RelayMessage.actionDtmf(digit));
        return true;
      } catch (_) {}
    }

    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/dtmf?digit=${Uri.encodeComponent(digit)}');
      final res = await http.post(uri).timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Dispatches an outgoing SMS message through Vivo S1's cellular SIM
  Future<bool> sendSms(String recipient, String message) async {
    final cleanRecipient = recipient.trim();
    final cleanMsg = message.trim();
    if (cleanRecipient.isEmpty || cleanMsg.isEmpty) return false;

    logDiagnostic('📤 Outgoing SMS via Vivo SIM to $cleanRecipient: $cleanMsg');

    // Save locally as sent SMS
    final localMsg = SmsMessageModel(
      id: DateTime.now().millisecondsSinceEpoch,
      sender: 'To: $cleanRecipient',
      body: cleanMsg,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isRead: true,
    );
    await DatabaseHelper.instance.saveMessage(localMsg);
    _smsController.add(localMsg);

    // WebSocket Priority
    if (_isConnected && _channel != null) {
      try {
        _sendRawMessage(RelayMessage.actionSendSms(recipient: cleanRecipient, message: cleanMsg));
        return true;
      } catch (_) {}
    }

    // REST Fallback
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/sms/send');
      final res = await http.post(
        uri,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'recipient': cleanRecipient, 'message': cleanMsg}),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (e) {
      logDiagnostic('REST sendSms error: $e');
      return false;
    }
  }

  /// Mutes or unmutes local microphone during WebRTC voice session
  void toggleMute(bool muted) {
    voiceTunnel.toggleMute(muted);
  }

  /// Toggles iPhone speakerphone or earpiece output
  Future<void> setSpeakerphone(bool enabled) async {
    await voiceTunnel.setSpeakerphone(enabled);
  }

  /// Returns the HTTP streaming URL for a contact avatar from Vivo S1
  String getContactAvatarUrl(String contactId) {
    return 'http://$hostIp:$hostPort/api/contacts/avatar?id=${Uri.encodeComponent(contactId)}';
  }

  Future<void> syncAll() async {
    await fetchContacts();
    await fetchHistory();
  }

  Future<void> fetchContacts() async {
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/contacts');
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
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
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
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

  /// Fetches the list of Vivo S1 native call recordings matching a phone number
  Future<List<CallRecordingModel>> fetchRecordings(String rawNumber) async {
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/recordings?number=${Uri.encodeComponent(rawNumber)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        return list.map((item) => CallRecordingModel.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      debugPrint('[RELAY_CLIENT] Error fetching recordings: $e');
    }
    return [];
  }

  /// URL for streaming or downloading a specific recording file from the Vivo S1 host
  String getRecordingAudioUrl(String filename) {
    return 'http://$hostIp:$hostPort/api/recordings/audio?file=${Uri.encodeComponent(filename)}';
  }
}

