import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../services/whatsapp_launcher.dart';
import '../theme/liquid_glass_theme.dart';

class KeypadScreen extends StatefulWidget {
  const KeypadScreen({super.key});

  @override
  State<KeypadScreen> createState() => _KeypadScreenState();
}

class _KeypadScreenState extends State<KeypadScreen> {
  String _digits = '';
  ContactModel? _matchedContact;

  void _onDigitPressed(String char) {
    HapticFeedback.lightImpact();
    setState(() {
      _digits += char;
    });
    _lookupContact();
  }

  void _onBackspace() {
    if (_digits.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() {
        _digits = _digits.substring(0, _digits.length - 1);
      });
      _lookupContact();
    }
  }

  void _onClearAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _digits = '';
      _matchedContact = null;
    });
  }

  Future<void> _lookupContact() async {
    if (_digits.length < 3) {
      setState(() {
        _matchedContact = null;
      });
      return;
    }
    final contact = await DatabaseHelper.instance.findContactByNumber(_digits);
    if (mounted) {
      setState(() {
        _matchedContact = contact;
      });
    }
  }

  void _initiateGsmDial() {
    if (_digits.isEmpty) return;
    HapticFeedback.heavyImpact();
    RelayClient.instance.dialNumber(_digits);
  }

  void _openActionPicker() {
    if (_digits.isEmpty) return;
    WhatsAppLauncher.showActionPicker(
      context: context,
      name: _matchedContact?.displayName ?? '',
      number: _digits,
      onZongGsmCall: _initiateGsmDial,
      onZongSms: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Column(
      children: [
        const SizedBox(height: 20),
        SizedBox(
          height: 36,
          child: _matchedContact != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person, color: LiquidGlassTheme.iosBlue, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      _matchedContact!.displayName,
                      style: const TextStyle(
                        color: LiquidGlassTheme.iosBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _digits.isEmpty ? '' : _digits,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: LiquidGlassTheme.textPrimary,
                      fontSize: 36,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (_digits.isNotEmpty)
                  GestureDetector(
                    onTap: _onBackspace,
                    onLongPress: _onClearAll,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.backspace_outlined,
                        color: isDark ? Colors.white60 : Colors.black54,
                        size: 26,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Spacer(),
        _buildKeypadGrid(),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _initiateGsmDial,
          onLongPress: _openActionPicker,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: LiquidGlassTheme.gsmGreen,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.phone, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildKeypadGrid() {
    const keys = [
      ['1', ''],
      ['2', 'ABC'],
      ['3', 'DEF'],
      ['4', 'GHI'],
      ['5', 'JKL'],
      ['6', 'MNO'],
      ['7', 'PQRS'],
      ['8', 'TUV'],
      ['9', 'WXYZ'],
      ['*', ''],
      ['0', '+'],
      ['#', ''],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: keys.map((k) {
          return _KeypadButton(
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

class _KeypadButton extends StatelessWidget {
  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _KeypadButton({
    required this.digit,
    required this.letters,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFF4F4F8),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? const Color(0x28FFFFFF) : const Color(0x1F000000),
            width: 0.5,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: TextStyle(
                color: LiquidGlassTheme.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: TextStyle(
                  color: LiquidGlassTheme.textPrimary,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
