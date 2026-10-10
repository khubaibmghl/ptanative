import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:pta_shared/pta_shared.dart';
import 'services/callkit_service.dart';
import 'services/relay_client.dart';
import 'services/phone_permission_service.dart';
import 'widgets/phone_permission_sheet.dart';
import 'theme/liquid_glass_theme.dart';
import 'screens/keypad_screen.dart';
import 'screens/recents_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/in_call_screen.dart';
import 'screens/messages_screen.dart';
import 'dart:async';

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
  StreamSubscription<SmsMessageModel>? _smsSub;
  StreamSubscription<CallLogModel>? _missedCallSub;
  StreamSubscription<DeviceStatusModel>? _statusSub;
  bool _warnedLowBattery = false;
  bool _isCallMinimized = false;

  final List<Widget> _screens = const [
    RecentsScreen(),
    ContactsScreen(),
    KeypadScreen(),
    MessagesScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCallKitListener();
    _checkInitialCallIntent();
    _setupNativeIntentChannel();
    _setupSmsListener();
    _setupMissedCallListener();
    _setupStatusListener();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkStartupPermissions();
    });
  }

  Future<void> _checkStartupPermissions() async {
    final allGranted = await PhonePermissionService.arePermissionsGranted();
    if (!allGranted && mounted) {
      await PhonePermissionSheet.show(context);
    }
  }

  void _setupSmsListener() {
    _smsSub = RelayClient.instance.smsStream.listen((sms) {
      if (sms.extractedOtp != null && sms.extractedOtp!.isNotEmpty && mounted) {
        // Auto-copy OTP to clipboard with haptic feedback
        Clipboard.setData(ClipboardData(text: sms.extractedOtp!));
        HapticFeedback.heavyImpact();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: LiquidGlassTheme.surfaceDark,
            duration: const Duration(seconds: 8),
            content: Row(
              children: [
                const Icon(Icons.shield_outlined, color: LiquidGlassTheme.goldOtp),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🔐 OTP Auto-Copied from ${sms.sender}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                      Text(sms.extractedOtp!, style: const TextStyle(color: LiquidGlassTheme.goldOtp, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: LiquidGlassTheme.goldOtp),
                  ),
                  child: const Text('COPIED', style: TextStyle(color: LiquidGlassTheme.goldOtp, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  void _setupMissedCallListener() {
    _missedCallSub = RelayClient.instance.missedCallStream.listen((log) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF2C1618),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: LiquidGlassTheme.crimsonRed, width: 1),
            ),
            duration: const Duration(seconds: 10),
            content: Row(
              children: [
                const Icon(Icons.phone_missed_rounded, color: LiquidGlassTheme.crimsonRed),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Missed Call: ${log.callerName.isNotEmpty ? log.callerName : log.remoteNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        log.durationSeconds > 0
                            ? '${PhoneNumberNormalizer.formatForDisplay(log.remoteNumber)} • Rang for ${log.durationSeconds}s'
                            : PhoneNumberNormalizer.formatForDisplay(log.remoteNumber),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LiquidGlassTheme.gsmGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.call, size: 14),
                  label: const Text('Call Back', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    RelayClient.instance.dialNumber(log.remoteNumber);
                  },
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  void _setupStatusListener() {
    _statusSub = RelayClient.instance.statusStream.listen((status) {
      if (status.batteryLevel <= 20 && !status.isCharging && !_warnedLowBattery && mounted) {
        _warnedLowBattery = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.amber.shade900,
            duration: const Duration(seconds: 8),
            content: Row(
              children: [
                const Icon(Icons.battery_alert, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '⚠️ Vivo Host Battery Low (${status.batteryLevel}%). Connect charger to prevent disconnection.',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (status.batteryLevel > 25 || status.isCharging) {
        _warnedLowBattery = false;
      }
    });
  }

  @override
  void dispose() {
    _smsSub?.cancel();
    _missedCallSub?.cancel();
    _statusSub?.cancel();
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

  void _setupNativeIntentChannel() async {
    const channel = MethodChannel('com.pta.phone/native_intents');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onNativeDialIntent') {
        final number = call.arguments['number']?.toString() ?? '';
        if (number.isNotEmpty) {
          RelayClient.instance.dialNumber(number);
        }
      }
    });

    try {
      final pending = await channel.invokeMethod<String>('getPendingDialIntent');
      if (pending != null && pending.isNotEmpty) {
        RelayClient.instance.dialNumber(pending);
      }
    } catch (_) {}
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

          // In-Call Overlay: Full-Screen iOS 17/18 InCallScreen OR Minimized Dynamic Island Pill
          StreamBuilder<ActiveCallInfo?>(
            stream: RelayClient.instance.activeCallStream,
            initialData: RelayClient.instance.currentActiveCall,
            builder: (context, snapshot) {
              final activeCall = snapshot.data;
              if (activeCall == null) {
                if (_isCallMinimized) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _isCallMinimized = false);
                  });
                }
                return const SizedBox.shrink();
              }

              if (_isCallMinimized) {
                return Positioned(
                  top: MediaQuery.of(context).padding.top + 6,
                  left: 16,
                  right: 16,
                  child: _buildDynamicIslandCallPill(activeCall),
                );
              }

              return Positioned.fill(
                child: InCallScreen(
                  callInfo: activeCall,
                  onMinimize: () => setState(() => _isCallMinimized = true),
                  onOpenContacts: () {
                    setState(() {
                      _isCallMinimized = true;
                      _currentIndex = 1;
                    });
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Sleek iOS Dynamic Island In-Call Capsule Pill when call is minimized
  Widget _buildDynamicIslandCallPill(ActiveCallInfo callInfo) {
    final title = callInfo.callerName.isNotEmpty ? callInfo.callerName : callInfo.number;
    final dur = callInfo.durationSeconds;
    final m = (dur ~/ 60).toString().padLeft(2, '0');
    final s = (dur % 60).toString().padLeft(2, '0');
    final timeStr = callInfo.state == PhoneCallState.connected
        ? '$m:$s'
        : (callInfo.state == PhoneCallState.ringing ? 'Ringing' : 'Calling');

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _isCallMinimized = false);
      },
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Glowing green phone receiver dot
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: Color(0xFF30D158), // Apple System Green
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phone_in_talk, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: Color(0xFF30D158),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Tap to expand indicator
            const Icon(
              Icons.unfold_more_rounded,
              color: Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 8),
            // Quick End Call Red Button
            GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                RelayClient.instance.hangupCall();
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimalHeaderDot() {
    return StreamBuilder<bool>(
      stream: RelayClient.instance.connectionStream,
      initialData: RelayClient.instance.isConnected,
      builder: (context, connSnapshot) {
        final isConnected = connSnapshot.data ?? RelayClient.instance.isConnected;

        return StreamBuilder<DeviceStatusModel>(
          stream: RelayClient.instance.statusStream,
          initialData: RelayClient.instance.lastStatus,
          builder: (context, statusSnapshot) {
            final status = statusSnapshot.data;

            return Padding(
              padding: const EdgeInsets.only(top: LiquidGlassTheme.dynamicIslandTopInset + 4, right: 18, bottom: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => _showQuickSwitcherSheet(context, isConnected, status),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.15)
                          : LiquidGlassTheme.crimsonRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isConnected
                            ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.4)
                            : LiquidGlassTheme.crimsonRed.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isConnected ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.crimsonRed,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (isConnected ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.crimsonRed).withValues(alpha: 0.6),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? RelayClient.instance.hostIp : 'Offline',
                          style: TextStyle(
                            color: isConnected ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.crimsonRed,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showQuickSwitcherSheet(BuildContext context, bool isConnected, DeviceStatusModel? status) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xF2161622),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final connections = RelayClient.instance.savedConnections;
            final activeIp = RelayClient.instance.hostIp;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.flash_on_rounded, color: LiquidGlassTheme.iosBlue, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Quick Switch Host Connection',
                          style: TextStyle(
                            color: LiquidGlassTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap any connection to switch instantaneously (<200ms)',
                      style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ...connections.map((conn) {
                      final isActive = activeIp == conn.ip;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? (isConnected ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15))
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive
                                ? (isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange)
                                : Colors.white12,
                            width: isActive ? 1.2 : 0.8,
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            conn.isDefaultHotspot ? Icons.wifi_tethering_rounded : Icons.wifi_rounded,
                            color: isActive
                                ? (isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange)
                                : Colors.white70,
                          ),
                          title: Row(
                            children: [
                              Text(
                                conn.name,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              if (isActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange).withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isConnected ? 'CONNECTED' : 'CONNECTING',
                                    style: TextStyle(
                                      color: isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${conn.ip}:${conn.port}${conn.isDefaultHotspot ? " • Dry Hotspot Default" : ""}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          trailing: isActive
                              ? Icon(Icons.check_circle_rounded, color: isConnected ? LiquidGlassTheme.gsmGreen : Colors.orange)
                              : ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: LiquidGlassTheme.iosBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () async {
                                    HapticFeedback.mediumImpact();
                                    await RelayClient.instance.switchToConnection(conn);
                                    if (ctx.mounted) {
                                      setSheetState(() {});
                                      Navigator.pop(ctx);
                                    }
                                    if (mounted) setState(() {});
                                  },
                                  child: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                          onTap: () async {
                            HapticFeedback.mediumImpact();
                            await RelayClient.instance.switchToConnection(conn);
                            if (ctx.mounted) {
                              setSheetState(() {});
                              Navigator.pop(ctx);
                            }
                            if (mounted) setState(() {});
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.radar, size: 18, color: Colors.white),
                            label: const Text('Auto-Discover', style: TextStyle(color: Colors.white, fontSize: 13)),
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              Navigator.pop(ctx);
                              final ip = await RelayClient.instance.discoverHostIp();
                              if (ip != null && ip.isNotEmpty) {
                                RelayClient.instance.connect();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.settings, size: 18),
                            label: const Text('All Settings', style: TextStyle(fontSize: 13)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() => _currentIndex = 4);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
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
          padding: const EdgeInsets.symmetric(horizontal: 4),
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
                icon: Icons.shield_outlined,
                label: 'SMS / OTP',
                index: 3,
              ),
              _buildDockItem(
                icon: Icons.settings,
                label: 'Settings',
                index: 4,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
