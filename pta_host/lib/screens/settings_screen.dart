import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pta_shared/pta_shared.dart';
import '../services/relay_server.dart';
import '../services/telephony_controller.dart';
import '../services/telemetry_service.dart';
import '../services/hotspot_service.dart';
import '../services/host_permission_service.dart';
import '../widgets/host_permission_sheet.dart';

class SettingsScreen extends StatefulWidget {
  final RelayServer server;
  final TelephonyController telephonyController;
  final TelemetryService? telemetry;
  final HotspotService? hotspotService;

  const SettingsScreen({
    super.key,
    required this.server,
    required this.telephonyController,
    this.telemetry,
    this.hotspotService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoStartOnBoot = true;
  bool _autoTether = true;
  bool _isBatteryIgnored = false;
  bool _isHotspotActive = false;
  Map<Permission, PermissionStatus> _permissionStatuses = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkSystemHealth();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoStartOnBoot = prefs.getBool('auto_start_on_boot') ?? true;
      _autoTether = prefs.getBool('auto_tether_hotspot') ?? true;
    });
  }

  Future<void> _checkSystemHealth() async {
    try {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      final hotspot = await widget.telephonyController.isHotspotActive();
      final statuses = await HostPermissionService.checkAllStatuses();
      if (mounted) {
        setState(() {
          _isBatteryIgnored = batteryStatus.isGranted;
          _isHotspotActive = hotspot;
          _permissionStatuses = statuses;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleAutoStart(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_start_on_boot', val);
    setState(() => _autoStartOnBoot = val);
  }

  Future<void> _toggleAutoTether(bool val) async {
    if (widget.hotspotService != null) {
      await widget.hotspotService!.toggleAutoTether(val);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_tether_hotspot', val);
    }
    setState(() => _autoTether = val);
  }

  Future<void> _requestBatteryOptimizationBypass() async {
    HapticFeedback.lightImpact();
    await Permission.ignoreBatteryOptimizations.request();
    _checkSystemHealth();
  }

  Future<void> _requestPermissions() async {
    await HostPermissionSheet.show(
      context,
      onGranted: () {
        widget.server.contentService?.syncAllFromDevice();
        _checkSystemHealth();
      },
    );
  }

  void _broadcastBeacon() {
    HapticFeedback.lightImpact();
    widget.server.broadcastUdpBurst(RelayMessage.ping(), count: 5);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.radar_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'High-priority pairing beacon burst (5x UDP packets) sent on :8081!',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showTestCallDialog() {
    final numberCtrl = TextEditingController(text: '+92 300 1234567');
    final nameCtrl = TextEditingController(text: 'Vivo S1 Test Caller');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.phone_in_talk, color: Colors.green, size: 18),
              ),
              SizedBox(width: 10),
              Text('Simulate Incoming Call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Dispatches incoming ring event to iPhone via WebSocket and bursts 5 UDP packets across subnet for instant CallKit ring trigger.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: numberCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Caller Number',
                  prefixIcon: const Icon(Icons.dialpad_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Caller Display Name',
                  prefixIcon: const Icon(Icons.person_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final num = numberCtrl.text.trim();
                final name = nameCtrl.text.trim();
                Navigator.of(ctx).pop();

                final msg = RelayMessage.incomingRing(
                  number: num.isNotEmpty ? num : '+92 300 1234567',
                  name: name.isNotEmpty ? name : 'Test Caller',
                  label: 'Simulated Cellular',
                );

                widget.server.broadcast(msg);
                widget.server.broadcastUdpBurst(msg, count: 5);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('⚡ Ringing dispatched to iPhone for $num ($name)!'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Send Ring Event'),
            ),
          ],
        );
      },
    );
  }

  void _showTestSmsDialog() {
    final senderCtrl = TextEditingController(text: 'HBL-Alert');
    final bodyCtrl = TextEditingController(
      text: 'Your OTP is 849201. Valid for 5 minutes. PTA Native Relay Test.',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.sms_rounded, color: Colors.blue, size: 18),
              ),
              SizedBox(width: 10),
              Text('Simulate Incoming SMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Dispatches cellular SMS with automatic OTP extraction directly to iPhone database and active notification.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: senderCtrl,
                decoration: InputDecoration(
                  labelText: 'Sender / Bank Name',
                  prefixIcon: const Icon(Icons.business_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Message Body',
                  prefixIcon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final sender = senderCtrl.text.trim();
                final body = bodyCtrl.text.trim();
                Navigator.of(ctx).pop();

                widget.server.handleIncomingSms(
                  sender.isNotEmpty ? sender : 'HBL-Alert',
                  body.isNotEmpty ? body : 'Test SMS Body',
                  DateTime.now().millisecondsSinceEpoch,
                );

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('💬 SMS dispatched to iPhone from $sender!'),
                    backgroundColor: Colors.blue,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Send SMS'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cellularIp = widget.telemetry?.cellularIp ?? '';
    final wifiIp = widget.telemetry?.wifiIp ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Settings & Mesh Control', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Diagnostics',
            onPressed: () {
              HapticFeedback.lightImpact();
              _checkSystemHealth();
              widget.telemetry?.refreshNetworkInterfaces();
              setState(() {});
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. NETWORK MESH & IP ADDRESS DEMYSTIFIER CARD
          _buildNetworkMeshCard(cellularIp, wifiIp),
          const SizedBox(height: 14),

          // 2. VIVO HOTSPOT AP MANAGER CARD
          _buildHotspotControlCard(),
          const SizedBox(height: 14),

          // 3. VIVO FUNTOUCHOS BATTERY & BACKGROUND PERSISTENCE SHIELD
          _buildBackgroundShieldCard(),
          const SizedBox(height: 14),

          // 4. LOCAL ADB CALL DROP ENGINE
          _buildAdbControlCard(),
          const SizedBox(height: 14),

          // 5. ANDROID SYSTEM PERMISSIONS MATRIX
          _buildPermissionsCard(),
          const SizedBox(height: 16),

          // 6. ENGINE ARCHITECTURE FOOTER
          _buildFooter(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 1. Network Mesh Diagnostics & IP Demystifier
  Widget _buildNetworkMeshCard(String cellularIp, String wifiIp) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFFE8F5E9),
                  child: Icon(Icons.hub_rounded, color: Colors.green, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Relay Mesh & Interface Architecture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Zero-typing pairing routes & gateway status', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.server.clientCount > 0
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.server.clientCount > 0 ? '${widget.server.clientCount} PAIRED' : 'STANDBY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: widget.server.clientCount > 0 ? Colors.green.shade800 : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Fixed Static Hotspot Row
            _buildNetInfoRow(
              label: 'Vivo Hotspot AP Gateway',
              value: '192.168.43.1 : 8080',
              badge: 'FIXED & PERMANENT',
              badgeColor: Colors.green,
              isImportant: true,
              subtitle: 'Never changes regardless of SIM restarts. Use this on iPhone.',
            ),
            const Divider(height: 20),

            // SIM Mobile Data WAN IP (Dynamic Carrier CGNAT)
            _buildNetInfoRow(
              label: 'SIM Cellular Data (Zong 4G)',
              value: cellularIp.isNotEmpty ? cellularIp : 'Active Mobile Data CGNAT',
              badge: 'OPERATOR WAN (IGNORED)',
              badgeColor: Colors.orange,
              isImportant: false,
              subtitle: 'Changes every session by carrier. Not needed by iPhone.',
            ),
            const Divider(height: 20),

            // Wi-Fi Client IP
            _buildNetInfoRow(
              label: 'Wi-Fi Client IP (Router)',
              value: wifiIp.isNotEmpty ? wifiIp : 'Not connected to Wi-Fi router',
              badge: wifiIp.isNotEmpty ? 'ROUTER LAN' : 'STANDBY',
              badgeColor: wifiIp.isNotEmpty ? Colors.blue : Colors.grey,
              isImportant: false,
              subtitle: wifiIp.isNotEmpty ? 'Active home/office network subnet' : 'Hotspot is primary connection',
            ),
            const Divider(height: 20),

            // UDP Signaling Port
            _buildNetInfoRow(
              label: 'UDP Burst Signaling Port',
              value: 'Port 8081',
              badge: 'ZERO-HANDSHAKE',
              badgeColor: Colors.teal,
              isImportant: false,
              subtitle: 'Bypasses dry cellular data during incoming GSM calls.',
            ),

            const SizedBox(height: 14),

            // Explanatory Tip Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withValues(alpha: 0.25), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_rounded, color: Colors.green, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Zero-Typing Hotspot Notice',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Vivo Hotspot is permanently anchored at 192.168.43.1. When SIM data toggles, Zong assigns a dynamic WAN IP (10.x.x.x), but iPhone never needs that IP. Simply tap Auto-Discover on iPhone or let it auto-lock.',
                          style: TextStyle(fontSize: 11, color: Colors.green.shade900),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Diagnostics & Simulation Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.radar_rounded, size: 16, color: Colors.teal),
                    label: const Text('Beacon Burst', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _broadcastBeacon,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.phone_in_talk_rounded, size: 16, color: Colors.green),
                    label: const Text('Test Call', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _showTestCallDialog,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.sms_rounded, size: 16, color: Colors.blue),
                    label: const Text('Test SMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _showTestSmsDialog,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 2. Hotspot & Tethering Control Card
  Widget _buildHotspotControlCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _isHotspotActive ? Colors.teal : Colors.grey.shade400,
                child: const Icon(Icons.wifi_tethering_rounded, color: Colors.white),
              ),
              title: const Text('Vivo Hotspot AP Manager', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                _isHotspotActive ? 'Active & Broadcasting (192.168.43.1)' : 'Inactive. Tap Settings to enable.',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await widget.telephonyController.openTetherSettings();
                  _checkSystemHealth();
                },
                child: const Text('Hotspot Settings'),
              ),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-Tether Prompt on Launch', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Prompts to enable Hotspot if inactive when opening app.', style: TextStyle(fontSize: 11, color: Colors.grey)),
              value: _autoTether,
              onChanged: _toggleAutoTether,
            ),
          ],
        ),
      ),
    );
  }

  /// 3. Vivo FuntouchOS Battery & Background Persistence Shield
  Widget _buildBackgroundShieldCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _isBatteryIgnored ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                  child: Icon(
                    _isBatteryIgnored ? Icons.shield_rounded : Icons.warning_amber_rounded,
                    color: _isBatteryIgnored ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FuntouchOS Battery & WakeLock Shield', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('Prevents Vivo from killing daemon when screen is locked', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Battery Optimization Bypass Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Battery Optimization Bypass', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(
                        _isBatteryIgnored
                            ? 'Whitelisted (Unrestricted background execution granted)'
                            : 'Restricted. Vivo may kill WebSocket server after screen sleep.',
                        style: TextStyle(fontSize: 11, color: _isBatteryIgnored ? Colors.green.shade800 : Colors.red.shade700),
                      ),
                    ],
                  ),
                ),
                if (!_isBatteryIgnored)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _requestBatteryOptimizationBypass,
                    child: const Text('Whitelist', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  )
                else
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
              ],
            ),
            const Divider(height: 24),

            // Auto-Start on Boot Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-Start on Boot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Starts relay engine silently in background when phone reboots.', style: TextStyle(fontSize: 11, color: Colors.grey)),
              value: _autoStartOnBoot,
              onChanged: _toggleAutoStart,
            ),
            const Divider(height: 16),

            // Foreground Service State Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Foreground Daemon Service', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Active with sticky notification & Wi-Fi Lock', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('RUNNING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 4. Local ADB Call Drop Engine
  Widget _buildAdbControlCard() {
    final isAdb = widget.telephonyController.isAdbConnected;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(
          backgroundColor: isAdb ? Colors.teal : Colors.blueGrey,
          child: const Icon(Icons.adb_rounded, color: Colors.white),
        ),
        title: const Text('Local ADB Call Drop Engine', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          isAdb ? 'Connected (localhost:5555) • Zero-latency call end' : 'Disconnected. Wireless Debugging standby.',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: FilledButton.tonal(
          onPressed: () async {
            HapticFeedback.lightImpact();
            final ok = await widget.telephonyController.checkAndConnectAdb();
            if (!mounted) return;
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok ? 'ADB Connected successfully on port 5555!' : 'Could not connect. Ensure Wireless Debugging is on port 5555.'),
                backgroundColor: ok ? Colors.green : Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: const Text('Reconnect'),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Text(
                  'Wireless ADB Setup Guide:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                const Text(
                  '1. Open Settings > Developer Options > Wireless Debugging.\n'
                  '2. Connect phone once to PC or run:\n'
                  '   adb tcpip 5555\n'
                  '3. This allows local programmatic call disconnection on newer Android versions.',
                  style: TextStyle(fontSize: 11, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copy adb tcpip 5555 command', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Clipboard.setData(const ClipboardData(text: 'adb tcpip 5555'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Command copied to clipboard!'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 5. Android System Permissions Matrix
  Widget _buildPermissionsCard() {
    final total = HostPermissionService.items.length;
    final granted = _permissionStatuses.values.where((s) => s.isGranted).length;
    final allOk = granted >= total && total > 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: allOk ? Colors.purple : Colors.deepOrange,
          child: Icon(allOk ? Icons.security_rounded : Icons.warning_amber_rounded, color: Colors.white),
        ),
        title: const Text('Android Permissions Health', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          allOk
              ? 'All $total permissions active • Phone, SMS & Audio fully operational'
              : '$granted of $total permissions granted • Tap to review permissions',
          style: TextStyle(fontSize: 12, color: allOk ? Colors.black54 : Colors.deepOrange.shade800),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: allOk ? Colors.green.withValues(alpha: 0.15) : Colors.deepOrange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            allOk ? 'OPTIMAL' : 'REVIEW',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: allOk ? Colors.green.shade800 : Colors.deepOrange.shade800,
            ),
          ),
        ),
        onTap: _requestPermissions,
      ),
    );
  }

  Widget _buildNetInfoRow({
    required String label,
    required String value,
    required String badge,
    required Color badgeColor,
    required bool isImportant,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                badge,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: isImportant ? Colors.green.shade800 : Colors.black87,
                ),
              ),
            ),
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                Clipboard.setData(ClipboardData(text: value.split(':').first.trim()));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied "$value" to clipboard'),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildFooter() {
    return const Column(
      children: [
        Icon(Icons.phonelink_setup_rounded, color: Colors.grey, size: 28),
        SizedBox(height: 6),
        Text(
          'PTA Native Host Companion • Vivo S1 Engine',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
        ),
        SizedBox(height: 2),
        Text(
          'v1.4.0 (Build 27) • Zero-Typing Hotspot & Telephony Mesh Server',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
