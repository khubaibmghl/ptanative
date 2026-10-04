import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';

void showDtmfKeypadSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
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
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

    return Container(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 40),
      decoration: const BoxDecoration(
        color: Color(0xF0121218),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text(
            'In-Call DTMF Keypad',
            style: TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _digitsSent.isEmpty ? 'Touch keys to send IVR tones' : _digitsSent,
            style: const TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 20,
            runSpacing: 14,
            alignment: WrapAlignment.center,
            children: keys.map((k) {
              return GestureDetector(
                onTap: () => _sendDigit(k),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0x22FFFFFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x28FFFFFF), width: 0.75),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    k,
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w400),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
