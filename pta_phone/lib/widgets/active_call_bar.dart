import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';

class ActiveCallBar extends StatefulWidget {
  final ActiveCallInfo callInfo;
  final VoidCallback onOpenDtmf;

  const ActiveCallBar({
    super.key,
    required this.callInfo,
    required this.onOpenDtmf,
  });

  @override
  State<ActiveCallBar> createState() => _ActiveCallBarState();
}

class _ActiveCallBarState extends State<ActiveCallBar> {
  late Timer _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _seconds = ((DateTime.now().millisecondsSinceEpoch - widget.callInfo.startTime) / 1000).floor();
    if (_seconds < 0) _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _seconds++;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.callInfo.callerName.isNotEmpty
        ? widget.callInfo.callerName
        : widget.callInfo.number;

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0x351C1C26),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: LiquidGlassTheme.gsmGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_in_talk, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LiquidGlassTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Zong GSM • ${_formatDuration(_seconds)}',
                  style: const TextStyle(
                    color: LiquidGlassTheme.gsmGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onOpenDtmf,
            icon: const Icon(Icons.dialpad, color: Colors.white70, size: 22),
            tooltip: 'Keypad / DTMF',
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              HapticFeedback.heavyImpact();
              RelayClient.instance.hangupCall();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: LiquidGlassTheme.crimsonRed,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call_end, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
