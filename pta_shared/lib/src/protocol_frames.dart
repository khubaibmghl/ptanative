import 'dart:convert';

class DeviceStatusModel {
  final int batteryLevel; // 0 - 100
  final bool isCharging;
  final int signalBars; // 0 - 4
  final String networkType; // e.g. 'Zong 4G • VoLTE'
  final bool isAdbConnected;
  final bool isAirPodsConnected;

  DeviceStatusModel({
    required this.batteryLevel,
    required this.isCharging,
    required this.signalBars,
    required this.networkType,
    required this.isAdbConnected,
    required this.isAirPodsConnected,
  });

  factory DeviceStatusModel.fromJson(Map<String, dynamic> json) {
    return DeviceStatusModel(
      batteryLevel: json['batteryLevel'] as int? ?? 100,
      isCharging: json['isCharging'] as bool? ?? false,
      signalBars: json['signalBars'] as int? ?? 4,
      networkType: json['networkType'] as String? ?? 'Zong 4G • VoLTE',
      isAdbConnected: json['isAdbConnected'] as bool? ?? false,
      isAirPodsConnected: json['isAirPodsConnected'] as bool? ?? false,
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
  }) {
    return RelayMessage(
      type: 'CALL_DISCONNECTED',
      data: {
        'number': number,
        'duration': duration,
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
}
