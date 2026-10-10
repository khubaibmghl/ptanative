import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';

class KeypadScreen extends StatefulWidget {
  const KeypadScreen({super.key});

  @override
  State<KeypadScreen> createState() => _KeypadScreenState();
}

class _KeypadScreenState extends State<KeypadScreen> {
  String _digits = '';
  String? _clipboardNumber;
  List<ContactMatchModel> _matches = [];

  @override
  void initState() {
    super.initState();
    _checkClipboardForNumber();
  }

  Future<void> _checkClipboardForNumber() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      final digits = text.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 7 && digits.length <= 15 && text != _digits) {
        if (mounted) setState(() => _clipboardNumber = text);
      }
    } catch (_) {}
  }

  void _onDigitPressed(String char) {
    HapticFeedback.lightImpact();
    setState(() {
      _digits += char;
    });
    _lookupMatches();
  }

  void _onBackspace() {
    if (_digits.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() {
        _digits = _digits.substring(0, _digits.length - 1);
      });
      _lookupMatches();
    }
  }

  void _onClearAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _digits = '';
      _matches = [];
    });
  }

  Future<void> _lookupMatches() async {
    if (_digits.isEmpty) {
      if (mounted) setState(() => _matches = []);
      return;
    }

    final List<ContactMatchModel> results = [];

    // Search contacts by number, name, or T9 keypad sequence
    final allContacts = await DatabaseHelper.instance.getContacts();
    for (final c in allContacts) {
      final matchesNumber = c.phoneNumbers.any((p) => p.rawNumber.contains(_digits) || p.normalizedNumber.contains(_digits));
      final matchesName = c.displayName.toLowerCase().contains(_digits.toLowerCase());
      final matchesT9 = PhoneNumberNormalizer.matchesT9(c.displayName, _digits);

      if (matchesNumber || matchesName || matchesT9) {
        results.add(ContactMatchModel(
          name: c.displayName,
          number: c.primaryNumber,
        ));
      }
    }

    // Search recents if needed
    final logs = await DatabaseHelper.instance.getCallLogs(missedOnly: false);
    for (final log in logs) {
      final matchesNum = log.remoteNumber.contains(_digits);
      final matchesCaller = log.callerName.toLowerCase().contains(_digits.toLowerCase());
      final matchesT9Caller = PhoneNumberNormalizer.matchesT9(log.callerName, _digits);

      if (matchesNum || matchesCaller || matchesT9Caller) {
        if (!results.any((r) => r.number == log.remoteNumber)) {
          results.add(ContactMatchModel(
            name: log.callerName.isNotEmpty ? log.callerName : log.remoteNumber,
            number: log.remoteNumber,
          ));
        }
      }
    }

    if (mounted) {
      setState(() {
        _matches = results;
      });
    }
  }

  void _initiateGsmDial([String? targetNumber]) {
    final numberToDial = targetNumber ?? _digits;
    if (numberToDial.isEmpty) return;
    HapticFeedback.heavyImpact();
    RelayClient.instance.dialNumber(numberToDial);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Column(
      children: [
        const SizedBox(height: 12),

        // Header Top Right Add Contact Icon Button
        Padding(
          padding: const EdgeInsets.only(right: 24, top: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : const Color(0xFFF0F0F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add_outlined, color: LiquidGlassTheme.textPrimary, size: 20),
            ),
          ),
        ),

        const SizedBox(height: 8),

        if (_clipboardNumber != null && _digits.isEmpty)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _digits = _clipboardNumber!;
                _clipboardNumber = null;
              });
              _lookupMatches();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.paste_rounded, size: 14, color: LiquidGlassTheme.iosBlue),
                  const SizedBox(width: 6),
                  Text(
                    'Paste $_clipboardNumber',
                    style: const TextStyle(color: LiquidGlassTheme.iosBlue, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),

        // Centered Big Dialed Digits Display
        SizedBox(
          height: 52,
          child: Center(
            child: Text(
              _digits,
              style: TextStyle(
                color: LiquidGlassTheme.textPrimary,
                fontSize: 38,
                fontWeight: FontWeight.w400,
                letterSpacing: 2.0,
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Intelligent Suggestion Floating Glass Card
        if (_digits.isNotEmpty && _matches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x351C1C26) : const Color(0xF5F6F8FC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Match
                  InkWell(
                    onTap: () => _initiateGsmDial(_matches.first.number),
                    child: Row(
                      children: [
                        const Icon(Icons.account_circle, color: LiquidGlassTheme.textSecondary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _matches.first.name,
                            style: TextStyle(
                              color: LiquidGlassTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _matches.first.number,
                          style: TextStyle(
                            color: LiquidGlassTheme.iosBlue,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_matches.length > 1) ...[
                    const Divider(height: 12, color: Colors.white12),
                    Row(
                      children: [
                        const Icon(Icons.search, color: LiquidGlassTheme.textSecondary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${_matches.length - 1} More Results',
                          style: const TextStyle(
                            color: LiquidGlassTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          const SizedBox(height: 48),

        const Spacer(),

        // Keypad Grid 1-9, *, 0, #
        _buildKeypadGrid(),

        const SizedBox(height: 24),

        // Bottom Controls: Green Call Button & Backspace Icon
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 50), // Spacer balancing right backspace
              const Spacer(),
              // Green Circular Dial Call Button
              GestureDetector(
                onTap: () => _initiateGsmDial(),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: LiquidGlassTheme.gsmGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.phone, color: Colors.white, size: 34),
                ),
              ),
              const Spacer(),
              // Backspace Button
              SizedBox(
                width: 50,
                child: _digits.isNotEmpty
                    ? GestureDetector(
                        onTap: _onBackspace,
                        onLongPress: _onClearAll,
                        child: Container(
                          width: 44,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white12 : const Color(0xFFE8E8EE),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.backspace_outlined,
                            color: LiquidGlassTheme.textPrimary,
                            size: 20,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildKeypadGrid() {
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: keys.map((k) {
          return _KeypadBubbleButton(
            digit: k[0],
            letters: k[1],
            onTap: () => _onDigitPressed(k[0]),
            onLongPress: k[0] == '0' ? () => _onDigitPressed('+') : null,
          );
        }).toList(),
      ),
    );
  }
}

class ContactMatchModel {
  final String name;
  final String number;

  ContactMatchModel({required this.name, required this.number});
}

/// Keypad Button with Elastic Spring Bubble Touch Animation
class _KeypadBubbleButton extends StatefulWidget {
  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _KeypadBubbleButton({
    required this.digit,
    required this.letters,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_KeypadBubbleButton> createState() => _KeypadBubbleButtonState();
}

class _KeypadBubbleButtonState extends State<_KeypadBubbleButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _isPressed ? 0.91 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: _isPressed
                ? (isDark ? const Color(0x40FFFFFF) : const Color(0xFFE2E2EA))
                : (isDark ? const Color(0x22FFFFFF) : const Color(0xFFF4F4F8)),
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? const Color(0x28FFFFFF) : const Color(0x1F000000),
              width: 0.5,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: _isPressed ? 0.01 : 0.05),
                      blurRadius: _isPressed ? 3 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.digit,
                style: TextStyle(
                  color: LiquidGlassTheme.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (widget.letters.isNotEmpty)
                Text(
                  widget.letters,
                  style: TextStyle(
                    color: LiquidGlassTheme.textPrimary,
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
