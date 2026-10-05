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
  int _currentIndex = 2; // Keypad active by default

  final List<Widget> _screens = const [
    RecentsScreen(),
    ContactsScreen(),
    KeypadScreen(),
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
    final isDark = LiquidGlassTheme.isDarkMode;

    return Scaffold(
      backgroundColor: LiquidGlassTheme.bg,
      body: Stack(
        children: [
          // Background subtle ambient radial glow
          if (isDark) ...[
            Positioned(
              top: -120,
              right: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.12),
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
                  color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.08),
                ),
              ),
            ),
          ],

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

          // Floating iOS 26/27 Liquid Glass Dock Bar & Search Button
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Row(
              children: [
                Expanded(
                  child: _buildLiquidGlassDock(),
                ),
                const SizedBox(width: 10),
                _buildFloatingSearchButton(),
              ],
            ),
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
        final isDark = LiquidGlassTheme.isDarkMode;

        return Padding(
          padding: const EdgeInsets.only(top: LiquidGlassTheme.dynamicIslandTopInset, left: 20, right: 20, bottom: 8),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16161E) : const Color(0xFFEBEBF0),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
                width: 0.5,
              ),
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
                        color: isConnected
                            ? (RelayClient.instance.isConnectedViaCloud ? LiquidGlassTheme.iosBlue : LiquidGlassTheme.gsmGreen)
                            : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isConnected
                          ? (RelayClient.instance.isConnectedViaCloud
                              ? 'Vivo S1 • Remote Cloud'
                              : 'Vivo S1 • ${RelayClient.instance.hostIp}')
                          : 'Auto-Discovering...',
                      style: TextStyle(
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
                      style: TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      status != null && status.isCharging ? Icons.battery_charging_full : Icons.battery_full,
                      color: LiquidGlassTheme.gsmGreen,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Text(
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
    final isDark = LiquidGlassTheme.isDarkMode;

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.glassBlurSigma,
          sigmaY: LiquidGlassTheme.glassBlurSigma,
        ),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x351C1C26) : const Color(0xEBFAFBFE),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isDark ? const Color(0x35FFFFFF) : const Color(0x1F000000),
              width: 0.5,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildDockItem(
                icon: Icons.access_time_filled,
                label: 'Calls',
                index: 0,
                badgeCount: 1,
              ),
              _buildDockItem(
                icon: Icons.person,
                label: 'Contacts',
                index: 1,
              ),
              _buildDockItem(
                icon: Icons.grid_view_rounded,
                label: 'Keypad',
                index: 2,
              ),
              _buildDockItem(
                icon: Icons.settings,
                label: 'Settings',
                index: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingSearchButton() {
    final isDark = LiquidGlassTheme.isDarkMode;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _currentIndex = 1; // Open Contacts/Search
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: LiquidGlassTheme.glassBlurSigma,
            sigmaY: LiquidGlassTheme.glassBlurSigma,
          ),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? const Color(0x351C1C26) : const Color(0xEBFAFBFE),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? const Color(0x35FFFFFF) : const Color(0x1F000000),
                width: 0.5,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Icon(
              Icons.search,
              color: isDark ? Colors.white : Colors.black,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockItem({
    required IconData icon,
    required String label,
    required int index,
    int badgeCount = 0,
  }) {
    final isSelected = _currentIndex == index;
    final isDark = LiquidGlassTheme.isDarkMode;

    final activeColor = LiquidGlassTheme.iosBlue;
    final inactiveColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? const Color(0x28007AFF) : const Color(0xFFE5E5EA)) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? activeColor : inactiveColor,
                  size: 22,
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: LiquidGlassTheme.crimsonRed,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
