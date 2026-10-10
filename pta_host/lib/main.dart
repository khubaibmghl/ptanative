import 'package:flutter/material.dart';
import 'services/telephony_controller.dart';
import 'services/relay_server.dart';
import 'services/telephony_monitor.dart';
import 'services/telemetry_service.dart';
import 'services/android_content_service.dart';
import 'services/host_permission_service.dart';
import 'services/hotspot_service.dart';
import 'widgets/host_permission_sheet.dart';
import 'screens/dashboard_screen.dart';
import 'screens/live_activity_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final telephonyController = TelephonyController();
  final server = RelayServer(telephonyController: telephonyController);
  final monitor = TelephonyMonitor(server: server);
  server.telephonyMonitor = monitor;
  final telemetry = TelemetryService(server: server);
  final contentService = AndroidContentService(server: server);
  server.contentService = contentService;

  // Auto-connect local ADB on startup
  telephonyController.checkAndConnectAdb();

  // Initialize Hotspot Engine
  final hotspotService = HotspotService(
    telephonyController: telephonyController,
    server: server,
  );
  hotspotService.init();

  // If essential permissions are already granted, pre-sync ContentResolver
  HostPermissionService.areEssentialPermissionsGranted().then((granted) {
    if (granted) {
      contentService.syncAllFromDevice();
    }
  });

  runApp(PtaHostApp(
    server: server,
    monitor: monitor,
    telemetry: telemetry,
    telephonyController: telephonyController,
    hotspotService: hotspotService,
  ));
}

class PtaHostApp extends StatelessWidget {
  final RelayServer server;
  final TelephonyMonitor monitor;
  final TelemetryService telemetry;
  final TelephonyController telephonyController;
  final HotspotService hotspotService;

  const PtaHostApp({
    super.key,
    required this.server,
    required this.monitor,
    required this.telemetry,
    required this.telephonyController,
    required this.hotspotService,
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
        hotspotService: hotspotService,
      ),
    );
  }
}

class HostMainNavigation extends StatefulWidget {
  final RelayServer server;
  final TelephonyMonitor monitor;
  final TelemetryService telemetry;
  final TelephonyController telephonyController;
  final HotspotService hotspotService;

  const HostMainNavigation({
    super.key,
    required this.server,
    required this.monitor,
    required this.telemetry,
    required this.telephonyController,
    required this.hotspotService,
  });

  @override
  State<HostMainNavigation> createState() => _HostMainNavigationState();
}

class _HostMainNavigationState extends State<HostMainNavigation> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkStartupPermissions();
    });
  }

  Future<void> _checkStartupPermissions() async {
    final allGranted = await HostPermissionService.areEssentialPermissionsGranted();
    if (!allGranted && mounted) {
      await HostPermissionSheet.show(
        context,
        onGranted: () {
          widget.server.contentService?.syncAllFromDevice();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        server: widget.server,
        monitor: widget.monitor,
        telemetry: widget.telemetry,
        hotspotService: widget.hotspotService,
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
