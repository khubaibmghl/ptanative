import 'package:flutter/material.dart';
import 'services/telephony_controller.dart';
import 'services/relay_server.dart';
import 'services/telephony_monitor.dart';
import 'services/telemetry_service.dart';
import 'services/android_content_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/live_activity_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final telephonyController = TelephonyController();
  final server = RelayServer(telephonyController: telephonyController);
  final monitor = TelephonyMonitor(server: server);
  final telemetry = TelemetryService(server: server);
  final contentService = AndroidContentService(server: server);
  server.contentService = contentService;

  // Auto-connect local ADB on startup
  telephonyController.checkAndConnectAdb();

  // Sync native contacts & call history from Vivo S1 ContentResolver
  contentService.syncAllFromDevice();

  runApp(PtaHostApp(
    server: server,
    monitor: monitor,
    telemetry: telemetry,
    telephonyController: telephonyController,
  ));
}

class PtaHostApp extends StatelessWidget {
  final RelayServer server;
  final TelephonyMonitor monitor;
  final TelemetryService telemetry;
  final TelephonyController telephonyController;

  const PtaHostApp({
    super.key,
    required this.server,
    required this.monitor,
    required this.telemetry,
    required this.telephonyController,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PTA Host',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32), // Forest Green
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 1,
        ),
      ),
      home: HostMainNavigation(
        server: server,
        monitor: monitor,
        telemetry: telemetry,
        telephonyController: telephonyController,
      ),
    );
  }
}

class HostMainNavigation extends StatefulWidget {
  final RelayServer server;
  final TelephonyMonitor monitor;
  final TelemetryService telemetry;
  final TelephonyController telephonyController;

  const HostMainNavigation({
    super.key,
    required this.server,
    required this.monitor,
    required this.telemetry,
    required this.telephonyController,
  });

  @override
  State<HostMainNavigation> createState() => _HostMainNavigationState();
}

class _HostMainNavigationState extends State<HostMainNavigation> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        server: widget.server,
        monitor: widget.monitor,
        telemetry: widget.telemetry,
      ),
      LiveActivityScreen(
        server: widget.server,
      ),
      SettingsScreen(
        server: widget.server,
        telephonyController: widget.telephonyController,
      ),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
