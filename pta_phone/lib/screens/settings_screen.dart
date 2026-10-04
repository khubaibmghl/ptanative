import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _ipController.text = RelayClient.instance.hostIp;
    _portController.text = RelayClient.instance.hostPort.toString();
  }

  void _saveHostConfig() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);
    final port = int.tryParse(_portController.text.trim()) ?? 8080;
    await RelayClient.instance.updateHostConfig(_ipController.text, port);
    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Host settings updated! Connecting...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Settings & Host')),
      body: StreamBuilder<DeviceStatusModel>(
        stream: RelayClient.instance.statusStream,
        initialData: RelayClient.instance.lastStatus,
        builder: (context, snapshot) {
          final status = snapshot.data;
          final isConnected = RelayClient.instance.isConnected;

          return ListView(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 100),
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
                            isConnected ? 'Connected to Vivo S1' : 'Searching for Vivo S1...',
                            style: const TextStyle(
                              color: LiquidGlassTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            isConnected
                                ? 'ws://${RelayClient.instance.hostIp}:${RelayClient.instance.hostPort}/ws'
                                : 'Ensure hotspot or local Wi-Fi is active',
                            style: const TextStyle(
                              color: LiquidGlassTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Vivo Host Hardware Telemetry Card
              const Text(
                'VIVO HOST ENGINE STATUS',
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
                    const Divider(color: Colors.white10, height: 1),
                    _buildStatusRow(
                      icon: Icons.signal_cellular_alt,
                      iconColor: LiquidGlassTheme.accentBlue,
                      title: 'Cellular Network',
                      value: status?.networkType ?? 'Zong 4G • VoLTE',
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    _buildStatusRow(
                      icon: Icons.cable,
                      iconColor: Colors.purpleAccent,
                      title: 'Hardware ADB Loopback',
                      value: status != null && status.isAdbConnected ? 'Active (:5555)' : 'Ready',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Host Configuration
              const Text(
                'HOST RELAY IP CONFIGURATION',
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
                      style: const TextStyle(color: LiquidGlassTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Host IP Address',
                        labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
                        border: InputBorder.none,
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: LiquidGlassTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Host Port (Default 8080)',
                        labelStyle: TextStyle(color: LiquidGlassTheme.textSecondary),
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LiquidGlassTheme.accentBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _isSaving ? null : _saveHostConfig,
                        child: const Text('Save & Reconnect', style: TextStyle(fontWeight: FontWeight.w600)),
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
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.sync, color: Colors.white),
                  label: const Text('Force Delta Sync Now', style: TextStyle(color: Colors.white)),
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
          Text(title, style: const TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 15)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
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
