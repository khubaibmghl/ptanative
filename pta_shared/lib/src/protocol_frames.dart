import 'dart:convert';

class SimCardInfo {
  final int slotIndex; // 0 for SIM 1, 1 for SIM 2
  final int subId;
  final String displayName;
  final String carrierName;

  SimCardInfo({
    required this.slotIndex,
    required this.subId,
    required this.displayName,
    required this.carrierName,
  });

  factory SimCardInfo.fromJson(Map<String, dynamic> json) {
    return SimCardInfo(
      slotIndex: json['slotIndex'] as int? ?? 0,
      subId: json['subId'] as int? ?? -1,
      displayName: json['displayName'] as String? ?? 'SIM',
      carrierName: json['carrierName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slotIndex': slotIndex,
      'subId': subId,
      'displayName': displayName,
      'carrierName': carrierName,
    };
  }
}

class DeviceStatusModel {
  final int batteryLevel; // 0 - 100
  final bool isCharging;
  final int signalBars; // 0 - 4
  final String networkType; // e.g. 'Zong 4G • VoLTE'
  final bool isAdbConnected;
  final bool isAirPodsConnected;
  final bool isMobileDataEnabled;
  final int activeDataSlot; // 0 for SIM 1, 1 for SIM 2
  final int activeDataSubId;
  final List<SimCardInfo> sims;

  DeviceStatusModel({
    required this.batteryLevel,
    required this.isCharging,
    required this.signalBars,
    required this.networkType,
    required this.isAdbConnected,
    required this.isAirPodsConnected,
    this.isMobileDataEnabled = false,
    this.activeDataSlot = 0,
    this.activeDataSubId = -1,
    this.sims = const [],
  });

  factory DeviceStatusModel.fromJson(Map<String, dynamic> json) {
    final rawSims = json['sims'] as List<dynamic>? ?? [];
    return DeviceStatusModel(
      batteryLevel: json['batteryLevel'] as int? ?? 100,
      isCharging: json['isCharging'] as bool? ?? false,
      signalBars: json['signalBars'] as int? ?? 4,
      networkType: json['networkType'] as String? ?? 'Zong 4G • VoLTE',
      isAdbConnected: json['isAdbConnected'] as bool? ?? false,
      isAirPodsConnected: json['isAirPodsConnected'] as bool? ?? false,
      isMobileDataEnabled: json['isMobileDataEnabled'] as bool? ?? false,
      activeDataSlot: json['activeDataSlot'] as int? ?? 0,
      activeDataSubId: json['activeDataSubId'] as int? ?? -1,
      sims: rawSims.map((s) => SimCardInfo.fromJson(Map<String, dynamic>.from(s))).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batteryLevel': batteryLevel,
      'isCharging': isCharging,
      'signalBars': signalBars,
      'networkType': networkType,
      'isAdbConnected': isAdbConnected,
      'isAirPodsConnected': isAirPodsConnected,
      'isMobileDataEnabled': isMobileDataEnabled,
      'activeDataSlot': activeDataSlot,
      'activeDataSubId': activeDataSubId,
      'sims': sims.map((s) => s.toJson()).toList(),
    };
  }
}

class RelayMessage {
  final String type;
  final Map<String, dynamic> data;
  final int timestamp;

  RelayMessage({
    required this.type,
    required this.data,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  String toJsonString() => jsonEncode({
        'type': type,
        'data': data,
        'timestamp': timestamp,
      });

  factory RelayMessage.fromJsonString(String rawJson) {
    final map = jsonDecode(rawJson) as Map<String, dynamic>;
    return RelayMessage(
      type: map['type'] as String? ?? 'UNKNOWN',
      data: Map<String, dynamic>.from(map['data'] as Map? ?? {}),
      timestamp: map['timestamp'] as int?,
    );
  }

  // Predefined Event Constructors
  static RelayMessage incomingRing({
    required String number,
    required String name,
    String? label,
  }) {
    return RelayMessage(
      type: 'INCOMING_RING',
      data: {
        'number': number,
        'name': name,
        'label': label,
      },
    );
  }

  static RelayMessage callDialing({
    required String number,
  }) {
    return RelayMessage(
      type: 'CALL_DIALING',
      data: {
        'number': number,
      },
    );
  }

  static RelayMessage callActive({
    required String number,
    required int startTime,
  }) {
    return RelayMessage(
      type: 'CALL_ACTIVE',
      data: {
        'number': number,
        'startTime': startTime,
      },
    );
  }

  static RelayMessage callDisconnected({
    required String number,
    required int duration,
    bool isMissed = false,
  }) {
    return RelayMessage(
      type: 'CALL_DISCONNECTED',
      data: {
        'number': number,
        'duration': duration,
        'isMissed': isMissed,
      },
    );
  }

  static RelayMessage actionDial(String number) {
    return RelayMessage(
      type: 'ACTION_DIAL',
      data: {'number': number},
    );
  }

  static RelayMessage actionAnswer() {
    return RelayMessage(type: 'ACTION_ANSWER', data: {});
  }

  static RelayMessage actionHangup() {
    return RelayMessage(type: 'ACTION_HANGUP', data: {});
  }

  static RelayMessage actionDtmf(String digit) {
    return RelayMessage(
      type: 'ACTION_DTMF',
      data: {'digit': digit},
    );
  }

  static RelayMessage actionSetMobileData(bool enabled) {
    return RelayMessage(
      type: 'ACTION_SET_MOBILE_DATA',
      data: {'enabled': enabled},
    );
  }

  static RelayMessage actionSetDataSim({required int slotIndex, required int subId}) {
    return RelayMessage(
      type: 'ACTION_SET_DATA_SIM',
      data: {
        'slotIndex': slotIndex,
        'subId': subId,
      },
    );
  }

  static RelayMessage ping() {
    return RelayMessage(type: 'PING', data: {});
  }

  static RelayMessage pong() {
    return RelayMessage(type: 'PONG', data: {});
  }

  static RelayMessage registerCloudSession({
    required String pairingKey,
    required String role,
  }) {
    return RelayMessage(
      type: 'REGISTER_CLOUD_SESSION',
      data: {
        'pairingKey': pairingKey,
        'role': role,
      },
    );
  }

  static RelayMessage callTick({
    required int duration,
    required String formatted,
  }) {
    return RelayMessage(
      type: 'CALL_TICK',
      data: {
        'duration': duration,
        'formatted': formatted,
      },
    );
  }

  static RelayMessage smsReceived({
    required String sender,
    required String body,
    int? timestamp,
  }) {
    return RelayMessage(
      type: 'SMS_RECEIVED',
      data: {
        'sender': sender,
        'body': body,
        'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  static RelayMessage webrtcOffer(String sdp) {
    return RelayMessage(
      type: 'WEBRTC_OFFER',
      data: {'sdp': sdp},
    );
  }

  static RelayMessage webrtcAnswer(String sdp) {
    return RelayMessage(
      type: 'WEBRTC_ANSWER',
      data: {'sdp': sdp},
    );
  }

  static RelayMessage webrtcIceCandidate(Map<String, dynamic> candidate) {
    return RelayMessage(
      type: 'WEBRTC_ICE_CANDIDATE',
      data: candidate,
    );
  }

  static RelayMessage actionSendSms({
    required String recipient,
    required String message,
  }) {
    return RelayMessage(
      type: 'ACTION_SEND_SMS',
      data: {
        'recipient': recipient,
        'message': message,
      },
    );
  }

  static RelayMessage smsSentStatus({
    required bool success,
    required String recipient,
    String? error,
  }) {
    return RelayMessage(
      type: 'SMS_SENT_STATUS',
      data: {
        'success': success,
        'recipient': recipient,
        'error': error,
      },
    );
  }

  static RelayMessage encryptedFrame(String ciphertext) {
    return RelayMessage(
      type: 'ENCRYPTED_FRAME',
      data: {'ciphertext': ciphertext},
    );
  }
}

class SavedConnection {
  final String id;
  final String name;
  final String ip;
  final int port;
  final bool isDefaultHotspot;

  SavedConnection({
    required this.id,
    required this.name,
    required this.ip,
    this.port = 8080,
    this.isDefaultHotspot = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'isDefaultHotspot': isDefaultHotspot,
      };

  factory SavedConnection.fromJson(Map<String, dynamic> json) => SavedConnection(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Host',
        ip: json['ip'] as String? ?? '192.168.43.1',
        port: json['port'] as int? ?? 8080,
        isDefaultHotspot: json['isDefaultHotspot'] as bool? ?? false,
      );
}
