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

  void _openComposeSheet([String? initialRecipient]) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SmsComposeSheet(initialRecipient: initialRecipient),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Bank OTP & SMS'),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEFEFF4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit_square, color: LiquidGlassTheme.iosBlue, size: 18),
            ),
            tooltip: 'Compose SMS via Vivo SIM',
            onPressed: () => _openComposeSheet(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70),
        child: FloatingActionButton.extended(
          backgroundColor: LiquidGlassTheme.iosBlue,
          foregroundColor: Colors.white,
          elevation: 4,
          icon: const Icon(Icons.edit_note_rounded, size: 22),
          label: const Text(
            'Compose SMS',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2),
          ),
          onPressed: () => _openComposeSheet(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mark_chat_unread_outlined,
                        size: 54,
                        color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No SMS messages yet',
                        style: TextStyle(
                          color: LiquidGlassTheme.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap Compose SMS to send a message via Vivo S1',
                        style: TextStyle(
                          color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 140),
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
    final isOutgoing = msg.sender.startsWith('To:');
    final isDark = LiquidGlassTheme.isDarkMode;

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      color: hasOtp
          ? const Color(0x352A2410)
          : (isOutgoing
              ? (isDark ? const Color(0x250A4C2E) : const Color(0x1534C759))
              : LiquidGlassTheme.glassFill),
      border: hasOtp
          ? Border.all(color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.4), width: 1)
          : (isOutgoing
              ? Border.all(color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.3), width: 1)
              : null),
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
                      : (isOutgoing
                          ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.2)
                          : Colors.white12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasOtp
                      ? Icons.shield_outlined
                      : (isOutgoing ? Icons.arrow_outward_rounded : Icons.sms_outlined),
                  color: hasOtp
                      ? LiquidGlassTheme.goldOtp
                      : (isOutgoing ? LiquidGlassTheme.gsmGreen : Colors.white70),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.sender,
                      style: const TextStyle(
                        color: LiquidGlassTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isOutgoing) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.sim_card_outlined, size: 12, color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.8)),
                          const SizedBox(width: 4),
                          Text(
                            'Sent via Vivo S1 SIM',
                            style: TextStyle(
                              color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
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
          if (!isOutgoing && !hasOtp) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () => _openComposeSheet(msg.sender),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.reply_rounded, size: 14, color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.9)),
                      const SizedBox(width: 4),
                      const Text(
                        'Reply via Vivo SIM',
                        style: TextStyle(
                          color: LiquidGlassTheme.iosBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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

/// Apple Liquid Glass SMS Compose Sheet
class _SmsComposeSheet extends StatefulWidget {
  final String? initialRecipient;
  const _SmsComposeSheet({this.initialRecipient});

  @override
  State<_SmsComposeSheet> createState() => _SmsComposeSheetState();
}

class _SmsComposeSheetState extends State<_SmsComposeSheet> {
  late final TextEditingController _recipientController;
  final TextEditingController _bodyController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _recipientController = TextEditingController(text: widget.initialRecipient ?? '');
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final recipient = _recipientController.text.trim();
    final body = _bodyController.text.trim();
    if (recipient.isEmpty || body.isEmpty) return;

    setState(() => _isSending = true);
    HapticFeedback.mediumImpact();

    final ok = await RelayClient.instance.sendSms(recipient, body);
    if (mounted) {
      setState(() => _isSending = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(ok
                    ? 'SMS dispatched via Vivo S1 SIM to $recipient'
                    : 'Failed to dispatch SMS through Vivo SIM'),
              ),
            ],
          ),
          backgroundColor: ok ? LiquidGlassTheme.gsmGreen : const Color(0xFFFF3B30),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF0121218) : const Color(0xF0F8F8FC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New Message',
                    style: TextStyle(
                      color: LiquidGlassTheme.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: LiquidGlassTheme.gsmGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Dispatching via Vivo S1 Cellular SIM',
                        style: TextStyle(
                          color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                color: LiquidGlassTheme.textSecondary,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // To: Recipient field
          TextField(
            controller: _recipientController,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'To:',
              labelStyle: const TextStyle(color: LiquidGlassTheme.textSecondary, fontWeight: FontWeight.bold),
              hintText: 'Phone number or name',
              hintStyle: TextStyle(color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.5)),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Body text field
          TextField(
            controller: _bodyController,
            maxLines: 4,
            style: TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'iMessage / Cellular SMS message...',
              hintStyle: TextStyle(color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.5)),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Send Button
          ElevatedButton(
            onPressed: _isSending ? null : _handleSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: LiquidGlassTheme.gsmGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Send via Vivo SIM',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
