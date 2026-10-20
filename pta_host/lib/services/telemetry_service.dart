import 'dart:async';
import 'dart:io';
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
  
  // Network Interface Breakdown
  String localIp = '192.168.60.21';
  String hotspotIp = '192.168.60.21';
  String wifiIp = '';
  String cellularIp = '';
  String activeNetworkLabel = 'Vivo Hotspot (192.168.60.21)';
  bool isHotspotBroadcasting = false;

  // Cache of last broadcasted values to prevent redundant radio wakeups
  int? _lastBroadcastBattery;
  bool? _lastBroadcastCharging;
  String? _lastBroadcastNetwork;
  int _lastBroadcastTime = 0;

  TelemetryService({required this.server}) {
    server.telemetryService = this;
  }

  void start() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 15), (_) => updateAndBroadcast());
    updateAndBroadcast(force: true);
  }

  void stop() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  Future<void> updateAndBroadcast({bool force = false}) async {
    try {
      batteryLevel = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      isCharging = (state == BatteryState.charging || state == BatteryState.full);
    } catch (_) {}

    final now = DateTime.now().millisecondsSinceEpoch;
    final bool batteryChanged = (_lastBroadcastBattery != batteryLevel);
    final bool chargingChanged = (_lastBroadcastCharging != isCharging);
    final bool intervalExpired = (now - _lastBroadcastTime >= 30000); // 30s gentle fallback

    if (!force && !batteryChanged && !chargingChanged && !intervalExpired) {
      // Data is unchanged and interval has not elapsed; skip radio wakeup
      return;
    }

    if (force || intervalExpired) {
      await refreshNetworkInterfaces();
    }

    final bool networkChanged = (_lastBroadcastNetwork != activeNetworkLabel);

    if (!force && !batteryChanged && !chargingChanged && !networkChanged && !intervalExpired) {
      return;
    }

    _lastBroadcastBattery = batteryLevel;
    _lastBroadcastCharging = isCharging;
    _lastBroadcastNetwork = activeNetworkLabel;
    _lastBroadcastTime = now;

    final dataStatus = await server.telephonyController.getTelephonyDataStatus();
    final isMobileDataEnabled = dataStatus['isMobileDataEnabled'] as bool? ?? false;
    final activeDataSlot = dataStatus['activeDataSlot'] as int? ?? 0;
    final activeDataSubId = dataStatus['activeDataSubId'] as int? ?? -1;
    final rawSims = dataStatus['sims'] as List<dynamic>? ?? [];
    final sims = rawSims.map((s) => SimCardInfo.fromJson(Map<String, dynamic>.from(s))).toList();

    final status = DeviceStatusModel(
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      signalBars: 4,
      networkType: 'Zong 4G • VoLTE',
      isAdbConnected: server.telephonyController.isAdbConnected,
      isAirPodsConnected: true,
      isMobileDataEnabled: isMobileDataEnabled,
      activeDataSlot: activeDataSlot,
      activeDataSubId: activeDataSubId,
      sims: sims,
    );

    server.broadcast(RelayMessage(
      type: 'DEVICE_STATUS',
      data: status.toJson(),
    ));
  }

  /// Scans all native network interfaces to accurately isolate Hotspot, Wi-Fi, and SIM Cellular IPs
  Future<void> refreshNetworkInterfaces() async {
    try {
      isHotspotBroadcasting = await server.telephonyController.isHotspotActive();
      String? foundWifi;
      String? foundHotspot;
      String? foundCellular;

      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.')) continue;

          // Hotspot interface patterns on Android (ap0, wlan1, softap, 192.168.60.x or 192.168.43.x)
          if (name.contains('ap') || name.contains('softap') || name.contains('tether') || ip.startsWith('192.168.60.') || ip.startsWith('192.168.43.')) {
            foundHotspot = ip;
          } else if (name.contains('wlan0') || (!name.contains('rmnet') && !name.contains('ccmni') && (ip.startsWith('192.168.') || ip.startsWith('10.0.') || ip.startsWith('172.')))) {
            // Wi-Fi Client connected to a router
            foundWifi = ip;
          } else if (name.contains('rmnet') || name.contains('ccmni') || name.contains('pdp')) {
            // SIM Cellular Data WAN IP
            foundCellular = ip;
          }
        }
      }

      // Fallback wifi IP from plugin
      if (foundWifi == null) {
        try {
          final pIp = await _networkInfo.getWifiIP();
          if (pIp != null && pIp.isNotEmpty && !pIp.startsWith('127.') && pIp != '0.0.0.0') {
            foundWifi = pIp;
          }
        } catch (_) {}
      }

      hotspotIp = foundHotspot ?? '192.168.60.21';
      wifiIp = foundWifi ?? '';
      cellularIp = foundCellular ?? '';

      // Set primary pairing IP priority:
      // 1. Hotspot is ACTIVE -> Vivo Hotspot IP
      // 2. Wi-Fi Client is ACTIVE -> Home/Office Router IP
      // 3. Fallback -> Hotspot default
      if (isHotspotBroadcasting || foundHotspot != null) {
        localIp = hotspotIp;
        activeNetworkLabel = 'Vivo Hotspot Direct ($localIp)';
      } else if (wifiIp.isNotEmpty) {
        localIp = wifiIp;
        activeNetworkLabel = 'Wi-Fi LAN ($wifiIp)';
      } else {
        localIp = hotspotIp;
        activeNetworkLabel = 'Standby Hotspot ($hotspotIp)';
      }
    } catch (_) {
      localIp = '192.168.60.21';
    }
  }
}
