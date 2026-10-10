import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../services/callkit_service.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';
import '../widgets/diagnostic_console_sheet.dart';
import '../widgets/phone_permission_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _cloudUrlController = TextEditingController();
  final _pairingKeyController = TextEditingController();

  bool _isSaving = false;
  bool _isDiscovering = false;
  bool _isSyncing = false;
  bool _obscurePairingKey = true;

  late AnimationController _radarController;
  late AnimationController _syncAnimController;

  @override
  void initState() {
    super.initState();
    _ipController.text = RelayClient.instance.hostIp;
    _portController.text = RelayClient.instance.hostPort.toString();
    _cloudUrlController.text = RelayClient.instance.cloudRelayUrl;
    _pairingKeyController.text = RelayClient.instance.pairingKey;

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _syncAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _radarController.dispose();
    _syncAnimController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _cloudUrlController.dispose();
    _pairingKeyController.dispose();
    super.dispose();
  }

  void _saveHostConfig() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);
    final port = int.tryParse(_portController.text.trim()) ?? 8080;
    await RelayClient.instance.updateHostConfig(
      _ipController.text,
      port,
      cloudUrl: _cloudUrlController.text,
      key: _pairingKeyController.text,
    );
    if (mounted) setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: LiquidGlassTheme.gsmGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Host configured! Connecting to ${_ipController.text.trim()}:$port...',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: LiquidGlassTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  void _autoDiscover() async {
    HapticFeedback.lightImpact();
    setState(() => _isDiscovering = true);

    final discoveredIp = await RelayClient.instance.discoverHostIp();

    if (mounted) setState(() => _isDiscovering = false);

    if (discoveredIp != null && discoveredIp.isNotEmpty) {
      _ipController.text = discoveredIp;
      _saveHostConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.radar_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Found Vivo S1 Host at $discoveredIp! Connected automatically.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: LiquidGlassTheme.gsmGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Auto-discovery timed out. Please verify Hotspot or enter Host IP manually.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.deepOrange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    }
  }

  void _switchTo(SavedConnection conn) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _ipController.text = conn.ip;
      _portController.text = conn.port.toString();
    });
    await RelayClient.instance.switchToConnection(conn);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${conn.name} (${conn.ip})! Handshaking...'),
          backgroundColor: LiquidGlassTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _removeConnection(SavedConnection conn) async {
    HapticFeedback.lightImpact();
    await RelayClient.instance.removeSavedConnection(conn.id);
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${conn.name}"'),
          backgroundColor: LiquidGlassTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _forceSync() async {
    HapticFeedback.selectionClick();
    setState(() => _isSyncing = true);
    _syncAnimController.repeat();

    await RelayClient.instance.syncAll();

    if (mounted) {
      _syncAnimController.stop();
      _syncAnimController.reset();
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: LiquidGlassTheme.gsmGreen, size: 20),
              SizedBox(width: 10),
              Text('Contacts & Call history synced successfully!'),
            ],
          ),
          backgroundColor: LiquidGlassTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  void _testCallKit() async {
    HapticFeedback.heavyImpact();
    try {
      await CallKitService.instance.showIncomingCall(
        callId: CallKitService.generateUuid(),
        callerName: 'Vivo S1 Engine (Test)',
        handle: '+92 300 1234567',
        label: 'Cellular Test',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.phone_in_talk_rounded, color: LiquidGlassTheme.gsmGreen, size: 20),
                SizedBox(width: 10),
                Text('CallKit simulation triggered! Check native iOS ring screen.'),
              ],
            ),
            backgroundColor: LiquidGlassTheme.surfaceDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error testing CallKit: $e')),
        );
      }
    }
  }

  void _showAddConnectionDialog() {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController(text: '192.168.');
    final portCtrl = TextEditingController(text: '8080');

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = LiquidGlassTheme.isDarkMode;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1A2E) : const Color(0xFFF9F9FB),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_link_rounded, color: LiquidGlassTheme.iosBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Add Host Profile',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Profile Name',
                  hintText: 'e.g. Office Wi-Fi, Portable Router',
                  hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  prefixIcon: const Icon(Icons.bookmark_border_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ipCtrl,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Host IP Address',
                  hintText: '192.168.43.1',
                  hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  prefixIcon: const Icon(Icons.router_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: portCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Port (Default 8080)',
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  prefixIcon: const Icon(Icons.dns_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.only(right: 20, bottom: 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: LiquidGlassTheme.iosBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final ip = ipCtrl.text.trim();
                final port = int.tryParse(portCtrl.text.trim()) ?? 8080;
                if (ip.isNotEmpty) {
                  await RelayClient.instance.addSavedConnection(
                    name.isNotEmpty ? name : ip,
                    ip,
                    port,
                  );
                  if (mounted) setState(() {});
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Save Profile', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Settings & Relay Mesh'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<DeviceStatusModel>(
        stream: RelayClient.instance.statusStream,
        initialData: RelayClient.instance.lastStatus,
        builder: (context, snapshot) {
          final status = snapshot.data;
          final isConnected = RelayClient.instance.isConnected;

          return ListView(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 120),
            children: [
              // 1. Connection Hero & Mesh State
              _buildConnectionHeroCard(isConnected, isDark),
              const SizedBox(height: 16),

              // 2. High-Tech Automated Auto-Discovery Action Card
              _buildAutomatedDiscoveryCard(isConnected, isDark),
              const SizedBox(height: 22),

              // 3. Vivo S1 Hardware Telemetry Pro Dashboard
              _buildSectionHeader('VIVO S1 ENGINE TELEMETRY', icon: Icons.speed_rounded),
              const SizedBox(height: 8),
              _buildTelemetryDashboard(status, isConnected, isDark),
              const SizedBox(height: 22),

              // 4. Saved Host Connections (1-Tap Switcher)
              _buildSectionHeader(
                'SAVED HOST CONNECTIONS',
                icon: Icons.alt_route_rounded,
                trailing: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: LiquidGlassTheme.iosBlue.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16, color: LiquidGlassTheme.iosBlue),
                  label: const Text(
                    'Add New',
                    style: TextStyle(
                      color: LiquidGlassTheme.iosBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: _showAddConnectionDialog,
                ),
              ),
              const SizedBox(height: 8),
              _buildSavedConnectionsList(isConnected, isDark),
              const SizedBox(height: 22),

              // 5. Direct Wi-Fi / Hotspot IP Configuration
              _buildSectionHeader('DIRECT NETWORK CONFIGURATION', icon: Icons.tune_rounded),
              const SizedBox(height: 8),
              _buildDirectConfigCard(isDark),
              const SizedBox(height: 22),

              // 6. Remote Cloud Relay (WAN Tunnel)
              _buildSectionHeader('REMOTE CLOUD RELAY (WAN ACCESS)', icon: Icons.cloud_sync_rounded),
              const SizedBox(height: 8),
              _buildCloudRelayCard(isDark),
              const SizedBox(height: 22),

              // 7. Diagnostics & System Maintenance
              _buildSectionHeader('DIAGNOSTICS & SYSTEM TOOLS', icon: Icons.build_circle_rounded),
              const SizedBox(height: 8),
              _buildDiagnosticsCard(isDark),
              const SizedBox(height: 24),

              // 8. Architecture & Engine About Footer
              _buildArchitectureFooter(isDark),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // --- UI Builder Sections ---

  Widget _buildSectionHeader(String title, {IconData? icon, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: LiquidGlassTheme.textSecondary),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: TextStyle(
              color: LiquidGlassTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing,
          ],
        ],
      ),
    );
  }

  /// 1. Top Connection Hero Card with Live Status & Endpoint
  Widget _buildConnectionHeroCard(bool isConnected, bool isDark) {
    final viaCloud = RelayClient.instance.isConnectedViaCloud;
    final accentColor = isConnected
        ? (viaCloud ? LiquidGlassTheme.iosBlue : LiquidGlassTheme.gsmGreen)
        : Colors.orangeAccent;

    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Breathing glowing pulse indicator
              AnimatedBuilder(
                animation: _radarController,
                builder: (context, child) {
                  final glowRadius = 4.0 + (_radarController.value * 6.0);
                  return Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: isConnected ? 0.6 : 0.3),
                          blurRadius: glowRadius,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected
                          ? (viaCloud ? 'Connected • Cloud Gateway Tunnel' : 'Connected • Vivo S1 Direct Mesh')
                          : 'Disconnected / Searching...',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConnected
                          ? (viaCloud ? 'WAN remote link active via cloud server' : 'Ultra-low latency Wi-Fi/Hotspot socket link')
                          : 'Tap Auto-Discover or select a connection profile below',
                      style: TextStyle(
                        color: LiquidGlassTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Refresh / Reconnect Action
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: LiquidGlassTheme.iosBlue,
                  tooltip: 'Reconnect Now',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    RelayClient.instance.disconnect();
                    RelayClient.instance.connect();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Active Endpoint Chip with 1-Tap Copy
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 16, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ws://${RelayClient.instance.hostIp}:${RelayClient.instance.hostPort}/ws',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    final url = 'ws://${RelayClient.instance.hostIp}:${RelayClient.instance.hostPort}/ws';
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Endpoint copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(Icons.copy_rounded, size: 14, color: LiquidGlassTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 2. Automated Auto-Discovery Card with Live Animated Radar Scanner
  Widget _buildAutomatedDiscoveryCard(bool isConnected, bool isDark) {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _isDiscovering ? null : _autoDiscover,
        child: Row(
          children: [
            // Radar visual scanner animation
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(54, 54),
                  painter: _RadarScopePainter(
                    rotation: _radarController.value * 2 * math.pi,
                    isScanning: _isDiscovering,
                    isConnected: isConnected,
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _isDiscovering ? 'Scanning Mesh Network...' : 'Auto-Discover Vivo S1',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AUTOMATED',
                          style: TextStyle(
                            color: LiquidGlassTheme.iosBlue,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isDiscovering
                        ? 'Broadcasting UDP :8081 & scanning standard hotspot gateways...'
                        : 'Probes 192.168.43.1 hotspot gateway, local subnets & auto-pairs',
                    style: TextStyle(
                      color: LiquidGlassTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: _isDiscovering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: LiquidGlassTheme.iosBlue),
                    )
                  : const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: LiquidGlassTheme.iosBlue),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. Hardware Telemetry Pro Dashboard
  Widget _buildTelemetryDashboard(DeviceStatusModel? status, bool isConnected, bool isDark) {
    final battery = status?.batteryLevel ?? 85;
    final isCharging = status?.isCharging ?? false;
    final signalBars = status?.signalBars ?? 4;
    final carrier = status?.networkType ?? 'Zong 4G • VoLTE';
    final isAdb = status?.isAdbConnected ?? false;
    final isAirPods = status?.isAirPodsConnected ?? false;

    // Battery theme color
    final batteryColor = battery > 20
        ? LiquidGlassTheme.gsmGreen
        : (battery > 10 ? Colors.orangeAccent : LiquidGlassTheme.crimsonRed);

    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 2x2 Telemetry Metric Matrix
          Row(
            children: [
              // Metric 1: Battery Gauge
              Expanded(
                child: _buildTelemetryCell(
                  isDark: isDark,
                  icon: isCharging ? Icons.battery_charging_full_rounded : Icons.battery_full_rounded,
                  iconColor: batteryColor,
                  title: 'Vivo Battery',
                  value: '$battery%',
                  subtext: isCharging ? '⚡ Fast Charging' : 'Discharging',
                  extraWidget: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: battery / 100.0,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
                      minHeight: 4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Metric 2: Cellular & SIM Signal
              Expanded(
                child: _buildTelemetryCell(
                  isDark: isDark,
                  icon: Icons.cell_tower_rounded,
                  iconColor: LiquidGlassTheme.iosBlue,
                  title: 'GSM Cellular',
                  value: carrier.split('•').first.trim(),
                  subtext: carrier.contains('VoLTE') ? 'VoLTE HD Active' : 'Active SIM',
                  extraWidget: _buildSignalMeter(signalBars),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Metric 3: Bridge Gateway Port
              Expanded(
                child: _buildTelemetryCell(
                  isDark: isDark,
                  icon: Icons.router_rounded,
                  iconColor: Colors.deepPurpleAccent,
                  title: 'Engine Bridge',
                  value: 'Port ${RelayClient.instance.hostPort}',
                  subtext: isConnected ? 'Socket Live (:8080)' : 'Standby',
                ),
              ),
              const SizedBox(width: 12),
              // Metric 4: Hardware USB Loopback / AirPods
              Expanded(
                child: _buildTelemetryCell(
                  isDark: isDark,
                  icon: isAirPods ? Icons.headphones_rounded : Icons.cable_rounded,
                  iconColor: isAirPods ? Colors.tealAccent : Colors.amberAccent,
                  title: isAirPods ? 'Audio Route' : 'Hardware ADB',
                  value: isAirPods ? 'AirPods Active' : (isAdb ? 'Active (:5555)' : 'Loopback Ready'),
                  subtext: isAirPods ? 'Lossless PCM Tunnel' : 'Reverse Tethering',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryCell({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtext,
    Widget? extraWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: LiquidGlassTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: TextStyle(
              color: LiquidGlassTheme.textSecondary,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (extraWidget != null) ...[
            const SizedBox(height: 6),
            extraWidget,
          ],
        ],
      ),
    );
  }

  Widget _buildSignalMeter(int bars) {
    return Row(
      children: List.generate(4, (index) {
        final isActive = index < bars;
        final barHeight = 4.0 + (index * 3.0);
        return Container(
          width: 3,
          height: barHeight,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: isActive ? LiquidGlassTheme.iosBlue : Colors.white24,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }

  /// 4. Saved Host Connections (1-Tap Switcher)
  Widget _buildSavedConnectionsList(bool isConnected, bool isDark) {
    final connections = RelayClient.instance.savedConnections;

    return GlassCard(
      borderRadius: 22,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ...connections.asMap().entries.map((entry) {
            final idx = entry.key;
            final conn = entry.value;
            final isActive = RelayClient.instance.hostIp == conn.ip;

            return Column(
              children: [
                if (idx > 0)
                  Divider(
                    color: isDark ? Colors.white10 : Colors.black12,
                    height: 1,
                    indent: 54,
                  ),
                InkWell(
                  onTap: () => _switchTo(conn),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        // Connection Icon Squircle
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isActive
                                ? (isConnected
                                    ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.2)
                                    : LiquidGlassTheme.iosBlue.withValues(alpha: 0.15))
                                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            conn.isDefaultHotspot ? Icons.wifi_tethering_rounded : Icons.wifi_rounded,
                            color: isActive
                                ? (isConnected ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.iosBlue)
                                : LiquidGlassTheme.textSecondary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Profile Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      conn.name,
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (conn.isDefaultHotspot) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.07),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'HOTSPOT',
                                        style: TextStyle(
                                          color: LiquidGlassTheme.textSecondary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${conn.ip}:${conn.port}',
                                style: TextStyle(
                                  color: LiquidGlassTheme.textSecondary,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right Trailing Status & Actions
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isConnected
                                  ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.2)
                                  : Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isConnected ? Icons.check_circle_rounded : Icons.sync_rounded,
                                  size: 12,
                                  color: isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isConnected ? 'ACTIVE' : 'CONNECTING',
                                  style: TextStyle(
                                    color: isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: LiquidGlassTheme.iosBlue.withValues(alpha: 0.15),
                              foregroundColor: LiquidGlassTheme.iosBlue,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _switchTo(conn),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bolt_rounded, size: 14),
                                SizedBox(width: 2),
                                Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        if (!conn.isDefaultHotspot) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            color: LiquidGlassTheme.crimsonRed.withValues(alpha: 0.7),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _removeConnection(conn),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// 5. Direct Wi-Fi / Hotspot IP Configuration (With 1-Tap Quick Network Chips)
  Widget _buildDirectConfigCard(bool isDark) {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Automated Quick Presets Row
          Text(
            'QUICK PRESETS (1-TAP AUTOFILL)',
            style: TextStyle(
              color: LiquidGlassTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildPresetChip('📱 Vivo Hotspot (192.168.43.1)', '192.168.43.1', 8080, isDark),
              _buildPresetChip('🏠 Home Wi-Fi (192.168.23.68)', '192.168.23.68', 8080, isDark),
              _buildPresetChip('💻 ADB Loopback (127.0.0.1)', '127.0.0.1', 8080, isDark),
            ],
          ),
          const SizedBox(height: 14),

          // IP Field
          TextField(
            controller: _ipController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Vivo Host IP Address',
              hintText: '192.168.43.1',
              labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
              prefixIcon: const Icon(Icons.router_rounded, color: LiquidGlassTheme.iosBlue),
              suffixIcon: _ipController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => setState(() => _ipController.clear()),
                    )
                  : null,
              border: InputBorder.none,
            ),
            onChanged: (_) => setState(() {}),
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),

          // Port Field
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Host Port (Default 8080)',
              labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
              prefixIcon: const Icon(Icons.dns_rounded, color: LiquidGlassTheme.iosBlue),
              suffixIcon: _portController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => setState(() => _portController.clear()),
                    )
                  : null,
              border: InputBorder.none,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),

          // Save & Connect Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: LiquidGlassTheme.gsmGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                _isSaving ? 'Connecting to Host...' : 'Save & Connect Now',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: _isSaving ? null : _saveHostConfig,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, String ip, int port, bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _ipController.text = ip;
          _portController.text = port.toString();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            width: 0.6,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// 6. Remote Cloud Relay Card (WAN Access)
  Widget _buildCloudRelayCard(bool isDark) {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _cloudUrlController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Cloud WebSocket Server URL (Optional)',
              hintText: 'wss://your-relay-domain.com/ws',
              hintStyle: TextStyle(color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.5)),
              labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
              prefixIcon: const Icon(Icons.cloud_outlined, color: LiquidGlassTheme.iosBlue),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    tooltip: 'Paste URL',
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && mounted) {
                        setState(() => _cloudUrlController.text = data!.text!);
                      }
                    },
                  ),
                  if (_cloudUrlController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => setState(() => _cloudUrlController.clear()),
                    ),
                ],
              ),
              border: InputBorder.none,
            ),
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
          TextField(
            controller: _pairingKeyController,
            obscureText: _obscurePairingKey,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Pairing Security Key',
              labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
              prefixIcon: const Icon(Icons.key_rounded, color: LiquidGlassTheme.iosBlue),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _obscurePairingKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscurePairingKey = !_obscurePairingKey),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    tooltip: 'Paste Key',
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && mounted) {
                        setState(() => _pairingKeyController.text = data!.text!);
                      }
                    },
                  ),
                ],
              ),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  /// 7. Diagnostics & System Maintenance Tools
  Widget _buildDiagnosticsCard(bool isDark) {
    return GlassCard(
      borderRadius: 22,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Live Telemetry & Frame Debugger
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bug_report_rounded, color: Colors.orange, size: 20),
            ),
            title: Text(
              'Live Telemetry Debugger',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              'Inspect raw WebSocket frames, pings & socket disconnects',
              style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              HapticFeedback.lightImpact();
              DiagnosticConsoleSheet.show(context);
            },
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1, indent: 56),

          // Force Sync Contacts & Call History
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: RotationTransition(
                turns: _syncAnimController,
                child: const Icon(Icons.sync_rounded, color: LiquidGlassTheme.iosBlue, size: 20),
              ),
            ),
            title: Text(
              'Force Sync Contacts & History',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              'Re-fetch latest contacts and call history from Vivo S1',
              style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 12),
            ),
            trailing: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: LiquidGlassTheme.iosBlue),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: _isSyncing ? null : _forceSync,
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1, indent: 56),

          // Test CallKit Ringing
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phone_in_talk_rounded, color: LiquidGlassTheme.gsmGreen, size: 20),
            ),
            title: Text(
              'Test Apple CallKit Ringing',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              'Simulate native iOS incoming full-screen / banner ring screen',
              style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _testCallKit,
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1, indent: 56),

          // iOS Permissions Setup
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.security_rounded, color: Colors.purpleAccent, size: 20),
            ),
            title: Text(
              'iOS Permissions Setup',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              'Verify Microphone, Contacts & Notification access',
              style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              HapticFeedback.lightImpact();
              PhonePermissionSheet.show(context);
            },
          ),
        ],
      ),
    );
  }

  /// 8. Engine Architecture & Version Card
  Widget _buildArchitectureFooter(bool isDark) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.phonelink_ring_rounded, color: LiquidGlassTheme.iosBlue, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          'PTA Native Client for iPhone',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'v1.4.0 (Build 27) • Apple CallKit & Vivo S1 Telephony Engine',
          style: TextStyle(
            color: LiquidGlassTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Custom Animated Radar Scope Painter
class _RadarScopePainter extends CustomPainter {
  final double rotation;
  final bool isScanning;
  final bool isConnected;

  _RadarScopePainter({
    required this.rotation,
    required this.isScanning,
    required this.isConnected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Scope background
    final bgPaint = Paint()
      ..color = const Color(0xFF007AFF).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius, bgPaint);

    // Range rings
    final ringPaint = Paint()
      ..color = const Color(0xFF007AFF).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, maxRadius * 0.4, ringPaint);
    canvas.drawCircle(center, maxRadius * 0.75, ringPaint);
    canvas.drawCircle(center, maxRadius, ringPaint);

    // Crosshairs
    final crossPaint = Paint()
      ..color = const Color(0xFF007AFF).withValues(alpha: 0.2)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), crossPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), crossPaint);

    // Rotating Radar Sweep Beam
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi / 2,
        colors: [
          (isConnected ? const Color(0xFF34C759) : const Color(0xFF007AFF)).withValues(alpha: 0.0),
          (isConnected ? const Color(0xFF34C759) : const Color(0xFF007AFF)).withValues(alpha: 0.4),
        ],
        transform: GradientRotation(rotation),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, sweepPaint);

    // Center Blinking / Glowing Target Dot
    final targetColor = isConnected
        ? const Color(0xFF34C759)
        : (isScanning ? const Color(0xFF007AFF) : Colors.orangeAccent);

    final dotPaint = Paint()
      ..color = targetColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.5, dotPaint);

    final glowPaint = Paint()
      ..color = targetColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, 5.5, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarScopePainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.isScanning != isScanning ||
        oldDelegate.isConnected != isConnected;
  }
}
