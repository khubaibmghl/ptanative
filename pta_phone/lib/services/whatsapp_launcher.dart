import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pta_shared/pta_shared.dart';
import '../theme/liquid_glass_theme.dart';

class WhatsAppLauncher {
  /// Launches native WhatsApp voice call
  static Future<bool> startAudioCall(String rawNumber) async {
    final norm = PhoneNumberNormalizer.normalize(rawNumber);
    final fullNumber = norm.startsWith('92') ? norm : '92$norm';
    final uri = Uri.parse('whatsapp://call?phone=$fullNumber');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    final fallback = Uri.parse('https://wa.me/$fullNumber');
    return await launchUrl(fallback, mode: LaunchMode.externalApplication);
  }

  /// Launches native WhatsApp chat conversation
  static Future<bool> startChat(String rawNumber, {String? text}) async {
    final norm = PhoneNumberNormalizer.normalize(rawNumber);
    final fullNumber = norm.startsWith('92') ? norm : '92$norm';
    final query = text != null ? '?text=${Uri.encodeComponent(text)}' : '';
    final uri = Uri.parse('whatsapp://send?phone=$fullNumber$query');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    final fallback = Uri.parse('https://wa.me/$fullNumber$query');
    return await launchUrl(fallback, mode: LaunchMode.externalApplication);
  }

  /// Opens the Liquid Glass iOS Action Picker Modal
  static void showActionPicker({
    required BuildContext context,
    required String name,
    required String number,
    String? label,
    required VoidCallback onZongGsmCall,
    required VoidCallback onZongSms,
  }) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ActionPickerSheet(
        name: name,
        number: number,
        label: label,
        onZongGsmCall: () {
          Navigator.pop(ctx);
          onZongGsmCall();
        },
        onZongSms: () {
          Navigator.pop(ctx);
          onZongSms();
        },
      ),
    );
  }
}

class _ActionPickerSheet extends StatelessWidget {
  final String name;
  final String number;
  final String? label;
  final VoidCallback onZongGsmCall;
  final VoidCallback onZongSms;

  const _ActionPickerSheet({
    required this.name,
    required this.number,
    this.label,
    required this.onZongGsmCall,
    required this.onZongSms,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 40),
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
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            name.isNotEmpty ? name : number,
            style: const TextStyle(
              color: LiquidGlassTheme.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '$number ${label != null ? "• $label" : ""}',
              style: const TextStyle(
                color: LiquidGlassTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
          const SizedBox(height: 24),
          _buildActionButton(
            icon: Icons.phone,
            iconColor: LiquidGlassTheme.gsmGreen,
            title: 'Zong GSM Cellular Call',
            subtitle: 'Relayed via Vivo S1 SIM',
            onTap: onZongGsmCall,
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            icon: Icons.chat_bubble_outline,
            iconColor: LiquidGlassTheme.accentBlue,
            title: 'Send Cellular SMS',
            subtitle: 'Relayed via Vivo S1 SIM',
            onTap: onZongSms,
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            icon: Icons.phone_in_talk,
            iconColor: LiquidGlassTheme.whatsappGreen,
            title: 'WhatsApp Audio Call',
            subtitle: 'Direct VoIP via WhatsApp',
            onTap: () {
              Navigator.pop(context);
              WhatsAppLauncher.startAudioCall(number);
            },
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            icon: Icons.message,
            iconColor: LiquidGlassTheme.whatsappGreen,
            title: 'WhatsApp Chat',
            subtitle: 'Open conversation in WhatsApp',
            onTap: () {
              Navigator.pop(context);
              WhatsAppLauncher.startChat(number);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: LiquidGlassTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: LiquidGlassTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: LiquidGlassTheme.textTertiary,
            size: 20,
          ),
        ],
      ),
    );
  }
}
