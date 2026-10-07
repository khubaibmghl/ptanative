import 'dart:async';
import 'package:flutter/material.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';
import 'dtmf_sheet.dart';

class InCallScreen extends StatefulWidget {
  final ActiveCallInfo callInfo;

  const InCallScreen({super.key, required this.callInfo});

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isMuted = false;
  bool _isSpeaker = false;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant InCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.callInfo.state != oldWidget.callInfo.state) {
      _startTimerIfNeeded();
    }
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();
    if (widget.callInfo.state == PhoneCallState.connected) {
      if (widget.callInfo.startTime > 0) {
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
        return 'Calling...';
      case PhoneCallState.ringing:
        return 'Ringing...';
      case PhoneCallState.connected:
        return _formattedDuration;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.callInfo.callerName.isNotEmpty ? widget.callInfo.callerName : widget.callInfo.number;
    final initial = displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : '?';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Header Network indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cell_tower, color: LiquidGlassTheme.gsmGreen, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Zong 4G • GSM Relay',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Spacer(),

            // Big Contact Circle Avatar
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B466B), Color(0xFF1E2436)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),

            // Caller Name & Phone Number
            Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.callInfo.number,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),

            // Status / Live Call Duration
            Text(
              _statusSubtitle,
              style: TextStyle(
                color: widget.callInfo.state == PhoneCallState.connected
                    ? LiquidGlassTheme.gsmGreen
                    : LiquidGlassTheme.iosBlue,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),

            const Spacer(),

            // In-Call Action Grid (Mute, Keypad, Speaker)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCallOptionButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: 'Mute',
                    isActive: _isMuted,
                    onTap: () => setState(() => _isMuted = !_isMuted),
                  ),
                  _buildCallOptionButton(
                    icon: Icons.grid_view_rounded,
                    label: 'Keypad',
                    isActive: false,
                    onTap: () => showDtmfKeypadSheet(context),
                  ),
                  _buildCallOptionButton(
                    icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
                    label: 'Speaker',
                    isActive: _isSpeaker,
                    onTap: () => setState(() => _isSpeaker = !_isSpeaker),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),

            // End Call Red Button
            GestureDetector(
              onTap: () {
                RelayClient.instance.hangupCall();
              },
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: LiquidGlassTheme.crimsonRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: LiquidGlassTheme.crimsonRed.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildCallOptionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isActive ? Colors.black : Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
