import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../services/relay_server.dart';
import '../services/telephony_monitor.dart';
import '../services/telemetry_service.dart';
import '../services/hotspot_service.dart';

class DashboardScreen extends StatefulWidget {
  final RelayServer server;
  final TelephonyMonitor monitor;
  final TelemetryService telemetry;
  final HotspotService? hotspotService;

  const DashboardScreen({
    super.key,
    required this.server,
    required this.monitor,
    required this.telemetry,
    this.hotspotService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isRelayRunning = false;
  bool _isBatteryOptIgnored = true;

  @override
  void initState() {
    super.initState();
    _isRelayRunning = widget.server.isRunning;
    _checkBatteryOptimization();
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _checkBatteryOptimization() async {
    try {
      final bool? ignored = await const MethodChannel('com.pta.host/telephony_methods')
          .invokeMethod<bool>('isBatteryOptimizationIgnored');
      if (mounted && ignored != null) {
        setState(() => _isBatteryOptIgnored = ignored);
      }
    } catch (_) {}
  }

  Future<void> _requestBatteryOptimization() async {
    try {
      await const MethodChannel('com.pta.host/telephony_methods')
          .invokeMethod('requestBatteryOptimization');
      await Future.delayed(const Duration(seconds: 1));
      _checkBatteryOptimization();
    } catch (_) {}
  }

  Future<void> _toggleRelay() async {
    if (_isRelayRunning) {
      widget.monitor.stop();
      widget.telemetry.stop();
      await widget.server.stopServer();
      setState(() => _isRelayRunning = false);
    } else {
      final ok = await widget.server.startServer();
      if (ok) {
        widget.monitor.start();
        widget.telemetry.start();
        await widget.server.telephonyController.checkAndConnectAdb();
        setState(() => _isRelayRunning = true);
      }
    }
  }

  void _triggerTestRing() {
    widget.server.broadcast(RelayMessage.incomingRing(
      number: '03001234567',
      name: 'Test Caller',
      label: 'Work',
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚡ Test call sent to iPhone 15 Pro via WebSocket!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inCall = widget.server.currentCallState['is_in_call'] == true;
    final connected = widget.server.currentCallState['is_connected'] == true;
    final callNum = widget.server.currentCallState['number']?.toString() ?? '';
    final callDur = widget.server.currentCallState['duration_formatted']?.toString() ?? '00:00';

    return Scaffold(
      appBar: AppBar(
        title: const Text(' PTA Relay Host', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. MASTER POWER SWITCH CARD
            GestureDetector(
              onTap: _toggleRelay,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isRelayRunning
                        ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                        : [Colors.grey.shade800, Colors.grey.shade900],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _isRelayRunning
                          ? const Color(0xFF2E7D32).withValues(alpha: 0.4)
                          : Colors.black.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      _isRelayRunning ? Icons.power_settings_new : Icons.power_off,
                      size: 56,
                      color: _isRelayRunning ? Colors.greenAccent : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isRelayRunning ? 'RELAY ACTIVE' : 'RELAY STOPPED',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isRelayRunning
                          ? 'Tap to stop server • Hotspot: ${widget.telemetry.localIp}:${RelayServer.port}'
                          : 'Tap to start embedded server & background monitor',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 1.5 PERSISTENCE & DEEP SLEEP PROTECTION CARD
            Card(
              color: _isBatteryOptIgnored ? const Color(0xFF1E281E) : const Color(0xFF2E2214),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: _isBatteryOptIgnored ? Colors.green.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _isBatteryOptIgnored ? Icons.shield_rounded : Icons.warning_amber_rounded,
                      color: _isBatteryOptIgnored ? Colors.greenAccent : Colors.orangeAccent,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isBatteryOptIgnored ? 'Screen-Off Sleep Protection: Active' : 'Doze Mode Whitelist Needed',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isBatteryOptIgnored
                                ? 'Cpu WakeLock & WifiLock active. Hotspot won\'t drop packets.'
                                : 'Tap to whitelist PTA Host so Vivo doesn\'t sleep the Wi-Fi socket.',
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                    ),
                    if (!_isBatteryOptIgnored)
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _requestBatteryOptimization,
                        child: const Text('Allow', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 1.5. VIVO HOTSPOT AUTO-TETHERING ENGINE CARD
            _buildHotspotCard(),

            const SizedBox(height: 12),

            // 2. ACTIVE CALL CARD
            if (inCall)
              Card(
                color: connected ? Colors.green.shade900 : Colors.amber.shade900,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Icon(
                          connected ? Icons.phone_in_talk : Icons.phone_callback,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected ? 'Call in Progress' : 'Incoming Ringing',
                              style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              PhoneNumberNormalizer.formatForDisplay(callNum),
                              style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            if (connected)
                              Text('Duration: $callDur', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: Colors.red),
                        icon: const Icon(Icons.call_end, color: Colors.white),
                        onPressed: () => widget.server.telephonyController.hangupCall(),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // 3. PAIRED CLIENTS CARD
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: widget.server.clientCount > 0
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.grey.withValues(alpha: 0.2),
                      child: Icon(
                        Icons.phone_iphone,
                        color: widget.server.clientCount > 0 ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('iPhone 15 Pro Client', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(
                            widget.server.clientCount > 0
                                ? 'Connected via WebSocket (${widget.server.clientCount} active)'
                                : 'Waiting for connection on ${widget.telemetry.localIp}...',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.server.clientCount > 0 ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: _triggerTestRing,
                      child: const Text('Test Ring'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // 4. REAL SYSTEM HEALTH CHIPS GRID
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                _buildStatusTile(
                  icon: Icons.wifi,
                  title: 'Host Network IP',
                  subtitle: widget.telemetry.localIp,
                  color: Colors.teal,
                ),
                _buildStatusTile(
                  icon: Icons.devices,
                  title: 'iPhone Clients',
                  subtitle: widget.server.clientCount > 0
                      ? '${widget.server.clientCount} Active'
                      : '0 Connected',
                  color: widget.server.clientCount > 0 ? Colors.green : Colors.grey,
                ),
                _buildStatusTile(
                  icon: Icons.adb,
                  title: 'ADB Call Drop',
                  subtitle: widget.server.telephonyController.isAdbConnected ? 'Active (5555)' : 'Disconnected',
                  color: widget.server.telephonyController.isAdbConnected ? Colors.green : Colors.orange,
                ),
                _buildStatusTile(
                  icon: widget.telemetry.isCharging ? Icons.battery_charging_full : Icons.battery_full,
                  title: 'Vivo Battery',
                  subtitle: '${widget.telemetry.batteryLevel}% ${widget.telemetry.isCharging ? '(Charging)' : ''}',
                  color: Colors.blue,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 5. VIVO S1 SCREEN-OFF PERSISTENCE CHECKLIST
            Card(
              color: Colors.white.withValues(alpha: 0.04),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 18, color: Colors.amberAccent),
                        SizedBox(width: 8),
                        Text('Vivo S1 Long Screen-Off Checklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      '1. Personal Hotspot ➔ Auto-turn off ➔ Set to "Never".\n2. Settings ➔ Battery ➔ High background power consumption ➔ PTA Host ➔ Allow.\n3. Settings ➔ Apps ➔ Autostart ➔ PTA Host ➔ On.',
                      style: TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), maxLines: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotspotCard() {
    final active = widget.hotspotService?.isHotspotActive ?? false;
    final autoTether = widget.hotspotService?.autoTetherEnabled ?? true;

    return Card(
      color: active ? const Color(0xFF1B3B2B) : const Color(0xFF262626),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: active ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                  child: Icon(
                    Icons.wifi_tethering_rounded,
                    color: active ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Vivo Hotspot Mesh',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: active ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              active ? 'BROADCASTING' : 'INACTIVE',
                              style: TextStyle(
                                color: active ? Colors.greenAccent : Colors.orangeAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        active ? 'AP Gateway: 192.168.43.1 • iPhone Auto-Sync Ready' : 'Hotspot is off. Tap below to start tethering.',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Switch(
                      value: autoTether,
                      onChanged: (val) {
                        widget.hotspotService?.toggleAutoTether(val);
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 6),
                    const Text('Auto-Tether Keep-Alive', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: active ? Colors.green.shade800 : Colors.orange.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await widget.hotspotService?.triggerStartHotspot();
                  },
                  child: Text(active ? 'Hotspot Settings' : 'Start Hotspot'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
