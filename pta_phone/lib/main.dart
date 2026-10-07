import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:pta_shared/pta_shared.dart';
import 'services/callkit_service.dart';
import 'services/relay_client.dart';
import 'theme/liquid_glass_theme.dart';
import 'screens/keypad_screen.dart';
import 'screens/recents_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/in_call_screen.dart';

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

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _setupCallKitListener();
    _checkInitialCallIntent();
    _setupNativeIntentChannel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      RelayClient.instance.onAppResumed();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      RelayClient.instance.onAppPaused();
    }
  }

  void _setupNativeIntentChannel() {
    const MethodChannel('com.pta.phone/native_intents').setMethodCallHandler((call) async {
      if (call.method == 'onNativeDialIntent') {
        final number = call.arguments['number']?.toString() ?? '';
        if (number.isNotEmpty) {
          RelayClient.instance.dialNumber(number);
        }
      }
    });
  }

  Future<void> _checkInitialCallIntent() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls is List && calls.isNotEmpty) {
        for (final call in calls) {
          if (call is Map) {
            final bodyMap = Map<String, dynamic>.from(call);
            final number = bodyMap['handle']?.toString() ??
                           bodyMap['number']?.toString() ??
                           bodyMap['extra']?['number']?.toString() ?? '';
            if (number.isNotEmpty) {
              RelayClient.instance.dialNumber(number);
              break;
            }
          }
        }
      }
    } catch (_) {}
  }

  void _setupCallKitListener() {
    CallKitService.instance.onEvent?.listen((event) {
      if (event == null) return;
      switch (event.event) {
        case Event.actionCallStart:
          String number = '';
          if (event.body is Map) {
            final bodyMap = Map<String, dynamic>.from(event.body as Map);
            number = bodyMap['handle']?.toString() ??
                     bodyMap['number']?.toString() ??
                     bodyMap['extra']?['number']?.toString() ?? '';
          }
          if (number.isNotEmpty) {
            RelayClient.instance.dialNumber(number);
          }
          break;
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
                _buildMinimalHeaderDot(),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
          ),

          // Floating iOS Glass Dock Bar (Centered)
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: _buildLiquidGlassDock(),
          ),

          // Full-Screen Native InCallScreen Modal Overlay when Active Call is Present
          StreamBuilder<ActiveCallInfo?>(
            stream: RelayClient.instance.activeCallStream,
            initialData: RelayClient.instance.currentActiveCall,
            builder: (context, snapshot) {
              final activeCall = snapshot.data;
              if (activeCall == null) return const SizedBox.shrink();

              return Positioned.fill(
                child: InCallScreen(callInfo: activeCall),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalHeaderDot() {
    return StreamBuilder<DeviceStatusModel>(
      stream: RelayClient.instance.statusStream,
      initialData: RelayClient.instance.lastStatus,
      builder: (context, snapshot) {
        final isConnected = RelayClient.instance.isConnected;

        return Padding(
          padding: const EdgeInsets.only(top: LiquidGlassTheme.dynamicIslandTopInset + 4, right: 18, bottom: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                final status = snapshot.data;
                showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xF0121218),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (ctx) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Host Device Status', style: TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text('Connection: ${isConnected ? "Connected to Host" : "Disconnected"}', style: const TextStyle(color: Colors.white70)),
                        Text('Host IP: ${RelayClient.instance.hostIp}', style: const TextStyle(color: Colors.white70)),
                        Text('Vivo Battery: ${status != null ? "${status.batteryLevel}% ${status.isCharging ? '(Charging)' : ''}" : "Unknown"}', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                );
              },
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isConnected ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.crimsonRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isConnected ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.crimsonRed).withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
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
