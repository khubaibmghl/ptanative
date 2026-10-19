import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import 'callkit_service.dart';

enum PhoneCallState { dialing, ringing, connected, disconnected }

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

  ActiveCallInfo copyWith({
    String? number,
    String? callerName,
    String? label,
    int? startTime,
    int? durationSeconds,
    bool? isIncoming,
    PhoneCallState? state,
  }) {
    return ActiveCallInfo(
      number: number ?? this.number,
      callerName: callerName ?? this.callerName,
      label: label ?? this.label,
      startTime: startTime ?? this.startTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isIncoming: isIncoming ?? this.isIncoming,
      state: state ?? this.state,
    );
  }
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
  bool isAnsweringOrActive = false;
  int _lastHangupTimestamp = 0;
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

    // Connect immediately to last known host IP (fast launch, 0ms blocking)
    connect();
    _startReconnectLoop();

    // Run discovery in the background so cold startup does not hang UI on splash screen
    discoverHostIp().then((discoveredIp) async {
      if (discoveredIp != null && discoveredIp.isNotEmpty && discoveredIp != hostIp) {
        logDiagnostic('⚡ Background discovery resolved host: $discoveredIp');
        hostIp = discoveredIp;
        await prefs.setString('host_ip', hostIp);
        disconnect();
        connect();
      }
    });
  }

  int lastPingLatencyMs = 0;
  int _lastPingSentTimestamp = 0;

  /// Fast parallel HTTP sweep across a /24 subnet (e.g. 192.168.1.1 .. 254)
  Future<String?> sweepSubnet(String prefix) async {
    if (_isConnected) return null;
    logDiagnostic('⚡ Starting parallel subnet sweep on $prefix.0/24...');
    final client = http.Client();
    try {
      final futures = <Future<String?>>[];
      for (int i = 1; i <= 254; i++) {
        if (_isConnected) break;
        final ip = '$prefix.$i';
        futures.add(() async {
          if (_isConnected) return null;
          try {
            final uri = Uri.parse('http://$ip:$hostPort/api/status');
            final res = await client.get(uri).timeout(const Duration(milliseconds: 350));
            if (res.statusCode == 200 && res.body.contains('pta_host')) {
              return ip;
            }
          } catch (_) {}
          return null;
        }());
      }

      final results = await Future.wait(futures);
      final found = results.firstWhere((ip) => ip != null, orElse: () => null);
      if (found != null) {
        logDiagnostic('⚡ Subnet sweep matched host: $found');
        return found;
      }
    } finally {
      client.close();
    }
    return null;
  }

  /// Instant check of the local Hotspot / Wi-Fi router gateway
  Future<String?> probeDirectGateway() async {
    if (_isConnected) return hostIp;
    try {
      // 1. Auto-detect if connected to Vivo S1 Hotspot (192.168.43.x)
      try {
        final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (addr.address.startsWith('192.168.43.')) {
              logDiagnostic('⚡ Connected to Vivo S1 Hotspot subnet (192.168.43.x). Auto-locking 192.168.43.1!');
              return '192.168.43.1';
            }
          }
        }
      } catch (_) {}

      // 2. Direct gateway probes
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
        if (_isConnected) return hostIp;
        try {
          final uri = Uri.parse('http://$ip:$hostPort/api/status');
          final res = await http.get(uri).timeout(const Duration(milliseconds: 400));
          if (res.statusCode == 200) {
            logDiagnostic('⚡ Gateway direct-probe found host: $ip');
            return ip;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  /// High-Speed Multi-Layer Auto-Discovery (Hotspot Auto-Lock -> UDP Broadcast -> Subnet Sweep)
  Future<String?> discoverHostIp() async {
    if (_isConnected) return hostIp;

    // 1. Check Hotspot / Gateway direct probe (0 ms for Hotspot)
    final directIp = await probeDirectGateway();
    if (directIp != null && directIp.isNotEmpty) {
      hostIp = directIp;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('host_ip', hostIp);
      return directIp;
    }

    if (_isConnected) return hostIp;

    // 2. High-speed parallel UDP Broadcast Probe (10-20ms)
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final msg = 'PTA_DISCOVER_REQUEST'.codeUnits;

      socket.send(msg, InternetAddress('255.255.255.255'), 8081);

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

      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            socket.send(msg, InternetAddress(subnetBroadcast), 8081);
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

      final discoveredIp = await completer.future.timeout(const Duration(milliseconds: 600), onTimeout: () => null);
      socket.close();

      if (discoveredIp != null && discoveredIp.isNotEmpty) {
        logDiagnostic('⚡ UDP Broadcast discovered host at $discoveredIp');
        hostIp = discoveredIp;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('host_ip', hostIp);
        return discoveredIp;
      }
    } catch (_) {}

    // 3. Fallback: High-speed parallel subnet sweep (bypasses router AP isolation / UDP block)
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4 && parts[0] != '127') {
            final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            final swept = await sweepSubnet(prefix);
            if (swept != null) {
              hostIp = swept;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('host_ip', hostIp);
              return swept;
            }
          }
        }
      }
    } catch (_) {}

    return null;
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
    logDiagnostic('⚡ Starting superfast background reconnection loop...');
    _startReconnectLoop();
  }

  bool isAppPaused = false;

  /// Dispatched from native Swift UDP receiver when screen is locked or on dry Wi-Fi link
  void handleNativeUdpFrame(String raw) {
    logDiagnostic('UDP Frame received via Native Swift Bridge: ${raw.length > 80 ? "${raw.substring(0, 80)}..." : raw}');
    _onMessageReceived(raw);
  }

  void _startPingHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_isConnected && _channel != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsedSincePong = now - _lastPongTime;
        // In background/screen locked, allow up to 300s (5 mins) before watchdog teardown to prevent false disconnects
        final maxWatchdogTimeout = isAppPaused ? 300000 : 60000;
        if (elapsedSincePong > maxWatchdogTimeout) {
          logDiagnostic('Ping watchdog timeout (>${maxWatchdogTimeout ~/ 1000}s no response). Disconnecting to trigger instant reconnect.');
          disconnect();
          connect();
          return;
        }
        // Send PING if no packets were received from the host:
        // In foreground: every 15s. In background: every 75s (reduces CPU wakeups by 80% to save battery).
        final pingThreshold = isAppPaused ? 75000 : 15000;
        if (now - _lastPongTime >= pingThreshold) {
          try {
            _lastPingSentTimestamp = DateTime.now().millisecondsSinceEpoch;
            _channel!.sink.add(RelayMessage.ping().toJsonString());
            _pingNativeKeepAlive();
          } catch (e) {
            logDiagnostic('Ping Send Error: $e');
            _onDisconnected();
            connect();
          }
        }
      }
    });
  }

  void _pingNativeKeepAlive() {
    try {
      const MethodChannel('com.pta.phone/native_intents').invokeMethod('pingKeepAlive', {
        'hostIp': hostIp,
        'hostPort': hostPort,
      });
    } catch (_) {}
  }

  void _setNativeCallActive(bool active) {
    try {
      const MethodChannel('com.pta.phone/native_intents').invokeMethod('setCallActive', active);
    } catch (_) {}
  }

  void onAppResumed() {
    isAppPaused = false;
    logDiagnostic('App Resumed from screen lock/background');
    _lastPongTime = DateTime.now().millisecondsSinceEpoch;
    _pingNativeKeepAlive();
    if (!_isConnected || _channel == null) {
      logDiagnostic('Instant wake reconnecting directly to host $hostIp...');
      connect();
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (!_isConnected) {
          discoverHostIp().then((discovered) {
            if (!_isConnected && discovered != null && discovered.isNotEmpty) {
              connect();
            }
          });
        }
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
    isAppPaused = true;
    logDiagnostic('App entered background/screen locked (2-Hour Keep-Alive Active)');
    _lastPongTime = DateTime.now().millisecondsSinceEpoch;
    _pingNativeKeepAlive();
  }

  void _startReconnectLoop() {
    _reconnectTimer?.cancel();
    // In background, relax reconnect polling to 15s instead of 3s to conserve CPU & Wi-Fi power
    final pollInterval = isAppPaused ? const Duration(seconds: 15) : const Duration(seconds: 3);
    _reconnectTimer = Timer.periodic(pollInterval, (timer) async {
      if (_isConnected) {
        logDiagnostic('✅ Devices connected: stopping background search.');
        timer.cancel();
        _reconnectTimer = null;
        return;
      }
      if (hostIp.isNotEmpty) {
        connect();
        if (_isConnected) {
          timer.cancel();
          _reconnectTimer = null;
          return;
        }
      }
      // Only perform heavy network subnet sweeps when app is in foreground
      if (!isAppPaused) {
        logDiagnostic('⚡ Background search running for Vivo S1...');
        final discoveredIp = await discoverHostIp();
        if (discoveredIp != null && discoveredIp.isNotEmpty && discoveredIp != hostIp) {
          hostIp = discoveredIp;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('host_ip', hostIp);
        }
        if (!_isConnected) {
          connect();
        }
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
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        logDiagnostic('🛑 Background search process stopped (connection established).');
        _connectionController.add(true);
        syncAll();
      }

      // Any valid message received from host confirms link liveness
      _lastPongTime = DateTime.now().millisecondsSinceEpoch;
      _pingNativeKeepAlive();

      if (msg.type != 'PONG') {
        logDiagnostic('RX [${msg.type}]: ${msg.toJsonString()}');
      }

      switch (msg.type) {
        case 'PONG':
          if (_lastPingSentTimestamp > 0) {
            lastPingLatencyMs = _lastPongTime - _lastPingSentTimestamp;
          }
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
                final isSameNumber = number.isEmpty ||
                    (currentActiveCall != null &&
                        PhoneNumberNormalizer.normalize(currentActiveCall!.number) == PhoneNumberNormalizer.normalize(number));
                final resolvedNumber = number.isNotEmpty ? number : (currentActiveCall?.number ?? 'Cellular Call');
                final resolvedName = contact?.displayName ?? (isSameNumber ? (currentActiveCall?.callerName ?? '') : '');
                final resolvedLabel = contact?.getLabelForNumber(resolvedNumber) ?? (isSameNumber ? currentActiveCall?.label : null);

                currentActiveCall = ActiveCallInfo(
                  number: resolvedNumber,
                  callerName: resolvedName,
                  label: resolvedLabel,
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
          final callId = msg.data['call_id'] as String? ?? CallKitService.deterministicUuidForNumber(number);

          // Resolve contact locally from SQLite cache on iPhone
          final contact = await DatabaseHelper.instance.findContactByNumber(number);
          final resolvedName = contact?.displayName ?? (name.isNotEmpty ? name : number);
          final resolvedLabel = contact?.getLabelForNumber(number) ?? label;

          // Show native Apple CallKit Incoming Screen (Slide to Answer)
          try {
            await CallKitService.instance.showIncomingCall(
              callId: callId,
              callerName: resolvedName,
              handle: number,
              label: resolvedLabel,
            );
          } catch (e) {
            debugPrint('[RELAY] Exception showing CallKit incoming call: $e');
          }

          currentActiveCall = ActiveCallInfo(
            number: number,
            callerName: resolvedName,
            label: resolvedLabel,
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
            number: dialNum.isNotEmpty ? dialNum : 'Cellular Call',
            callerName: dialContact?.displayName ?? '',
            label: dialContact?.getLabelForNumber(dialNum),
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
              : DateTime.now().millisecondsSinceEpoch;

          final contact = await DatabaseHelper.instance.findContactByNumber(number);
          final bool wasIncomingCall = currentActiveCall?.isIncoming ?? false;

          // Only inherit callerName from currentActiveCall if it belongs to the SAME call/number!
          final isSameNumber = number.isEmpty ||
              (currentActiveCall != null &&
                  PhoneNumberNormalizer.normalize(currentActiveCall!.number) == PhoneNumberNormalizer.normalize(number));

          final resolvedNumber = number.isNotEmpty ? number : (currentActiveCall?.number ?? 'Cellular Call');
          final resolvedName = contact?.displayName ?? (isSameNumber ? (currentActiveCall?.callerName ?? '') : '');
          final resolvedLabel = contact?.getLabelForNumber(resolvedNumber) ?? (isSameNumber ? currentActiveCall?.label : null);

          currentActiveCall = ActiveCallInfo(
            number: resolvedNumber,
            callerName: resolvedName,
            label: resolvedLabel,
            startTime: startTimeMs,
            durationSeconds: 0,
            isIncoming: wasIncomingCall,
            state: PhoneCallState.connected,
          );
          _activeCallController.add(currentActiveCall);

          if (isAnswered) {
            isAnsweringOrActive = true;
            _setNativeCallActive(true);
            // Inform Apple CallKit CXProvider that the call has connected (CXCallConnected)
            await CallKitService.instance.setCallConnected();
            logDiagnostic('🎙️ Active cellular call established on Vivo S1');
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
          isAnsweringOrActive = false;
          _setNativeCallActive(false);
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
          final bool wasConnected = currentActiveCall?.state == PhoneCallState.connected;
          final bool isMissed = msgIsMissed || (wasRinging && wasIncoming && !wasConnected && duration == 0);

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

          if (currentActiveCall != null) {
            currentActiveCall = ActiveCallInfo(
              number: number,
              callerName: contact?.displayName ?? currentActiveCall!.callerName,
              label: contact?.getLabelForNumber(number) ?? currentActiveCall?.label,
              startTime: currentActiveCall!.startTime,
              durationSeconds: duration,
              isIncoming: wasIncoming,
              state: PhoneCallState.disconnected,
            );
            _activeCallController.add(currentActiveCall);

            // Keep authentic iOS "call ended" on screen for 1.2s before dismissing
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (currentActiveCall?.state == PhoneCallState.disconnected) {
                currentActiveCall = null;
                _activeCallController.add(null);
              }
            });
          } else {
            _activeCallController.add(null);
          }
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

  String? _lastDialedNumber;
  int _lastDialedTimestamp = 0;

  Future<bool> dialNumber(String number) async {
    final clean = number.trim();
    if (clean.isEmpty) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastDialedNumber == clean && (now - _lastDialedTimestamp) < 1500) {
      logDiagnostic('⚡ Debounced duplicate dial intent for $clean');
      return true;
    }
    _lastDialedNumber = clean;
    _lastDialedTimestamp = now;

    final contact = await DatabaseHelper.instance.findContactByNumber(clean);
    currentActiveCall = ActiveCallInfo(
      number: clean,
      callerName: contact?.displayName ?? '',
      label: contact?.getLabelForNumber(clean),
      startTime: 0,
      durationSeconds: 0,
      isIncoming: false,
      state: PhoneCallState.dialing,
    );
    _activeCallController.add(currentActiveCall);
    _setNativeCallActive(true);

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
    isAnsweringOrActive = true;
    _setNativeCallActive(true);
    await CallKitService.instance.setCallConnected();

    final now = DateTime.now().millisecondsSinceEpoch;
    if (currentActiveCall != null) {
      currentActiveCall = currentActiveCall!.copyWith(
        state: PhoneCallState.connected,
        startTime: currentActiveCall!.startTime > 0 ? currentActiveCall!.startTime : now,
      );
      _activeCallController.add(currentActiveCall);
    }

    if (_isConnected && _channel != null) {
      try {
        _sendRawMessage(RelayMessage.actionAnswer());
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
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - _lastHangupTimestamp) < 1200 && currentActiveCall?.state == PhoneCallState.disconnected) {
      logDiagnostic('⚡ Debounced redundant hangup call intent');
      return true;
    }
    _lastHangupTimestamp = now;
    isAnsweringOrActive = false;
    _setNativeCallActive(false);

    voiceTunnel.closeVoiceTunnel();
    await CallKitService.instance.endAllCalls();

    if (currentActiveCall != null && currentActiveCall!.state != PhoneCallState.disconnected) {
      currentActiveCall = currentActiveCall!.copyWith(
        state: PhoneCallState.disconnected,
      );
      _activeCallController.add(currentActiveCall);

      Future.delayed(const Duration(milliseconds: 1000), () {
        if (currentActiveCall?.state == PhoneCallState.disconnected) {
          currentActiveCall = null;
          _activeCallController.add(null);
        }
      });
    }

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

  int _lastRecordingsSyncTimestamp = 0;

  Future<void> syncAll() async {
    await fetchContacts();
    await fetchHistory();
    await fetchMessages();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRecordingsSyncTimestamp > 180000) {
      _lastRecordingsSyncTimestamp = now;
      await syncLatestRecordings(limit: 20);
    }
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

  Future<void> fetchMessages({int limit = 500}) async {
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/messages?limit=$limit');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        final messages = list.map((item) => SmsMessageModel.fromJson(Map<String, dynamic>.from(item))).toList();
        await DatabaseHelper.instance.saveMessages(messages);
        _syncController.add(null);
      }
    } catch (_) {}
  }

  bool _isSyncingRecordings = false;

  /// Permanently fetches and caches the latest recordings from the Vivo S1 host
  Future<void> syncLatestRecordings({int limit = 20}) async {
    if (_isSyncingRecordings || !_isConnected) return;
    _isSyncingRecordings = true;
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/recordings/latest?limit=$limit');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        final recordings = list.map((item) => CallRecordingModel.fromJson(Map<String, dynamic>.from(item))).toList();
        logDiagnostic('📥 Synced ${recordings.length} latest recordings from Vivo S1 host');
        await DatabaseHelper.instance.saveRecordings(recordings);

        // Power saving: Only pre-download audio files when app is active in foreground
        if (!isAppPaused) {
          final topRecent = recordings.take(3).toList();
          for (final rec in topRecent) {
            final local = await getLocalRecordingPath(rec.filename);
            if (local == null && _isConnected && !isAppPaused) {
              await downloadRecordingAudio(rec.filename);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[RELAY_CLIENT] Error syncing latest recordings: $e');
    } finally {
      _isSyncingRecordings = false;
    }
  }

  /// Fetches the list of recordings: checks SQLite offline cache first, then syncs with host
  Future<List<CallRecordingModel>> fetchRecordings(
    String rawNumber, {
    String? contactName,
    int? callTimestamp,
    int? durationSeconds,
  }) async {
    // 1. Instant check from local SQLite cache
    final localCached = await DatabaseHelper.instance.getLocalRecordings(
      number: rawNumber,
      name: contactName,
      callTimestamp: callTimestamp,
    );

    // 2. If online, fetch from host and update cache
    if (_isConnected) {
      try {
        final queryParams = <String, String>{
          'number': rawNumber,
        };
        if (contactName != null && contactName.isNotEmpty) {
          queryParams['name'] = contactName;
        }
        if (callTimestamp != null && callTimestamp > 0) {
          queryParams['timestamp'] = callTimestamp.toString();
        }
        if (durationSeconds != null && durationSeconds > 0) {
          queryParams['duration'] = durationSeconds.toString();
        }

        final uri = Uri.http('$hostIp:$hostPort', 'api/recordings', queryParams);
        final res = await http.get(uri).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final List<dynamic> list = jsonDecode(res.body);
          final recordings = list.map((item) => CallRecordingModel.fromJson(Map<String, dynamic>.from(item))).toList();
          if (recordings.isNotEmpty) {
            await DatabaseHelper.instance.saveRecordings(recordings);

            // Auto-download all appearing recordings so they are permanently stored on iPhone
            for (final rec in recordings) {
              getLocalRecordingPath(rec.filename).then((local) {
                if (local == null) {
                  downloadRecordingAudio(rec.filename);
                }
              });
            }

            return recordings;
          }
        }
      } catch (e) {
        debugPrint('[RELAY_CLIENT] Error fetching recordings: $e');
      }
    }

    if (localCached.isNotEmpty) {
      return localCached;
    }

    // Strict isolation: Return empty list if no recording matches this specific number.
    // Never fallback to returning recordings belonging to other contacts.
    return [];
  }

  /// URL for streaming or downloading a specific recording file from the Vivo S1 host
  String getRecordingAudioUrl(String filename) {
    return 'http://$hostIp:$hostPort/api/recordings/audio?file=${Uri.encodeComponent(filename)}';
  }

  /// Checks if a call recording audio file already exists locally in iPhone storage
  Future<String?> getLocalRecordingPath(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/recordings/$filename');
      if (await localFile.exists() && await localFile.length() > 0) {
        return localFile.path;
      }
    } catch (_) {}
    return null;
  }

  /// Downloads Vivo S1 call recording audio over the local network and caches it
  /// as a permanent native audio file on the iPhone file system.
  Future<String?> downloadRecordingAudio(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${dir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      final localFile = File('${recordingsDir.path}/$filename');
      if (await localFile.exists() && await localFile.length() > 0) {
        await DatabaseHelper.instance.updateRecordingLocalPath(filename, localFile.path);
        return localFile.path;
      }

      final url = getRecordingAudioUrl(filename);
      logDiagnostic('📥 Downloading recording over network: $filename from $url');
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await localFile.writeAsBytes(res.bodyBytes, flush: true);
        logDiagnostic('✅ Saved recording as native iPhone file: ${localFile.path} (${res.bodyBytes.length} bytes)');
        await DatabaseHelper.instance.updateRecordingLocalPath(filename, localFile.path);
        return localFile.path;
      } else {
        logDiagnostic('❌ Failed to download recording ($filename): status ${res.statusCode}');
      }
    } catch (e) {
      logDiagnostic('❌ Error downloading recording ($filename): $e');
    }
    return null;
  }

  /// Directly tests roundtrip network latency to the Vivo S1 host in milliseconds
  Future<int> measurePingLatency() async {
    final start = DateTime.now().millisecondsSinceEpoch;
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/status');
      final res = await http.get(uri).timeout(const Duration(milliseconds: 1500));
      if (res.statusCode == 200) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - start;
        lastPingLatencyMs = elapsed;
        return elapsed;
      }
    } catch (_) {}
    return -1;
  }

  /// Returns the current local IPv4 address of this iPhone on Wi-Fi/Hotspot
  Future<String?> getCurrentLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && (addr.address.startsWith('192.168.') || addr.address.startsWith('10.') || addr.address.startsWith('172.'))) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

