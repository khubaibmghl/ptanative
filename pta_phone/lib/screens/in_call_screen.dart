import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/relay_client.dart';
import '../data/database_helper.dart';
import '../widgets/contact_avatar_widget.dart';
import 'dtmf_sheet.dart';

/// Pixel-Perfect iOS 17 / iOS 18 In-Call Screen
/// Featuring the authentic Contact Poster aesthetic, one-handed lower 6-button cluster
/// with bottom-center End Call button, frosted glass circular controls, and swipe-down minimization.
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
  bool _isMuted = false;
  bool _isSpeaker = false;
  String? _contactId;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
    _lookupContact();
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
      _startTimerIfNeeded();
    } else if (widget.callInfo.durationSeconds > 0 && widget.callInfo.durationSeconds != _elapsedSeconds) {
      setState(() {
        _elapsedSeconds = widget.callInfo.durationSeconds;
      });
    }
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();
    if (widget.callInfo.state == PhoneCallState.connected) {
      if (widget.callInfo.durationSeconds > 0) {
        _elapsedSeconds = widget.callInfo.durationSeconds;
      } else if (widget.callInfo.startTime > 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final computed = (now - widget.callInfo.startTime) ~/ 1000;
        _elapsedSeconds = (computed >= 0 && computed < 86400) ? computed : 0;
      } else {
        _elapsedSeconds = 0;
      }

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _elapsedSeconds++;
          });
        }
      });
    } else {
      _elapsedSeconds = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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
        return 'calling mobile...';
      case PhoneCallState.ringing:
        return 'ringing...';
      case PhoneCallState.connected:
        return _formattedDuration;
    }
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

                      // Discreet carrier / audio indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'PTA Cellular',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // Apple Contact Poster Monogram / Avatar Streamed from Vivo S1
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

                // Contact Display Name (Apple SF Pro Display Typography)
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

                // --- Modern iOS 17 / 18 Lower 6-Button Control Cluster ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Row 1: [ audio ]  [ FaceTime ]  [ mute ]
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildIosCircleButton(
                            icon: _isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                            label: 'audio',
                            isActive: _isSpeaker,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              final nextState = !_isSpeaker;
                              setState(() => _isSpeaker = nextState);
                              RelayClient.instance.setSpeakerphone(nextState);
                            },
                          ),
                          _buildIosCircleButton(
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
                          _buildIosCircleButton(
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
                          _buildIosCircleButton(
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
                          _buildIosCircleButton(
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

  /// Apple iOS 17/18 Frosted Glass Circular In-Call Button
  Widget _buildIosCircleButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    bool isDisabled = false,
    required VoidCallback onTap,
  }) {
    final bgColor = isActive
        ? Colors.white
        : (isDisabled
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.16));

    final iconColor = isActive
        ? Colors.black
        : (isDisabled
            ? Colors.white.withValues(alpha: 0.3)
            : Colors.white);

    final labelColor = isDisabled
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.9);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  /// The Iconic iOS 17/18 Center-Positioned Red End Call Button
  Widget _buildEndCallButton() {
    return GestureDetector(
      onTap: () {
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
            decoration: const BoxDecoration(
              color: Color(0xFFFF3B30), // Apple System Red
              shape: BoxShape.circle,
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
              color: Colors.transparent, // iOS 17 leaves the red button unlabelled, keeping space aligned
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
