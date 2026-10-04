import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:pta_shared/pta_shared.dart';
import 'services/callkit_service.dart';
import 'services/relay_client.dart';
import 'theme/liquid_glass_theme.dart';
import 'widgets/active_call_bar.dart';
import 'screens/keypad_screen.dart';
import 'screens/recents_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/dtmf_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  await RelayClient.instance.init();

  runApp(const PtaPhoneApp());
}

class PtaPhoneApp extends StatelessWidget {
  const PtaPhoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PTA Phone',
      debugShowCheckedModeBanner: false,
      theme: LiquidGlassTheme.themeData,
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    KeypadScreen(),
    RecentsScreen(),
    ContactsScreen(),
    MessagesScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _setupCallKitListener();
  }

  void _setupCallKitListener() {
    CallKitService.instance.onEvent?.listen((event) {
      if (event == null) return;
      switch (event.event) {
        case Event.actionCallAccept:
          RelayClient.instance.answerCall();
          break;
        case Event.actionCallDecline:
        case Event.actionCallEnded:
        case Event.actionCallTimeout:
          RelayClient.instance.hangupCall();
          break;
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LiquidGlassTheme.bgDark,
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.06),
              ),
            ),
          ),

          SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                _buildDynamicIslandCapsule(),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
          ),

          // Live Active Call Floating Bar
          StreamBuilder<ActiveCallInfo?>(
            stream: RelayClient.instance.activeCallStream,
            initialData: RelayClient.instance.currentActiveCall,
            builder: (context, snapshot) {
              final activeCall = snapshot.data;
              if (activeCall == null) return const SizedBox.shrink();

              return Positioned(
                top: LiquidGlassTheme.dynamicIslandTopInset + 44,
                left: 16,
                right: 16,
                child: ActiveCallBar(
                  callInfo: activeCall,
                  onOpenDtmf: () => showDtmfKeypadSheet(context),
                ),
              );
            },
          ),

          // Floating Liquid Glass Dock
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: _buildLiquidGlassDock(),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicIslandCapsule() {
    return StreamBuilder<DeviceStatusModel>(
      stream: RelayClient.instance.statusStream,
      initialData: RelayClient.instance.lastStatus,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final isConnected = RelayClient.instance.isConnected;

        return Padding(
          padding: const EdgeInsets.only(top: LiquidGlassTheme.dynamicIslandTopInset, left: 20, right: 20, bottom: 8),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: LiquidGlassTheme.dynamicPill,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white12, width: 0.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isConnected ? 'Vivo S1 • ${RelayClient.instance.hostIp}' : 'Reconnecting...',
                      style: const TextStyle(
                        color: LiquidGlassTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      status != null ? '${status.batteryLevel}%' : '85%',
                      style: const TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      status != null && status.isCharging ? Icons.battery_charging_full : Icons.battery_full,
                      color: LiquidGlassTheme.gsmGreen,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Zong 4G',
                      style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiquidGlassDock() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.glassBlurSigma,
          sigmaY: LiquidGlassTheme.glassBlurSigma,
        ),
        child: Container(
          height: LiquidGlassTheme.dockHeight,
          decoration: BoxDecoration(
            color: const Color(0x351C1C26),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: const Color(0x35FFFFFF),
              width: 0.75,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildDockItem(icon: Icons.dialpad, label: 'Keypad', index: 0),
              _buildDockItem(icon: Icons.access_time, label: 'Recents', index: 1),
              _buildDockItem(icon: Icons.contacts, label: 'Contacts', index: 2),
              _buildDockItem(icon: Icons.mark_email_unread_outlined, label: 'Messages', index: 3),
              _buildDockItem(icon: Icons.settings, label: 'Settings', index: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDockItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? LiquidGlassTheme.accentBlue : LiquidGlassTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? LiquidGlassTheme.accentBlue : LiquidGlassTheme.textSecondary,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
