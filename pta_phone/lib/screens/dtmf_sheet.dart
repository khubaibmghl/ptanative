import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';

void showDtmfKeypadSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const _DtmfSheet(),
  );
}

class _DtmfSheet extends StatefulWidget {
  const _DtmfSheet();

  @override
  State<_DtmfSheet> createState() => _DtmfSheetState();
}

class _DtmfSheetState extends State<_DtmfSheet> {
  String _digitsSent = '';

  void _sendDigit(String d) {
    HapticFeedback.lightImpact();
    RelayClient.instance.sendDtmf(d);
    setState(() {
      _digitsSent += d;
    });
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', ''],
      ['2', 'A B C'],
      ['3', 'D E F'],
      ['4', 'G H I'],
      ['5', 'J K L'],
      ['6', 'M N O'],
      ['7', 'P Q R S'],
      ['8', 'T U V'],
      ['9', 'W X Y Z'],
      ['*', ''],
      ['0', '+'],
      ['#', ''],
    ];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 14, bottom: 44),
          decoration: BoxDecoration(
            color: const Color(0xF212111E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.22),
                width: 0.8,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag indicator bar
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // Title Header
              const Text(
                'Keypad',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),

              // Digits display / IVR helper
              Container(
                height: 38,
                alignment: Alignment.center,
                child: Text(
                  _digitsSent.isEmpty ? 'Touch keys to send tones to IVR menu' : _digitsSent,
                  style: TextStyle(
                    color: _digitsSent.isEmpty
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.white,
                    fontSize: _digitsSent.isEmpty ? 13 : 26,
                    fontWeight: _digitsSent.isEmpty ? FontWeight.w400 : FontWeight.w300,
                    letterSpacing: _digitsSent.isEmpty ? 0 : 3.0,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 12-Key Liquid Glass Keypad Grid
              Wrap(
                spacing: 24,
                runSpacing: 14,
                alignment: WrapAlignment.center,
                children: keys.map((k) {
                  return _DtmfGlassKey(
                    digit: k[0],
                    letters: k[1],
                    onTap: () => _sendDigit(k[0]),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Bottom "Hide" Pill Button
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 0.6,
                    ),
                  ),
                  child: const Text(
                    'Hide',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular Liquid Glass Key for DTMF Keypad
class _DtmfGlassKey extends StatefulWidget {
  final String digit;
  final String letters;
  final VoidCallback onTap;

  const _DtmfGlassKey({
    required this.digit,
    required this.letters,
    required this.onTap,
  });

  @override
  State<_DtmfGlassKey> createState() => _DtmfGlassKeyState();
}

class _DtmfGlassKeyState extends State<_DtmfGlassKey> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isPressed ? 0.1 : 0.25),
                blurRadius: _isPressed ? 4 : 8,
                offset: Offset(0, _isPressed ? 1 : 3),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: CustomPaint(
                foregroundPainter: GlassCircleBorderPainter(
                  strokeWidth: 0.8,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isPressed
                        ? const [Color(0xD0FFFFFF), Color(0x60FFFFFF), Color(0x18FFFFFF)]
                        : const [Color(0x75FFFFFF), Color(0x22FFFFFF), Color(0x06FFFFFF)],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isPressed
                          ? const [Color(0x60FFFFFF), Color(0x35FFFFFF)]
                          : const [Color(0x22FFFFFF), Color(0x0DFFFFFF)],
                    ),
                  ),
                  child: _buildContent(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (widget.digit == '*') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            '*',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w300,
              height: 1.0,
            ),
          ),
        ),
      );
    }

    if (widget.digit == '#') {
      return const Center(
        child: Text(
          '#',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w300,
            height: 1.0,
          ),
        ),
      );
    }

    if (widget.digit == '0') {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '0',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w300,
              height: 1.0,
            ),
          ),
          SizedBox(height: 1),
          Text(
            '+',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.0,
            ),
          ),
        ],
      );
    }

    if (widget.letters.isEmpty) {
      return Center(
        child: Text(
          widget.digit,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w300,
            height: 1.0,
          ),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          widget.digit,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w300,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          widget.letters,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 8.5,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
