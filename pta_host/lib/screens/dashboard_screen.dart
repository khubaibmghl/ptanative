import 'package:flutter/material.dart';
import 'package:pta_shared/pta_shared.dart';
import '../services/relay_server.dart';
import '../services/telephony_monitor.dart';
import '../services/telemetry_service.dart';

class DashboardScreen extends StatefulWidget {
  final RelayServer server;
  final TelephonyMonitor monitor;
  final TelemetryService telemetry;

  const DashboardScreen({
    super.key,
    required this.server,
    required this.monitor,
    required this.telemetry,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isRelayRunning = false;

  @override
  void initState() {
    super.initState();
    _isRelayRunning = widget.server.isRunning;
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (mounted) setState(() {});
    });
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

            const SizedBox(height: 16),

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
}
