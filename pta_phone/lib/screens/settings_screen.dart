import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';
import '../widgets/diagnostic_console_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _cloudUrlController = TextEditingController();
  final _pairingKeyController = TextEditingController();
  bool _isSaving = false;
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _ipController.text = RelayClient.instance.hostIp;
    _portController.text = RelayClient.instance.hostPort.toString();
    _cloudUrlController.text = RelayClient.instance.cloudRelayUrl;
    _pairingKeyController.text = RelayClient.instance.pairingKey;
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
    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Host settings updated! Connecting to ${_ipController.text.trim()}...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _autoDiscover() async {
    HapticFeedback.lightImpact();
    setState(() => _isDiscovering = true);

    final discoveredIp = await RelayClient.instance.discoverHostIp();

    setState(() => _isDiscovering = false);

    if (discoveredIp != null && discoveredIp.isNotEmpty) {
      _ipController.text = discoveredIp;
      _saveHostConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found Vivo S1 Host at $discoveredIp! Connected.'),
            backgroundColor: LiquidGlassTheme.gsmGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Auto-discovery timed out. Please enter the Host IP shown on the Vivo S1 screen.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Settings & Relay Host'),
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
            padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 120),
            children: [
              // Connection Status Card
              GlassCard(
                borderRadius: 20,
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange).withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected
                                ? (RelayClient.instance.isConnectedViaCloud ? 'Connected (Remote Cloud)' : 'Connected (Vivo S1 Host)')
                                : 'Disconnected / Searching...',
                            style: TextStyle(
                              color: LiquidGlassTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            isConnected
                                ? 'ws://${RelayClient.instance.hostIp}:${RelayClient.instance.hostPort}/ws'
                                : 'Tap Auto-Discover or enter Vivo S1 IP below',
                            style: TextStyle(
                              color: LiquidGlassTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      color: LiquidGlassTheme.iosBlue,
                      onPressed: () {
                        RelayClient.instance.disconnect();
                        RelayClient.instance.connect();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Auto Discover Quick Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LiquidGlassTheme.iosBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _isDiscovering
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.radar, size: 20),
                  label: Text(
                    _isDiscovering ? 'Scanning Local Wi-Fi & Hotspot...' : '🔍 Auto-Discover Vivo S1 Host',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  onPressed: _isDiscovering ? null : _autoDiscover,
                ),
              ),
              const SizedBox(height: 20),

              // Host Configuration Card
              Text(
                'DIRECT WI-FI / HOTSPOT IP CONFIGURATION',
                style: TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                borderRadius: 20,
                child: Column(
                  children: [
                    TextField(
                      controller: _ipController,
                      style: TextStyle(color: LiquidGlassTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Vivo Host IP Address (e.g. 192.168.43.1 or 192.168.1.15)',
                        labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
                        prefixIcon: Icon(Icons.router, color: LiquidGlassTheme.iosBlue),
                        border: InputBorder.none,
                      ),
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                    TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: LiquidGlassTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Host Port (Default 8080)',
                        labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
                        prefixIcon: Icon(Icons.dns, color: LiquidGlassTheme.iosBlue),
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LiquidGlassTheme.gsmGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _isSaving ? null : _saveHostConfig,
                        child: const Text('Save & Connect Now', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Vivo Host Hardware Telemetry Card
              Text(
                'VIVO S1 ENGINE TELEMETRY',
                style: TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                borderRadius: 20,
                child: Column(
                  children: [
                    _buildStatusRow(
                      icon: Icons.battery_charging_full,
                      iconColor: LiquidGlassTheme.gsmGreen,
                      title: 'Vivo Battery',
                      value: status != null ? '${status.batteryLevel}% ${status.isCharging ? "(Charging)" : ""}' : '85%',
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                    _buildStatusRow(
                      icon: Icons.signal_cellular_alt,
                      iconColor: LiquidGlassTheme.iosBlue,
                      title: 'Cellular Network',
                      value: status?.networkType ?? 'Zong 4G • VoLTE',
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                    _buildStatusRow(
                      icon: Icons.cable,
                      iconColor: Colors.purpleAccent,
                      title: 'Hardware ADB Loopback',
                      value: status != null && status.isAdbConnected ? 'Active (:5555)' : 'Ready',
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                    ListTile(
                      leading: const Icon(Icons.bug_report_rounded, color: Colors.orangeAccent),
                      title: const Text('Live Telemetry Debugger', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Inspect raw WebSocket frames, pings & socket disconnects'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        DiagnosticConsoleSheet.show(context);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Optional Remote Cloud Relay Card
              Text(
                'REMOTE CLOUD RELAY (CROSS-NETWORK / CELLULAR DATA)',
                style: TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                borderRadius: 20,
                child: Column(
                  children: [
                    TextField(
                      controller: _cloudUrlController,
                      style: TextStyle(color: LiquidGlassTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Cloud WebSocket Server URL (Optional)',
                        hintText: 'wss://your-relay-domain.com/ws',
                        hintStyle: TextStyle(color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.5)),
                        labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
                        prefixIcon: Icon(Icons.cloud_outlined, color: LiquidGlassTheme.iosBlue),
                        border: InputBorder.none,
                      ),
                    ),
                    Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                    TextField(
                      controller: _pairingKeyController,
                      style: TextStyle(color: LiquidGlassTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Pairing Security Key',
                        labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
                        prefixIcon: Icon(Icons.key, color: LiquidGlassTheme.iosBlue),
                        border: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Manual Sync Actions
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(Icons.sync, color: LiquidGlassTheme.textPrimary),
                  label: Text('Force Sync Contacts & Call History', style: TextStyle(color: LiquidGlassTheme.textPrimary)),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await RelayClient.instance.syncAll();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Contacts & Call history synced!')),
                      );
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 15)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: LiquidGlassTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
