import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<SmsMessageModel> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();

    RelayClient.instance.smsStream.listen((_) {
      _loadMessages();
    });
  }

  Future<void> _loadMessages() async {
    final list = await DatabaseHelper.instance.getMessages();
    if (mounted) {
      setState(() {
        _messages = list;
        _isLoading = false;
      });
    }
  }

  void _copyOtpToClipboard(String otp) {
    Clipboard.setData(ClipboardData(text: otp));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('OTP code $otp copied to clipboard!'),
        backgroundColor: LiquidGlassTheme.surfaceDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Bank OTP & SMS'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? const Center(
                  child: Text(
                    'No SMS messages received yet',
                    style: TextStyle(color: LiquidGlassTheme.textSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 100),
                  itemCount: _messages.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return _buildMessageCard(msg);
                  },
                ),
    );
  }

  Widget _buildMessageCard(SmsMessageModel msg) {
    final hasOtp = msg.extractedOtp != null && msg.extractedOtp!.isNotEmpty;

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      color: hasOtp ? const Color(0x352A2410) : LiquidGlassTheme.glassFill,
      border: hasOtp
          ? Border.all(color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.4), width: 1)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasOtp
                      ? LiquidGlassTheme.goldOtp.withValues(alpha: 0.2)
                      : Colors.white12,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasOtp ? Icons.shield_outlined : Icons.sms_outlined,
                  color: hasOtp ? LiquidGlassTheme.goldOtp : Colors.white70,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg.sender,
                  style: const TextStyle(
                    color: LiquidGlassTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _formatTimestamp(msg.timestamp),
                style: const TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (hasOtp) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text(
                    'OTP CODE:',
                    style: TextStyle(
                      color: LiquidGlassTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    msg.extractedOtp!,
                    style: const TextStyle(
                      color: LiquidGlassTheme.goldOtp,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _copyOtpToClipboard(msg.extractedOtp!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: LiquidGlassTheme.goldOtp,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.copy, color: Colors.black, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Copy',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            msg.body,
            style: const TextStyle(
              color: LiquidGlassTheme.textPrimary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min $ampm';
  }
}
