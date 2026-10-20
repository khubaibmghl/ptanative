import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
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

  String? _currentLocalIp;
  int _pingLatency = -1;
  bool _isPinging = false;

  late AnimationController _syncAnimController;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<DeviceStatusModel>? _statusSub;

  // Optimistic UI state for Cellular Data & Dual SIM
  bool? _optimisticMobileData;
  int? _optimisticActiveSlot;
  int? _optimisticActiveSubId;
  bool _isSwitchingData = false;
  bool _isSwitchingSim = false;
  int? _targetSwitchSubId;

  @override
  void initState() {
    super.initState();
    _ipController.text = RelayClient.instance.hostIp;
    _portController.text = RelayClient.instance.hostPort.toString();
    _cloudUrlController.text = RelayClient.instance.cloudRelayUrl;
    _pairingKeyController.text = RelayClient.instance.pairingKey;

    _connectionSub = RelayClient.instance.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });

    _statusSub = RelayClient.instance.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          if (_optimisticMobileData != null && status.isMobileDataEnabled == _optimisticMobileData) {
            _optimisticMobileData = null;
          }
          if (_optimisticActiveSlot != null && status.activeDataSlot == _optimisticActiveSlot) {
            _optimisticActiveSlot = null;
          }
          if (_optimisticActiveSubId != null && status.activeDataSubId == _optimisticActiveSubId) {
            _optimisticActiveSubId = null;
          }
        });
      }
    });

    _syncAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _refreshNetworkState();
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _statusSub?.cancel();
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

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clipboard is empty'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }

    // Strip protocols and paths: ws://, wss://, http://, https://, trailing /ws, etc.
    var clean = text
        .replaceAll('ws://', '')
        .replaceAll('wss://', '')
        .replaceAll('http://', '')
        .replaceAll('https://', '');
    if (clean.contains('/')) {
      clean = clean.split('/').first;
    }

    String ip = clean.trim();
    int? port;
    if (clean.contains(':')) {
      final parts = clean.split(':');
      ip = parts[0].trim();
      port = int.tryParse(parts[1].trim());
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _ipController.text = ip;
      if (port != null && port > 0) {
        _portController.text = port.toString();
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.paste_rounded, color: LiquidGlassTheme.iosBlue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Pasted Host: $ip${port != null ? ":$port" : ""}'),
              ),
            ],
          ),
          backgroundColor: LiquidGlassTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _saveCurrentAsProfile() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8080;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid IP address first'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final exists = RelayClient.instance.savedConnections.any((c) => c.ip == ip && c.port == port);
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$ip:$port is already saved in your profiles'),
          backgroundColor: LiquidGlassTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final defaultName = (ip == '192.168.60.221' || ip == '192.168.43.1')
        ? 'Vivo S1 Hotspot'
        : (ip == '127.0.0.1' ? 'ADB Loopback' : 'Host ($ip)');

    await RelayClient.instance.addSavedConnection(defaultName, ip, port);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.bookmark_added_rounded, color: LiquidGlassTheme.gsmGreen, size: 20),
              const SizedBox(width: 8),
              Text('Saved "$defaultName" to profiles!'),
            ],
          ),
          backgroundColor: LiquidGlassTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  void _refreshNetworkState() async {
    final ip = await RelayClient.instance.getCurrentLocalIp();
    if (mounted) {
      setState(() {
        _currentLocalIp = ip;
      });
    }
    if (RelayClient.instance.isConnected) {
      _testPing();
    }
  }

  void _testPing() async {
    if (_isPinging) return;
    setState(() => _isPinging = true);
    final ms = await RelayClient.instance.measurePingLatency();
    if (mounted) {
      setState(() {
        _pingLatency = ms;
        _isPinging = false;
      });
    }
  }

  void _copyAllDiagnostics() {
    HapticFeedback.selectionClick();
    final logs = RelayClient.instance.diagnosticLogs.join('\n');
    Clipboard.setData(ClipboardData(text: logs.isNotEmpty ? logs : 'No diagnostic logs recorded yet.'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.copy_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Complete diagnostic logs copied to clipboard!'),
          ],
        ),
        backgroundColor: LiquidGlassTheme.surfaceDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = LiquidGlassTheme.isDarkMode;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1A2E) : const Color(0xFFF9F9FB),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Clear Cache & Reset',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Text(
            'This will clear local SQLite cached contacts, SMS and call history on this iPhone. All records will be freshly downloaded from your Vivo S1 host upon next sync.',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
          ),
          actionsPadding: const EdgeInsets.only(right: 16, bottom: 14),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: LiquidGlassTheme.crimsonRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await DatabaseHelper.instance.clearAll();
                _forceSync();
              },
              child: const Text('Clear & Resync', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Host IP Address',
                  hintText: '192.168.60.221',
                  hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  prefixIcon: const Icon(Icons.router_rounded, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_circle_outline_rounded, color: LiquidGlassTheme.gsmGreen, size: 20),
                    tooltip: 'Done',
                    onPressed: () => FocusScope.of(ctx).unfocus(),
                  ),
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
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Settings & Relay Mesh'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<DeviceStatusModel>(
                stream: RelayClient.instance.statusStream,
                initialData: RelayClient.instance.lastStatus,
                builder: (context, snapshot) {
                  final status = snapshot.data;
                  final isConnected = RelayClient.instance.isConnected;

                  return ListView(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 120),
                    children: [
                      // 1. Smart Local Network & Subnet Environment Banner (AT TOP FOR INSTANT CLARITY)
                      _buildSmartNetworkBanner(isDark),
                      const SizedBox(height: 14),

                      // 2. Direct Wi-Fi / Hotspot IP Configuration
                      _buildSectionHeader(
                        'HOST ADDRESS CONFIGURATION',
                        icon: Icons.router_rounded,
                        trailing: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: LiquidGlassTheme.iosBlue.withValues(alpha: 0.12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.paste_rounded, size: 14, color: LiquidGlassTheme.iosBlue),
                          label: const Text(
                            'Paste IP',
                            style: TextStyle(
                              color: LiquidGlassTheme.iosBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: _pasteFromClipboard,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDirectConfigCard(isConnected, isDark),
                      const SizedBox(height: 20),

                      // 3. Saved Host Connections
                      _buildSectionHeader(
                        'SAVED HOST PROFILES',
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

                      // 4. Vivo S1 Hardware Telemetry Pro Dashboard
                      _buildSectionHeader('VIVO S1 ENGINE TELEMETRY', icon: Icons.speed_rounded),
                      const SizedBox(height: 8),
                      _buildTelemetryDashboard(status, isConnected, isDark),
                      const SizedBox(height: 22),

                      // 5. Cellular Mobile Data & Dual SIM Control
                      _buildSectionHeader('CELLULAR & MOBILE DATA', icon: Icons.cell_tower_rounded),
                      const SizedBox(height: 8),
                      _buildCellularDataCard(status, isConnected, isDark),
                      const SizedBox(height: 22),

                      // 6. Diagnostics & System Maintenance
                      _buildSectionHeader('DIAGNOSTICS & SYSTEM TOOLS', icon: Icons.build_circle_rounded),
                      const SizedBox(height: 8),
                      _buildDiagnosticsCard(isDark),
                      const SizedBox(height: 24),

                      // 7. Minimal Clean Footer
                      Center(
                        child: Text(
                          'PTA Native • v1.4.0 (Build 27)',
                          style: TextStyle(
                            color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
            ],
          );
        },
      ),
    ),
    if (keyboardVisible) _buildKeyboardAccessoryBar(isDark),
  ],
),
      ),
    );
  }

  /// Authentic iOS keyboard accessory toolbar docked directly above the numeric keypad
  Widget _buildKeyboardAccessoryBar(bool isDark) {
    return Container(
      width: double.infinity,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C24) : const Color(0xFFEFEFF4),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.keyboard_rounded, size: 18, color: LiquidGlassTheme.iosBlue),
              const SizedBox(width: 8),
              Text(
                'Vivo Host IP / Port',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.mediumImpact();
              FocusScope.of(context).unfocus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: LiquidGlassTheme.gsmGreen,
                  width: 1,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: LiquidGlassTheme.gsmGreen),
                  SizedBox(width: 6),
                  Text(
                    'Done',
                    style: TextStyle(
                      color: LiquidGlassTheme.gsmGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

  /// 0. Smart Local Network & Subnet Environment Banner
  Widget _buildSmartNetworkBanner(bool isDark) {
    final isHotspot = _currentLocalIp != null && (_currentLocalIp!.startsWith('192.168.60.') || _currentLocalIp!.startsWith('192.168.43.'));
    final isWifi = _currentLocalIp != null && !isHotspot;

    final bannerColor = isHotspot
        ? LiquidGlassTheme.gsmGreen
        : (isWifi ? LiquidGlassTheme.iosBlue : Colors.orangeAccent);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bannerColor.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bannerColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHotspot
                  ? Icons.wifi_tethering_rounded
                  : (isWifi ? Icons.wifi_rounded : Icons.wifi_off_rounded),
              color: bannerColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isHotspot
                            ? 'Vivo Hotspot Mesh Active'
                            : (isWifi ? 'Wi-Fi LAN Connected' : 'Wi-Fi Offline / Standby'),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: bannerColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isHotspot ? 'ZERO-TYPING' : (isWifi ? 'LAN' : 'STANDBY'),
                        style: TextStyle(
                          color: bannerColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isHotspot
                      ? 'iPhone IP: ${_currentLocalIp ?? "192.168.60.x"} • Auto-locked to Host 192.168.60.221'
                      : (isWifi
                          ? 'iPhone IP: ${_currentLocalIp ?? "Wi-Fi"} • Scanning router subnet /24'
                          : 'Connect to Vivo S1 Hotspot in iOS Settings > Wi-Fi to auto-pair'),
                  style: TextStyle(
                    color: LiquidGlassTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: bannerColor,
            tooltip: 'Refresh Network State',
            onPressed: () {
              HapticFeedback.lightImpact();
              _refreshNetworkState();
            },
          ),
        ],
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

  void _handleMobileDataToggle(bool enabled) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _optimisticMobileData = enabled;
      _isSwitchingData = true;
    });

    final success = await RelayClient.instance.setMobileData(enabled);

    if (mounted) {
      setState(() {
        _isSwitchingData = false;
        if (!success) {
          _optimisticMobileData = null; // Revert
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success
                    ? (enabled ? Icons.wifi_tethering_rounded : Icons.portable_wifi_off_rounded)
                    : Icons.error_outline_rounded,
                color: success
                    ? (enabled ? LiquidGlassTheme.gsmGreen : Colors.orangeAccent)
                    : LiquidGlassTheme.crimsonRed,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  success
                      ? 'Mobile data ${enabled ? "enabled" : "disabled"} on Vivo S1.'
                      : 'Failed to toggle mobile data. Check connection.',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: LiquidGlassTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  void _handleDataSimSwitch({required int slotIndex, required int subId, required String simName}) async {
    HapticFeedback.selectionClick();
    setState(() {
      _optimisticActiveSlot = slotIndex;
      _optimisticActiveSubId = subId;
      _isSwitchingSim = true;
      _targetSwitchSubId = subId;
    });

    final success = await RelayClient.instance.setDataSim(slotIndex: slotIndex, subId: subId);

    if (mounted) {
      setState(() {
        _isSwitchingSim = false;
        _targetSwitchSubId = null;
        if (!success) {
          _optimisticActiveSlot = null;
          _optimisticActiveSubId = null;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.swap_horizontal_circle_rounded : Icons.error_outline_rounded,
                color: success ? LiquidGlassTheme.iosBlue : LiquidGlassTheme.crimsonRed,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  success
                      ? 'Switched mobile data connection to $simName on Vivo S1.'
                      : 'Failed to switch data SIM. Check connection.',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: LiquidGlassTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  /// Vivo S1 Cellular Mobile Data & Dual SIM Data Control Card
  Widget _buildCellularDataCard(DeviceStatusModel? status, bool isConnected, bool isDark) {
    final isMobileDataOn = _optimisticMobileData ?? (status?.isMobileDataEnabled ?? false);
    final activeSlot = _optimisticActiveSlot ?? (status?.activeDataSlot ?? 0);
    final activeSubId = _optimisticActiveSubId ?? (status?.activeDataSubId ?? -1);

    // List of SIMs from status or fallback to standard Vivo Dual SIM defaults
    final List<SimCardInfo> sims = (status != null && status.sims.isNotEmpty)
        ? status.sims
        : [
            SimCardInfo(slotIndex: 0, subId: 6, displayName: 'SIM 1', carrierName: 'ZONG'),
            SimCardInfo(slotIndex: 1, subId: 2, displayName: 'SIM 2', carrierName: 'Ufone'),
          ];

    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Master Mobile Data Toggle Row
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (isMobileDataOn && isConnected)
                      ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.15)
                      : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (isMobileDataOn && isConnected)
                        ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.3)
                        : (isDark ? Colors.white12 : Colors.black12),
                    width: 0.8,
                  ),
                ),
                child: Icon(
                  Icons.signal_cellular_alt_rounded,
                  color: (isMobileDataOn && isConnected)
                      ? LiquidGlassTheme.gsmGreen
                      : LiquidGlassTheme.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cellular Mobile Data',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !isConnected
                          ? 'Vivo host disconnected'
                          : (isMobileDataOn
                              ? 'Active (${sims.any((s) => s.slotIndex == activeSlot) ? (sims.firstWhere((s) => s.slotIndex == activeSlot).displayName.isNotEmpty ? sims.firstWhere((s) => s.slotIndex == activeSlot).displayName : "SIM ${activeSlot + 1}") : "SIM ${activeSlot + 1}"})'
                              : 'Cellular data disconnected'),
                      style: TextStyle(
                        color: !isConnected
                            ? LiquidGlassTheme.textSecondary
                            : (isMobileDataOn ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.textSecondary),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isSwitchingData)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(LiquidGlassTheme.gsmGreen),
                  ),
                )
              else
                Switch.adaptive(
                  value: isConnected && isMobileDataOn,
                  activeTrackColor: LiquidGlassTheme.gsmGreen,
                  onChanged: isConnected && !_isSwitchingData
                      ? (val) => _handleMobileDataToggle(val)
                      : null,
                ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
          const SizedBox(height: 14),

          // 2. Dual SIM Data Switcher Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.swap_horiz_rounded,
                    color: LiquidGlassTheme.iosBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'CELLULAR DATA LINE',
                    style: TextStyle(
                      color: LiquidGlassTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isConnected && isMobileDataOn)
                      ? LiquidGlassTheme.iosBlue.withValues(alpha: 0.12)
                      : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (isConnected && isMobileDataOn)
                        ? LiquidGlassTheme.iosBlue.withValues(alpha: 0.25)
                        : Colors.transparent,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  !isConnected
                      ? 'OFFLINE'
                      : (isMobileDataOn ? 'SIM ${activeSlot + 1} ONLINE' : 'DATA DISABLED'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: !isConnected
                        ? LiquidGlassTheme.textSecondary
                        : (isMobileDataOn ? LiquidGlassTheme.iosBlue : LiquidGlassTheme.textSecondary),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Select which SIM card provides mobile internet data on Vivo S1:',
            style: TextStyle(
              color: LiquidGlassTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),

          // 3. SIM 1 and SIM 2 Selection Cards
          Column(
            children: sims.map((sim) {
              final isSimActive = (sim.slotIndex == activeSlot) || (sim.subId == activeSubId && activeSubId != -1);
              final isCurrentSwitchTarget = _isSwitchingSim && _targetSwitchSubId == sim.subId;
              final slotLabel = 'SIM ${sim.slotIndex + 1}';
              final displayName = sim.displayName.isNotEmpty ? sim.displayName : slotLabel;
              final carrierName = sim.carrierName.isNotEmpty ? sim.carrierName : displayName;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: InkWell(
                  onTap: (isConnected && !isSimActive && !_isSwitchingSim)
                      ? () => _handleDataSimSwitch(
                            slotIndex: sim.slotIndex,
                            subId: sim.subId,
                            simName: '$slotLabel ($carrierName)',
                          )
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSimActive
                          ? LiquidGlassTheme.iosBlue.withValues(alpha: isDark ? 0.15 : 0.08)
                          : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSimActive
                            ? LiquidGlassTheme.iosBlue.withValues(alpha: 0.5)
                            : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                        width: isSimActive ? 1.4 : 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        // SIM badge icon
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSimActive
                                ? LiquidGlassTheme.iosBlue.withValues(alpha: 0.2)
                                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.sim_card_rounded,
                            color: isSimActive ? LiquidGlassTheme.iosBlue : LiquidGlassTheme.textSecondary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // SIM Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    carrierName,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black87,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      slotLabel,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: LiquidGlassTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isSimActive
                                    ? (isMobileDataOn ? 'Primary Cellular Data Active' : 'Selected (Data is Off)')
                                    : 'Tap to switch cellular data',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isSimActive
                                      ? (isMobileDataOn ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.textSecondary)
                                      : LiquidGlassTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Trailing Radio / Progress / Checkmark
                        if (isCurrentSwitchTarget)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(LiquidGlassTheme.iosBlue),
                            ),
                          )
                        else if (isSimActive)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: LiquidGlassTheme.iosBlue,
                            size: 22,
                          )
                        else
                          Icon(
                            Icons.radio_button_unchecked_rounded,
                            color: isConnected
                                ? LiquidGlassTheme.textSecondary.withValues(alpha: 0.5)
                                : LiquidGlassTheme.textSecondary.withValues(alpha: 0.2),
                            size: 22,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 2. Saved Host Connections (1-Tap Profile Switcher)
  Widget _buildSavedConnectionsList(bool isConnected, bool isDark) {
    final connections = RelayClient.instance.savedConnections;

    if (connections.isEmpty) {
      return GlassCard(
        borderRadius: 22,
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.alt_route_rounded, size: 32, color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Text(
                'No Saved Host Profiles',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap "Save as Profile" in the card above or "+ Add New" to bookmark addresses.',
                style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return GlassCard(
      borderRadius: 22,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ...connections.asMap().entries.map((entry) {
            final idx = entry.key;
            final conn = entry.value;
            final isActive = RelayClient.instance.hostIp == conn.ip &&
                RelayClient.instance.hostPort == conn.port;

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
                  borderRadius: BorderRadius.vertical(
                    top: idx == 0 ? const Radius.circular(22) : Radius.zero,
                    bottom: idx == connections.length - 1 ? const Radius.circular(22) : Radius.zero,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isActive
                          ? (isConnected
                              ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.07)
                              : LiquidGlassTheme.iosBlue.withValues(alpha: 0.06))
                          : Colors.transparent,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        // Connection Icon Squircle with soft glow
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isActive
                                ? (isConnected
                                    ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.2)
                                    : LiquidGlassTheme.iosBlue.withValues(alpha: 0.16))
                                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActive
                                  ? (isConnected
                                      ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.4)
                                      : LiquidGlassTheme.iosBlue.withValues(alpha: 0.35))
                                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            conn.isDefaultHotspot ? Icons.wifi_tethering_rounded : Icons.router_rounded,
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
                                        fontSize: 14,
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
                                  fontWeight: FontWeight.w500,
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
                                  ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.16)
                                  : Colors.orange.withValues(alpha: 0.16),
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

  /// 1. Direct Wi-Fi / Hotspot IP Configuration (High-Tech Futuristic Glass Pod)
  Widget _buildDirectConfigCard(bool isConnected, bool isDark) {
    final effectiveHostIp = _ipController.text.trim().isNotEmpty ? _ipController.text.trim() : '192.168.60.221';
    final effectivePort = _portController.text.trim().isNotEmpty ? _portController.text.trim() : '8080';
    final endpointUrl = 'ws://$effectiveHostIp:$effectivePort/ws';

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Cyber Header with Live Link Status
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isConnected
                        ? [LiquidGlassTheme.gsmGreen.withValues(alpha: 0.25), LiquidGlassTheme.gsmGreen.withValues(alpha: 0.1)]
                        : [LiquidGlassTheme.iosBlue.withValues(alpha: 0.25), LiquidGlassTheme.iosBlue.withValues(alpha: 0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isConnected
                        ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.4)
                        : LiquidGlassTheme.iosBlue.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.router_rounded,
                  size: 20,
                  color: isConnected ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.iosBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'HOST RELAY BRIDGE',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: (isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange)
                                  .withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isConnected ? 'ONLINE' : 'STANDBY',
                                style: TextStyle(
                                  color: isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Direct WebSocket pipe for VoLTE audio & GSM signaling',
                      style: TextStyle(
                        color: LiquidGlassTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Latency or Reconnect Trigger
              if (isConnected)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _isPinging ? null : _testPing,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isPinging)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: LiquidGlassTheme.gsmGreen),
                          )
                        else
                          const Icon(Icons.bolt_rounded, size: 12, color: LiquidGlassTheme.gsmGreen),
                        const SizedBox(width: 3),
                        Text(
                          _pingLatency >= 0
                              ? '${_pingLatency}ms'
                              : (RelayClient.instance.lastPingLatencyMs > 0
                                  ? '${RelayClient.instance.lastPingLatencyMs}ms'
                                  : 'Ping'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: LiquidGlassTheme.gsmGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // High-Tech Monospace Endpoint Bar with 1-Tap Copy
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 14, color: isConnected ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.iosBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    endpointUrl,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Clipboard.setData(ClipboardData(text: endpointUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Endpoint URL copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Icon(Icons.copy_rounded, size: 14, color: LiquidGlassTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // IP Address Input Pod
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: TextField(
              controller: _ipController,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontFamily: 'monospace',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                labelText: 'Vivo Host IP Address',
                hintText: '192.168.60.221',
                labelStyle: TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 12,
                ),
                prefixIcon: const Icon(Icons.lan_rounded, color: LiquidGlassTheme.iosBlue, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Quick Paste Chip
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _pasteFromClipboard,
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.content_paste_rounded, size: 12, color: LiquidGlassTheme.iosBlue),
                            SizedBox(width: 4),
                            Text(
                              'PASTE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: LiquidGlassTheme.iosBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // "Good sign" (✓ / Done) button to send back / dismiss keyboard
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        FocusScope.of(context).unfocus();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 14, color: LiquidGlassTheme.gsmGreen),
                            SizedBox(width: 3),
                            Text(
                              'DONE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: LiquidGlassTheme.gsmGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_ipController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => setState(() => _ipController.clear()),
                      ),
                  ],
                ),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 10),

          // Port Input Pod
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontFamily: 'monospace',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                labelText: 'Relay Port',
                hintText: '8080',
                labelStyle: TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 12,
                ),
                prefixIcon: const Icon(Icons.numbers_rounded, color: LiquidGlassTheme.iosBlue, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_portController.text.trim() != '8080')
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _portController.text = '8080');
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Default: 8080',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: LiquidGlassTheme.iosBlue,
                            ),
                          ),
                        ),
                      ),
                    // "Good sign" (✓ / Done) button to send back / dismiss keyboard
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        FocusScope.of(context).unfocus();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 14, color: LiquidGlassTheme.gsmGreen),
                            SizedBox(width: 3),
                            Text(
                              'DONE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: LiquidGlassTheme.gsmGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_portController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => setState(() => _portController.clear()),
                      ),
                  ],
                ),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 14),

          // Quick Presets Row
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 13, color: LiquidGlassTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                'QUICK PRESETS',
                style: TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildPresetChip('📱 Vivo Hotspot (192.168.60.221)', '192.168.60.221', 8080, isDark),
              _buildPresetChip('🏠 Home Wi-Fi (192.168.23.68)', '192.168.23.68', 8080, isDark),
              _buildPresetChip('💻 ADB Loopback (127.0.0.1)', '127.0.0.1', 8080, isDark),
              // Radar Auto-Discover Quick Chip
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _isDiscovering ? null : _autoDiscover,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isDiscovering)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: LiquidGlassTheme.iosBlue),
                        )
                      else
                        const Icon(Icons.radar_rounded, size: 13, color: LiquidGlassTheme.iosBlue),
                      const SizedBox(width: 5),
                      const Text(
                        '⚡ Auto-Discover',
                        style: TextStyle(
                          color: LiquidGlassTheme.iosBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main High-Tech Gradient Action Button
          Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isConnected
                    ? const [Color(0xFF34C759), Color(0xFF248A3D)]
                    : (_isSaving
                        ? const [Color(0xFF007AFF), Color(0xFF5856D6)]
                        : const [Color(0xFF007AFF), Color(0xFF0051C7)]),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? const Color(0xFF34C759) : const Color(0xFF007AFF))
                      .withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      isConnected ? Icons.check_circle_rounded : Icons.bolt_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
              label: Text(
                _isSaving
                    ? 'CONNECTING TO VIVO S1...'
                    : (isConnected ? 'CONNECTED • RE-SYNC NOW' : 'CONNECT TO HOST NOW'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
              onPressed: _isSaving ? null : _saveHostConfig,
            ),
          ),
          const SizedBox(height: 10),

          // Secondary Quick Actions Row: Save as Profile & Disconnect
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.8,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16, color: LiquidGlassTheme.iosBlue),
                  label: const Text(
                    'Save as Profile',
                    style: TextStyle(
                      color: LiquidGlassTheme.iosBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _saveCurrentAsProfile,
                ),
              ),
              if (isConnected) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: LiquidGlassTheme.crimsonRed.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.power_settings_new_rounded, size: 16, color: LiquidGlassTheme.crimsonRed),
                  label: const Text(
                    'Disconnect',
                    style: TextStyle(
                      color: LiquidGlassTheme.crimsonRed,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    RelayClient.instance.disconnect();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, String ip, int port, bool isDark) {
    final isSelected = _ipController.text.trim() == ip && _portController.text.trim() == port.toString();
    final chipColor = isSelected ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.iosBlue;

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.16)
              : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? chipColor
                : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 1.2 : 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(Icons.check_circle_rounded, size: 12, color: chipColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? chipColor : (isDark ? Colors.white70 : Colors.black87),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
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

          // Copy Diagnostic Logs
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.copy_rounded, color: Colors.blueGrey, size: 20),
            ),
            title: Text(
              'Copy Diagnostic Logs',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              'Copy recent 150+ socket, UDP and signaling frames to clipboard',
              style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _copyAllDiagnostics,
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1, indent: 56),

          // Clear Cached Database & Re-sync
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
            ),
            title: Text(
              'Clear Local Cache & Reset',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              'Purge local SQLite database and freshly resync from Vivo host',
              style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showClearCacheDialog,
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

}
