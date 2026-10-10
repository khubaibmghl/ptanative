import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'telephony_controller.dart';
import 'relay_server.dart';
import '../models/activity_log.dart';

class HotspotService {
  final TelephonyController telephonyController;
  final RelayServer server;

  bool isHotspotActive = false;
  bool autoTetherEnabled = true;
  Timer? _monitorTimer;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  HotspotService({
    required this.telephonyController,
    required this.server,
  });

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    autoTetherEnabled = prefs.getBool('auto_tether_hotspot') ?? true;

    await checkStatus();
    _startMonitor();
  }

  void _startMonitor() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      await checkStatus();
      if (autoTetherEnabled && !isHotspotActive) {
        debugPrint('[HOTSPOT] Auto-tether enabled: hotspot dropped. Prompting start...');
        server.logEvent('Hotspot Monitor', 'Wi-Fi Hotspot inactive. Auto-tethering standby...', ActivityType.info);
      }
    });
  }

  Future<bool> checkStatus() async {
    final active = await telephonyController.isHotspotActive();
    if (active != isHotspotActive) {
      isHotspotActive = active;
      _statusController.add(isHotspotActive);
      server.logEvent(
        'Hotspot State',
        active ? 'Vivo S1 Hotspot Active (192.168.43.1)' : 'Hotspot Disabled',
        active ? ActivityType.success : ActivityType.info,
      );
    }
    return isHotspotActive;
  }

  Future<void> toggleAutoTether(bool enabled) async {
    autoTetherEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_tether_hotspot', enabled);
    server.logEvent('Hotspot Config', 'Auto-Tether set to $enabled', ActivityType.info);
  }

  Future<void> triggerStartHotspot() async {
    debugPrint('[HOTSPOT] Triggering hotspot start/settings...');
    server.logEvent('Hotspot Action', 'Opening Hotspot & Tethering setup', ActivityType.info);
    await telephonyController.openTetherSettings();
  }

  void dispose() {
    _monitorTimer?.cancel();
    _statusController.close();
  }
}
