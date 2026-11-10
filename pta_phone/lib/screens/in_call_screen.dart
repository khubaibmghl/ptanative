import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/relay_client.dart';
import '../data/database_helper.dart';
import '../theme/liquid_glass_theme.dart';
import '../widgets/contact_avatar_widget.dart';
import 'dtmf_sheet.dart';

/// Pixel-Perfect iOS 17 / iOS 27 Liquid Glass In-Call Screen
/// Features live audio route control (Speaker, Earpiece, Bluetooth),
/// DTMF tone dialing over dry Hotspot Wi-Fi, and frosted glass circular controls.
class InCallScreen extends StatefulWidget {
  final ActiveCallInfo callInfo;
  final VoidCallback? onMinimize;
  final VoidCallback? onOpenContacts;

  const InCallScreen({
    super.key,
    required this.callInfo,
    this.onMinimize,
    this.onOpenContacts,
  });

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  Timer? _timer;
  int _elapsedSeconds = 0;
  int? _localCallStartTimeMs;
  bool _isMuted = false;
  String? _contactId;

  StreamSubscription? _audioRouteSub;
  HostAudioRouteState _audioRoute = RelayClient.instance.currentAudioRoute;

  @override
  void initState() {
    super.initState();
    _initCallTimer();
    _lookupContact();

    // Listen to real-time audio route state changes from Vivo S1 host
    _audioRouteSub = RelayClient.instance.audioRouteStream.listen((state) {
      if (mounted) {
        setState(() {
          _audioRoute = state;
        });
      }
    });
    RelayClient.instance.fetchHostAudioRoute();
  }

  Future<void> _lookupContact() async {
    final contact = await DatabaseHelper.instance.findContactByNumber(widget.callInfo.number);
    if (mounted && contact != null) {
      setState(() {
        _contactId = contact.id;
      });
    }
  }

  @override
  void didUpdateWidget(covariant InCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.callInfo.state != oldWidget.callInfo.state) {
      RelayClient.instance.logDiagnostic(
        '📞 [IN-CALL-STATE-CHANGE] didUpdateWidget state changed: ${oldWidget.callInfo.state} -> ${widget.callInfo.state}',
      );
      _initCallTimer();
    } else if (widget.callInfo.state == PhoneCallState.connected && widget.callInfo.durationSeconds > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final drift = (widget.callInfo.durationSeconds - _elapsedSeconds).abs();
      if (drift >= 2) {
        RelayClient.instance.logDiagnostic(
          '⚠️ [IN-CALL-DRIFT-RESYNC] Timer drift >= 2s detected! HostDur: ${widget.callInfo.durationSeconds}s, LocalElapsed: $_elapsedSeconds, drift: ${drift}s. Resyncing local anchor.',
        );
        _localCallStartTimeMs = now - (widget.callInfo.durationSeconds * 1000);
        setState(() {
          _elapsedSeconds = widget.callInfo.durationSeconds;
        });
      }
    }
  }

  void _initCallTimer() {
    _timer?.cancel();
    if (widget.callInfo.state == PhoneCallState.connected) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (widget.callInfo.durationSeconds > 0) {
        _localCallStartTimeMs = now - (widget.callInfo.durationSeconds * 1000);
        _elapsedSeconds = widget.callInfo.durationSeconds;
      } else if (widget.callInfo.startTime > 0 && widget.callInfo.startTime <= now) {
        _localCallStartTimeMs = widget.callInfo.startTime;
        _elapsedSeconds = (now - _localCallStartTimeMs!) ~/ 1000;
      } else {
        _localCallStartTimeMs = now;
        _elapsedSeconds = 0;
      }

      int lastTickMs = DateTime.now().millisecondsSinceEpoch;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          final curNow = DateTime.now().millisecondsSinceEpoch;
          lastTickMs = curNow;

          final sec = _localCallStartTimeMs != null
              ? ((curNow - _localCallStartTimeMs!) ~/ 1000)
              : (_elapsedSeconds + 1);

          setState(() {
            _elapsedSeconds = sec >= 0 ? sec : 0;
          });
        }
      });
    } else if (widget.callInfo.state == PhoneCallState.disconnected) {
      _timer?.cancel();
      if (widget.callInfo.durationSeconds > 0) {
        _elapsedSeconds = widget.callInfo.durationSeconds;
      }
    } else {
      _timer?.cancel();
      _localCallStartTimeMs = null;
      _elapsedSeconds = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioRouteSub?.cancel();
    super.dispose();
  }

  String get _formattedDuration {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _statusSubtitle {
    switch (widget.callInfo.state) {
      case PhoneCallState.dialing:
        final rawLabel = widget.callInfo.label?.trim().toLowerCase();
        if (rawLabel != null && rawLabel.isNotEmpty) {
          return 'calling $rawLabel...';
        }
        return 'calling mobile...';
      case PhoneCallState.ringing:
        return 'ringing...';
      case PhoneCallState.connected:
        return _formattedDuration;
      case PhoneCallState.disconnected:
        return 'call ended';
    }
  }

  IconData get _audioIcon {
    if (_audioRoute.currentRoute == 'BLUETOOTH') return Icons.bluetooth_audio_rounded;
    if (_audioRoute.currentRoute == 'SPEAKER') return Icons.volume_up_rounded;
    return Icons.volume_down_rounded;
  }

  String get _audioLabel {
    if (_audioRoute.currentRoute == 'BLUETOOTH') return 'bluetooth';
    if (_audioRoute.currentRoute == 'SPEAKER') return 'speaker';
    return 'audio';
  }

  bool get _isAudioActive => _audioRoute.currentRoute != 'EARPIECE';

  void _onAudioPressed() {
    HapticFeedback.selectionClick();
    if (_audioRoute.bluetoothConnected) {
      _showAudioRouteSheet(context);
    } else {
      final next = _audioRoute.currentRoute == 'SPEAKER' ? 'EARPIECE' : 'SPEAKER';
      RelayClient.instance.setHostAudioRoute(next);
    }
  }

  void _showAudioRouteSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              decoration: BoxDecoration(
                color: const Color(0xF0181726),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Audio Source',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Option 1: Vivo S1 (Internal Earpiece)
                  _buildAudioRouteTile(
                    ctx: ctx,
                    routeKey: 'EARPIECE',
                    title: 'Vivo S1 (Handset)',
                    subtitle: 'Cellular earpiece receiver',
                    icon: Icons.phone_iphone_rounded,
                    isSelected: _audioRoute.currentRoute == 'EARPIECE',
                  ),
                  const Divider(height: 1, color: Colors.white12),

                  // Option 2: Speaker
                  _buildAudioRouteTile(
                    ctx: ctx,
                    routeKey: 'SPEAKER',
                    title: 'Speaker',
                    subtitle: 'Hands-free speakerphone',
                    icon: Icons.volume_up_rounded,
                    isSelected: _audioRoute.currentRoute == 'SPEAKER',
                  ),

                  // Option 3: Bluetooth (if connected)
                  if (_audioRoute.bluetoothConnected) ...[
                    const Divider(height: 1, color: Colors.white12),
                    _buildAudioRouteTile(
                      ctx: ctx,
                      routeKey: 'BLUETOOTH',
                      title: _audioRoute.bluetoothName.isNotEmpty
                          ? _audioRoute.bluetoothName
                          : 'Bluetooth Headset',
                      subtitle: 'Connected wireless audio',
                      icon: Icons.bluetooth_audio_rounded,
                      isSelected: _audioRoute.currentRoute == 'BLUETOOTH',
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAudioRouteTile({
    required BuildContext ctx,
    required String routeKey,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(ctx);
        RelayClient.instance.setHostAudioRoute(routeKey);
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? LiquidGlassTheme.iosBlue : Colors.white70,
              size: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? LiquidGlassTheme.iosBlue : Colors.white,
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                color: LiquidGlassTheme.iosBlue,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.callInfo.callerName.isNotEmpty
        ? widget.callInfo.callerName
        : widget.callInfo.number;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 250) {
          widget.onMinimize?.call();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1E2130), // Subtle contact poster ambient glow
                Color(0xFF0F1017),
                Color(0xFF000000),
                Color(0xFF000000),
              ],
              stops: [0.0, 0.35, 0.7, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Top Navigation Bar with Apple "hide" chevron
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (widget.onMinimize != null)
                        GestureDetector(
                          onTap: widget.onMinimize,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'hide',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 48),

                      // Carrier / Route indicator pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12, width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _audioIcon,
                              color: _isAudioActive ? LiquidGlassTheme.iosBlue : Colors.white60,
                              size: 13,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _audioRoute.currentRoute == 'BLUETOOTH'
                                  ? (_audioRoute.bluetoothName.isNotEmpty ? _audioRoute.bluetoothName : 'Bluetooth')
                                  : (_audioRoute.currentRoute == 'SPEAKER' ? 'Speaker' : 'PTA Cellular'),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // Apple Contact Poster Avatar Streamed from Vivo S1
                ContactAvatarWidget(
                  contactId: _contactId,
                  displayName: displayName,
                  size: 108,
                  fontSize: 44,
                  backgroundColor: const Color(0xFF2B2E3E),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 2,
                  ),
                ),
                const SizedBox(height: 20),

                // Contact Display Name (Apple Typography)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),

                // Status Subtitle / Live Duration (Apple format)
                Text(
                  _statusSubtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),

                const Spacer(flex: 2),

                // --- Modern iOS Lower 6-Button Control Cluster ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Row 1: [ audio ]  [ FaceTime ]  [ mute ]
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildInCallGlassButton(
                            icon: _audioIcon,
                            label: _audioLabel,
                            isActive: _isAudioActive,
                            onTap: _onAudioPressed,
                            onLongPress: () => _showAudioRouteSheet(context),
                          ),
                          _buildInCallGlassButton(
                            icon: Icons.videocam_rounded,
                            label: 'FaceTime',
                            isDisabled: true,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('FaceTime is unavailable over cellular relay'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                          _buildInCallGlassButton(
                            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            label: 'mute',
                            isActive: _isMuted,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              final nextState = !_isMuted;
                              setState(() => _isMuted = nextState);
                              RelayClient.instance.toggleMute(nextState);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Row 2: [ add ]  [ 🔴 END CALL (Centerpiece) ]  [ keypad ]
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildInCallGlassButton(
                            icon: Icons.add_rounded,
                            label: 'add',
                            onTap: () {
                              HapticFeedback.lightImpact();
                              if (widget.onOpenContacts != null) {
                                widget.onOpenContacts!();
                              } else if (widget.onMinimize != null) {
                                widget.onMinimize!();
                              }
                            },
                          ),
                          _buildEndCallButton(),
                          _buildInCallGlassButton(
                            icon: Icons.dialpad_rounded,
                            label: 'keypad',
                            onTap: () {
                              HapticFeedback.lightImpact();
                              showDtmfKeypadSheet(context);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Apple iOS Liquid Glass Circular In-Call Button
  Widget _buildInCallGlassButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    bool isDisabled = false,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return _InCallButtonLens(
      icon: icon,
      label: label,
      isActive: isActive,
      isDisabled: isDisabled,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  /// Center-Positioned Radiant Red End Call Button
  Widget _buildEndCallButton() {
    final isEnded = widget.callInfo.state == PhoneCallState.disconnected;
    return GestureDetector(
      onTap: isEnded
          ? null
          : () {
              HapticFeedback.heavyImpact();
              RelayClient.instance.hangupCall();
            },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isEnded
                  ? const LinearGradient(colors: [Color(0x88FF453A), Color(0x66D70015)])
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF453A), Color(0xFFD70015)],
                    ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B30).withValues(alpha: isEnded ? 0.1 : 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'end',
            style: TextStyle(
              color: Colors.transparent,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular Glass Lens Button for In-Call Controls
class _InCallButtonLens extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDisabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _InCallButtonLens({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isDisabled,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_InCallButtonLens> createState() => _InCallButtonLensState();
}

class _InCallButtonLensState extends State<_InCallButtonLens> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isActive
        ? Colors.black
        : (widget.isDisabled ? Colors.white.withValues(alpha: 0.3) : Colors.white);

    final labelColor = widget.isDisabled
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.9);

    return GestureDetector(
      onTapDown: (_) {
        if (!widget.isDisabled) setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        if (!widget.isDisabled) {
          setState(() => _isPressed = false);
          widget.onTap();
        }
      },
      onTapCancel: () {
        if (!widget.isDisabled) setState(() => _isPressed = false);
      },
      onLongPress: widget.isDisabled ? null : widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: CustomPaint(
                    foregroundPainter: GlassCircleBorderPainter(
                      strokeWidth: 0.9,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: widget.isActive
                            ? const [Color(0xFFFFFFFF), Color(0xD0FFFFFF), Color(0x70FFFFFF)]
                            : const [Color(0x70FFFFFF), Color(0x22FFFFFF), Color(0x06FFFFFF)],
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isActive
                            ? Colors.white
                            : (widget.isDisabled
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.16)),
                      ),
                      alignment: Alignment.center,
                      child: Icon(widget.icon, color: iconColor, size: 30),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: TextStyle(
                color: labelColor,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
