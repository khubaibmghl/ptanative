import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import 'callkit_service.dart';

class ActiveCallInfo {
  final String number;
  final String callerName;
  final String? label;
  final int startTime; // Epoch millis
  final bool isIncoming;

  ActiveCallInfo({
    required this.number,
    required this.callerName,
    this.label,
    required this.startTime,
    required this.isIncoming,
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
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  // Stream Controllers
  final _connectionController = StreamController<bool>.broadcast();
  final _statusController = StreamController<DeviceStatusModel>.broadcast();
  final _activeCallController = StreamController<ActiveCallInfo?>.broadcast();
  final _smsController = StreamController<SmsMessageModel>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<DeviceStatusModel> get statusStream => _statusController.stream;
  Stream<ActiveCallInfo?> get activeCallStream => _activeCallController.stream;
  Stream<SmsMessageModel> get smsStream => _smsController.stream;

  ActiveCallInfo? currentActiveCall;
  DeviceStatusModel? lastStatus;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    hostIp = prefs.getString('host_ip') ?? '192.168.23.68';
    hostPort = prefs.getInt('host_port') ?? 8080;

    connect();
    _startReconnectLoop();
  }

  Future<void> updateHostConfig(String ip, int port) async {
    hostIp = ip.trim();
    hostPort = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host_ip', hostIp);
    await prefs.setInt('host_port', hostPort);

    disconnect();
    connect();
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
        onError: (err) => _onDisconnected(),
        cancelOnError: true,
      );

      _isConnected = true;
      _connectionController.add(true);

      // Perform initial delta sync upon connection
      syncAll();
    } catch (e) {
      _onDisconnected();
    }
  }

  void disconnect() {
    _isConnected = false;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _connectionController.add(false);
  }

  void _onDisconnected() {
    _isConnected = false;
    _connectionController.add(false);
  }

  void _startReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!_isConnected) {
        connect();
      }
    });
  }

  void _onMessageReceived(dynamic message) async {
    try {
      final raw = message.toString();
      final msg = RelayMessage.fromJsonString(raw);

      switch (msg.type) {
        case 'INCOMING_RING':
          final number = msg.data['number'] as String? ?? 'Cellular Call';
          final name = msg.data['name'] as String? ?? '';
          final label = msg.data['label'] as String?;

          // Show native Apple CallKit Incoming Screen (Slide to Answer)
          await CallKitService.instance.showIncomingCall(
            callId: 'ring_${DateTime.now().millisecondsSinceEpoch}',
            callerName: name,
            handle: number,
            label: label,
          );

          currentActiveCall = ActiveCallInfo(
            number: number,
            callerName: name,
            label: label,
            startTime: DateTime.now().millisecondsSinceEpoch,
            isIncoming: true,
          );
          _activeCallController.add(currentActiveCall);
          break;

        case 'CALL_ACTIVE':
          final number = msg.data['number'] as String? ?? '';
          final startTime = msg.data['startTime'] as int? ?? DateTime.now().millisecondsSinceEpoch;

          final contact = await DatabaseHelper.instance.findContactByNumber(number);
          currentActiveCall = ActiveCallInfo(
            number: number,
            callerName: contact?.displayName ?? '',
            label: contact?.getLabelForNumber(number),
            startTime: startTime,
            isIncoming: currentActiveCall?.isIncoming ?? false,
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

          currentActiveCall = null;
          _activeCallController.add(null);
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

  // --- REST API Commands ---

  Future<bool> dialNumber(String number) async {
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/call');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'number': number}),
      );

      if (res.statusCode == 200) {
        final contact = await DatabaseHelper.instance.findContactByNumber(number);
        currentActiveCall = ActiveCallInfo(
          number: number,
          callerName: contact?.displayName ?? '',
          label: contact?.getLabelForNumber(number),
          startTime: DateTime.now().millisecondsSinceEpoch,
          isIncoming: false,
        );
        _activeCallController.add(currentActiveCall);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> answerCall() async {
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/answer');
      final res = await http.post(uri);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hangupCall() async {
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/hangup');
      final res = await http.post(uri);
      await CallKitService.instance.endAllCalls();
      currentActiveCall = null;
      _activeCallController.add(null);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendDtmf(String digit) async {
    try {
      final uri = Uri.parse('http://$hostIp:$hostPort/api/dtmf');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'digit': digit}),
      );
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
      }
    } catch (_) {}
  }
}
