import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/relay_server.dart';
import '../services/telephony_controller.dart';

class SettingsScreen extends StatefulWidget {
  final RelayServer server;
  final TelephonyController telephonyController;

  const SettingsScreen({
    super.key,
    required this.server,
    required this.telephonyController,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoStartOnBoot = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoStartOnBoot = prefs.getBool('auto_start_on_boot') ?? true;
    });
  }

  Future<void> _toggleAutoStart(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_start_on_boot', val);
    setState(() => _autoStartOnBoot = val);
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.phone,
      Permission.contacts,
      Permission.sms,
      Permission.ignoreBatteryOptimizations,
    ].request();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Permissions evaluated. Check Android Settings for details.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Tools', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. HARDWARE ADB
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.teal,
                child: Icon(Icons.adb, color: Colors.white),
              ),
              title: const Text('Local ADB Call Drop', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                widget.telephonyController.isAdbConnected
                    ? 'Connected (localhost:5555)'
                    : 'Disconnected. Tap Reconnect to pair.',
              ),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  final ok = await widget.telephonyController.checkAndConnectAdb();
                  if (!context.mounted) return;
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'ADB Connected successfully!' : 'Could not connect. Ensure Wireless Debugging is on port 5555.'),
                      backgroundColor: ok ? Colors.green : Colors.red,
                    ),
                  );
                },
                child: const Text('Reconnect'),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 2. AUTO-START TOGGLE
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.indigo,
                child: Icon(Icons.flash_on, color: Colors.white),
              ),
              title: const Text('Auto-Start on Boot', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Starts relay engine silently when phone reboots.'),
              trailing: Switch(
                value: _autoStartOnBoot,
                onChanged: _toggleAutoStart,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 3. ANDROID PERMISSIONS
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.purple,
                child: Icon(Icons.security, color: Colors.white),
              ),
              title: const Text('Android Permissions Wizard', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Grant Phone, Contacts, SMS & Battery bypass.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _requestPermissions,
            ),
          ),
        ],
      ),
    );
  }
}
