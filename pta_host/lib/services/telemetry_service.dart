import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:pta_shared/pta_shared.dart';
import 'relay_server.dart';

class TelemetryService {
  final RelayServer server;
  final Battery _battery = Battery();
  final NetworkInfo _networkInfo = NetworkInfo();
  Timer? _telemetryTimer;

  int batteryLevel = 100;
  bool isCharging = false;
  String localIp = '192.168.23.68';

  TelemetryService({required this.server});

  void start() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 15), (_) => updateAndBroadcast());
    updateAndBroadcast();
  }

  void stop() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  Future<void> updateAndBroadcast() async {
    try {
      batteryLevel = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      isCharging = (state == BatteryState.charging || state == BatteryState.full);

      final ip = await _networkInfo.getWifiIP();
      if (ip != null && ip.isNotEmpty) {
        localIp = ip;
      }
    } catch (_) {}

    final status = DeviceStatusModel(
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      signalBars: 4,
      networkType: 'Zong 4G • VoLTE',
      isAdbConnected: server.telephonyController.isAdbConnected,
      isAirPodsConnected: true,
    );

    server.broadcast(RelayMessage(
      type: 'DEVICE_STATUS',
      data: status.toJson(),
    ));
  }
}
