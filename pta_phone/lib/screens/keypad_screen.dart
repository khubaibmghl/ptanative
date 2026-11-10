import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../services/whatsapp_launcher.dart';
import '../theme/liquid_glass_theme.dart';
import 'contact_detail_screen.dart';

/// iPhone 15 Pro / iOS 27 Liquid Glass Dial Pad Screen
class KeypadScreen extends StatefulWidget {
  const KeypadScreen({super.key});

  @override
  State<KeypadScreen> createState() => _KeypadScreenState();
}

class _KeypadScreenState extends State<KeypadScreen> {
  String _digits = '';
  String? _clipboardNumber;
  List<ContactMatchModel> _matches = [];
  StreamSubscription? _callSub;
  bool _isCallPressed = false;

  @override
  void initState() {
    super.initState();
    _checkClipboardForNumber();

    // Auto-clear keypad number when a call ends
    _callSub = RelayClient.instance.activeCallStream.listen((call) {
      if (call == null && mounted && _digits.isNotEmpty) {
        setState(() {
          _digits = '';
          _matches = [];
        });
      }
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
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
      final matchesNumber = c.phoneNumbers.any(
        (p) => p.rawNumber.contains(_digits) || p.normalizedNumber.contains(_digits),
      );
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

  Future<void> _initiateGsmDial([String? targetNumber]) async {
    final numberToDial = targetNumber ?? _digits;
    if (numberToDial.isEmpty) {
      // Standard Apple Phone behavior: If dialer is empty, populate last dialed number
      final logs = await DatabaseHelper.instance.getCallLogs();
      final lastOutgoing = logs.where((l) => l.callType == CallType.outgoing).firstOrNull;
      if (lastOutgoing != null && lastOutgoing.remoteNumber.isNotEmpty) {
        if (mounted) {
          HapticFeedback.selectionClick();
          setState(() {
            _digits = lastOutgoing.remoteNumber;
          });
          _lookupMatches();
        }
      }
      return;
    }

    HapticFeedback.heavyImpact();
    RelayClient.instance.dialNumber(numberToDial);
    if (mounted) {
      setState(() {
        _digits = '';
        _matches = [];
      });
    }
  }

  void _openAddContactScreen() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactDetailScreen(rawNumber: _digits),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;
    final primaryTextColor = isDark ? LiquidGlassTheme.textPrimaryDark : LiquidGlassTheme.textPrimary;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const SizedBox(height: 4),

          // Header Top Bar: Add Contact Action Lens (Top Right)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: _GlassHeaderButton(
                icon: Icons.person_add_rounded,
                onTap: _openAddContactScreen,
              ),
            ),
          ),

          // Floating Clipboard Paste Pill
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
                margin: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: CustomPaint(
                      foregroundPainter: GlassBorderPainter(
                        radius: 18,
                        strokeWidth: 0.8,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [const Color(0x60007AFF), const Color(0x25007AFF), const Color(0x0A007AFF)]
                              : [const Color(0x80007AFF), const Color(0x35007AFF), const Color(0x10007AFF)],
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: LiquidGlassTheme.iosBlue.withValues(alpha: isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.paste_rounded, size: 14, color: LiquidGlassTheme.iosBlue),
                            const SizedBox(width: 6),
                            Text(
                              'Paste $_clipboardNumber',
                              style: const TextStyle(
                                color: LiquidGlassTheme.iosBlue,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Big Centered Dialed Digits Display (Auto-scaling with FittedBox)
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            alignment: Alignment.center,
            child: _digits.isNotEmpty
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _digits,
                      maxLines: 1,
                      style: TextStyle(
                        color: primaryTextColor,
                        fontSize: 38,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 2.0,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // "Add Number" Subtle Action Link
          AnimatedOpacity(
            opacity: _digits.isNotEmpty ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: _digits.isNotEmpty
                ? GestureDetector(
                    onTap: _openAddContactScreen,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Add Number',
                        style: TextStyle(
                          color: LiquidGlassTheme.iosBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(height: 22),
          ),

          // Intelligent Contact Match Floating Glass Card
          if (_digits.isNotEmpty && _matches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: CustomPaint(
                    foregroundPainter: GlassBorderPainter(
                      radius: 20,
                      strokeWidth: 0.8,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [const Color(0x65FFFFFF), const Color(0x22FFFFFF), const Color(0x06FFFFFF)]
                            : [const Color(0x95FFFFFF), const Color(0x45FFFFFF), const Color(0x18000000)],
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0x2E161528) : const Color(0x65FFFFFF),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => _initiateGsmDial(_matches.first.number),
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.18),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _matches.first.name.isNotEmpty
                                          ? _matches.first.name[0].toUpperCase()
                                          : '#',
                                      style: const TextStyle(
                                        color: LiquidGlassTheme.iosBlue,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _matches.first.name,
                                    style: TextStyle(
                                      color: primaryTextColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  _matches.first.number,
                                  style: const TextStyle(
                                    color: LiquidGlassTheme.iosBlue,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_matches.length > 1) ...[
                            Divider(
                              height: 14,
                              thickness: 0.5,
                              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                            ),
                            Row(
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  color: isDark ? LiquidGlassTheme.textSecondaryDark : LiquidGlassTheme.textSecondary,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_matches.length - 1} more results',
                                  style: TextStyle(
                                    color: isDark ? LiquidGlassTheme.textSecondaryDark : LiquidGlassTheme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 24),

          const Spacer(),

          // 12-Key Dial Pad Grid (1-9, *, 0, #)
          _buildKeypadGrid(),

          const SizedBox(height: 18),

          // Bottom Action Row: Spacer (Left) | Green Call Button (Center) | Backspace Button (Right)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: 286, // Aligns exactly with 3x78 width + 2x26 gap
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left WhatsApp Slot (78 pt slot containing 56 pt lens)
                  SizedBox(
                    width: 78,
                    height: 78,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _digits.isNotEmpty ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: AnimatedScale(
                          scale: _digits.isNotEmpty ? 1.0 : 0.8,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOutCubic,
                          child: IgnorePointer(
                            ignoring: _digits.isEmpty,
                            child: _WhatsAppBubbleButton(
                              onTap: () {
                                if (_digits.isNotEmpty) {
                                  HapticFeedback.lightImpact();
                                  WhatsAppLauncher.startChat(_digits);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Center Green Call Lens (78 pt)
                  GestureDetector(
                    onTapDown: (_) => setState(() => _isCallPressed = true),
                    onTapUp: (_) {
                      setState(() => _isCallPressed = false);
                      _initiateGsmDial();
                    },
                    onTapCancel: () => setState(() => _isCallPressed = false),
                    child: AnimatedScale(
                      scale: _isCallPressed ? 0.91 : 1.0,
                      duration: const Duration(milliseconds: 90),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: LiquidGlassTheme.gsmGreen.withValues(alpha: _isCallPressed ? 0.35 : 0.55),
                              blurRadius: _isCallPressed ? 14 : 26,
                              spreadRadius: _isCallPressed ? 0 : 2,
                              offset: Offset(0, _isCallPressed ? 4 : 8),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: CustomPaint(
                              foregroundPainter: GlassCircleBorderPainter(
                                strokeWidth: 1.0,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0x95FFFFFF),
                                    Color(0x35FFFFFF),
                                    Color(0x05000000),
                                  ],
                                  stops: [0.0, 0.45, 1.0],
                                ),
                              ),
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF38E56B),
                                      Color(0xFF24B34A),
                                    ],
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.phone_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Right Backspace Slot (78 pt slot containing 56 pt lens)
                  SizedBox(
                    width: 78,
                    height: 78,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _digits.isNotEmpty ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: AnimatedScale(
                          scale: _digits.isNotEmpty ? 1.0 : 0.8,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOutCubic,
                          child: IgnorePointer(
                            ignoring: _digits.isEmpty,
                            child: _BackspaceBubbleButton(
                              onTap: _onBackspace,
                              onLongPress: _onClearAll,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Safe padding clearing the floating dock (68 pt) + home bar
          SizedBox(height: bottomInset + 88),
        ],
      ),
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
      child: SizedBox(
        width: 286,
        child: Wrap(
          spacing: 26,
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
      ),
    );
  }
}

class ContactMatchModel {
  final String name;
  final String number;

  ContactMatchModel({required this.name, required this.number});
}

/// Circular Glass Lens Button with Specular Rim & Frosted Blur
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
    final textColor = isDark ? LiquidGlassTheme.textPrimaryDark : LiquidGlassTheme.textPrimary;

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
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: _isPressed ? 0.15 : 0.35),
                      blurRadius: _isPressed ? 6 : 14,
                      offset: Offset(0, _isPressed ? 2 : 5),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: _isPressed ? 0.02 : 0.06),
                      blurRadius: _isPressed ? 4 : 10,
                      offset: Offset(0, _isPressed ? 1 : 4),
                    ),
                  ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: CustomPaint(
                foregroundPainter: GlassCircleBorderPainter(
                  strokeWidth: 0.9,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? (_isPressed
                            ? const [Color(0xD0FFFFFF), Color(0x60FFFFFF), Color(0x18FFFFFF)]
                            : const [Color(0x75FFFFFF), Color(0x24FFFFFF), Color(0x06FFFFFF)])
                        : (_isPressed
                            ? const [Color(0xFFFFFFFF), Color(0x80FFFFFF), Color(0x35000000)]
                            : const [Color(0xD0FFFFFF), Color(0x55FFFFFF), Color(0x18000000)]),
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? (_isPressed
                              ? const [Color(0x68FFFFFF), Color(0x38FFFFFF)]
                              : const [Color(0x28FFFFFF), Color(0x0EFFFFFF)])
                          : (_isPressed
                              ? const [Color(0xC0FFFFFF), Color(0x88FFFFFF)]
                              : const [Color(0x78FFFFFF), Color(0x35FFFFFF)]),
                    ),
                  ),
                  child: _buildKeyContent(textColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyContent(Color textColor) {
    if (widget.digit == '*') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '*',
            style: TextStyle(
              color: textColor,
              fontSize: 44,
              fontWeight: FontWeight.w300,
              height: 1.0,
            ),
          ),
        ),
      );
    }

    if (widget.digit == '#') {
      return Center(
        child: Text(
          '#',
          style: TextStyle(
            color: textColor,
            fontSize: 28,
            fontWeight: FontWeight.w300,
            height: 1.0,
          ),
        ),
      );
    }

    if (widget.digit == '0') {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '0',
            style: TextStyle(
              color: textColor,
              fontSize: 35,
              fontWeight: FontWeight.w300,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '+',
            style: TextStyle(
              color: textColor,
              fontSize: 14,
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
          style: TextStyle(
            color: textColor,
            fontSize: 35,
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
          style: TextStyle(
            color: textColor,
            fontSize: 35,
            fontWeight: FontWeight.w300,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          widget.letters,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.85),
            fontSize: 9.5,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

/// Frosted Glass Backspace Bubble Button
class _BackspaceBubbleButton extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BackspaceBubbleButton({
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_BackspaceBubbleButton> createState() => _BackspaceBubbleButtonState();
}

class _BackspaceBubbleButtonState extends State<_BackspaceBubbleButton> {
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
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: CustomPaint(
                foregroundPainter: GlassCircleBorderPainter(
                  strokeWidth: 0.8,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [const Color(0x60FFFFFF), const Color(0x20FFFFFF), const Color(0x06FFFFFF)]
                        : [const Color(0x95FFFFFF), const Color(0x40FFFFFF), const Color(0x15000000)],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? (_isPressed
                              ? const [Color(0x55FFFFFF), Color(0x2AFFFFFF)]
                              : const [Color(0x22FFFFFF), Color(0x0DFFFFFF)])
                          : (_isPressed
                              ? const [Color(0xBBFFFFFF), Color(0x80FFFFFF)]
                              : const [Color(0x75FFFFFF), Color(0x35FFFFFF)]),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.backspace_rounded,
                      color: isDark ? LiquidGlassTheme.textPrimaryDark : LiquidGlassTheme.textPrimary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header Icon Button with Glass Refraction & Border
class _GlassHeaderButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassHeaderButton({
    required this.icon,
    required this.onTap,
  });

  @override
  State<_GlassHeaderButton> createState() => _GlassHeaderButtonState();
}

class _GlassHeaderButtonState extends State<_GlassHeaderButton> {
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
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
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
                    colors: isDark
                        ? [const Color(0x60FFFFFF), const Color(0x18FFFFFF), const Color(0x05FFFFFF)]
                        : [const Color(0x95FFFFFF), const Color(0x40FFFFFF), const Color(0x12000000)],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0x22FFFFFF) : const Color(0x60FFFFFF),
                  ),
                  child: Center(
                    child: Icon(
                      widget.icon,
                      color: isDark ? LiquidGlassTheme.textPrimaryDark : LiquidGlassTheme.textPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 1-Tap Direct WhatsApp Chat Bubble Button for Keypad
class _WhatsAppBubbleButton extends StatefulWidget {
  final VoidCallback onTap;

  const _WhatsAppBubbleButton({required this.onTap});

  @override
  State<_WhatsAppBubbleButton> createState() => _WhatsAppBubbleButtonState();
}

class _WhatsAppBubbleButtonState extends State<_WhatsAppBubbleButton> {
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
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: LiquidGlassTheme.whatsappGreen.withValues(alpha: isDark ? 0.25 : 0.18),
                blurRadius: _isPressed ? 8 : 14,
                offset: const Offset(0, 3),
              ),
              if (isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: CustomPaint(
                foregroundPainter: GlassCircleBorderPainter(
                  strokeWidth: 0.85,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            LiquidGlassTheme.whatsappGreen.withValues(alpha: 0.6),
                            const Color(0x35FFFFFF),
                            const Color(0x06FFFFFF),
                          ]
                        : [
                            LiquidGlassTheme.whatsappGreen.withValues(alpha: 0.8),
                            const Color(0x40FFFFFF),
                            const Color(0x15000000),
                          ],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isPressed
                          ? [
                              LiquidGlassTheme.whatsappGreen.withValues(alpha: 0.40),
                              LiquidGlassTheme.whatsappGreen.withValues(alpha: 0.25),
                            ]
                          : [
                              LiquidGlassTheme.whatsappGreen.withValues(alpha: 0.22),
                              LiquidGlassTheme.whatsappGreen.withValues(alpha: 0.12),
                            ],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.chat_bubble_rounded,
                      color: LiquidGlassTheme.whatsappGreen,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
