import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../models/sms_thread_model.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';
import '../widgets/contact_avatar_widget.dart';

class SmsThreadScreen extends StatefulWidget {
  final SmsThreadModel thread;

  const SmsThreadScreen({
    super.key,
    required this.thread,
  });

  @override
  State<SmsThreadScreen> createState() => _SmsThreadScreenState();
}

class _SmsThreadScreenState extends State<SmsThreadScreen> {
  late final List<SmsMessageModel> _messages;
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _smsSubscription;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _messages = List.from(widget.thread.messages);
    _markThreadAsRead();

    // Listen for incoming SMS messages in real-time
    _smsSubscription = RelayClient.instance.smsStream.listen((newMsg) {
      final clean = newMsg.sender.startsWith('To:') ? newMsg.sender.substring(3).trim() : newMsg.sender.trim();
      final norm = PhoneNumberNormalizer.normalize(clean);
      final key = norm.isNotEmpty ? norm : clean.toLowerCase();

      if (key == widget.thread.normalizedKey || PhoneNumberNormalizer.areMatching(clean, widget.thread.rawAddress)) {
        if (mounted) {
          setState(() {
            _messages.add(newMsg);
          });
          DatabaseHelper.instance.markMessageRead(newMsg.id);
          _scrollToBottom();
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animated: false);
    });
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markThreadAsRead() async {
    await DatabaseHelper.instance.markThreadRead(widget.thread.rawAddress);
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent + 80;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutQuad,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _handleSend() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    HapticFeedback.lightImpact();

    final ok = await RelayClient.instance.sendSms(widget.thread.rawAddress, text);

    if (mounted) {
      setState(() => _isSending = false);
      if (ok) {
        final outgoing = SmsMessageModel(
          id: DateTime.now().millisecondsSinceEpoch,
          sender: 'To: ${widget.thread.rawAddress}',
          body: text,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isRead: true,
        );
        setState(() {
          _messages.add(outgoing);
          _replyController.clear();
        });
        _scrollToBottom();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to dispatch SMS via Vivo SIM'),
            backgroundColor: Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _copyOtpToClipboard(String otp) {
    Clipboard.setData(ClipboardData(text: otp));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.shield_outlined, color: LiquidGlassTheme.goldOtp, size: 18),
            const SizedBox(width: 8),
            Text('OTP $otp copied to clipboard!'),
          ],
        ),
        backgroundColor: const Color(0xE61C1C24),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _dialContact() {
    HapticFeedback.mediumImpact();
    RelayClient.instance.dialNumber(widget.thread.rawAddress);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            ContactAvatarWidget(
              contactId: widget.thread.contactId,
              displayName: widget.thread.displayName,
              size: 38,
              fontSize: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.thread.displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: LiquidGlassTheme.gsmGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Vivo S1 SIM • Cellular',
                        style: TextStyle(
                          color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phone_rounded, color: LiquidGlassTheme.gsmGreen, size: 18),
            ),
            tooltip: 'Call via Vivo SIM',
            onPressed: _dialContact,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Message Bubbles List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isOutgoing = msg.sender.startsWith('To:');
                final showDateHeader = index == 0 || !_isSameDay(_messages[index - 1].timestamp, msg.timestamp);

                return Column(
                  children: [
                    if (showDateHeader) _buildDateHeader(msg.timestamp),
                    _buildMessageBubble(msg, isOutgoing),
                  ],
                );
              },
            ),
          ),

          // Bottom Reply Input Bar (iMessage style)
          Container(
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              top: 10,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xEB1A1A22) : const Color(0xEBFFFFFF),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black12,
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF0F0F4),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                          width: 0.5,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _replyController,
                        style: TextStyle(
                          color: LiquidGlassTheme.textPrimary,
                          fontSize: 15,
                        ),
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleSend(),
                        decoration: InputDecoration(
                          hintText: 'Text Message • Vivo SIM',
                          hintStyle: TextStyle(
                            color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.55),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isSending ? null : _handleSend,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: LiquidGlassTheme.gsmGreen,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(int timestamp) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _formatDateHeader(timestamp),
            style: const TextStyle(
              color: LiquidGlassTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(SmsMessageModel msg, bool isOutgoing) {
    final hasOtp = msg.extractedOtp != null && msg.extractedOtp!.isNotEmpty;
    final isDark = LiquidGlassTheme.isDarkMode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isOutgoing
                ? LiquidGlassTheme.gsmGreen
                : (hasOtp
                    ? const Color(0x352A2410)
                    : (isDark ? const Color(0x402C2C34) : const Color(0xFFE5E5EA))),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isOutgoing ? 18 : 4),
              bottomRight: Radius.circular(isOutgoing ? 4 : 18),
            ),
            border: hasOtp
                ? Border.all(color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.5), width: 1)
                : Border.all(
                    color: isOutgoing
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
          ),
          child: Column(
            crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // OTP Banner inside bubble
              if (hasOtp) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_rounded, color: LiquidGlassTheme.goldOtp, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        msg.extractedOtp!,
                        style: const TextStyle(
                          color: LiquidGlassTheme.goldOtp,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _copyOtpToClipboard(msg.extractedOtp!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: LiquidGlassTheme.goldOtp,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy, color: Colors.black, size: 11),
                              SizedBox(width: 3),
                              Text(
                                'Copy',
                                style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Message Body
              Text(
                msg.body,
                style: TextStyle(
                  color: isOutgoing ? Colors.white : (isDark ? Colors.white : Colors.black87),
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),

              // Timestamp & Outgoing SIM label
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOutgoing) ...[
                    Icon(
                      Icons.sim_card_outlined,
                      size: 10,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    _formatTime(msg.timestamp),
                    style: TextStyle(
                      color: isOutgoing
                          ? Colors.white.withValues(alpha: 0.8)
                          : LiquidGlassTheme.textSecondary.withValues(alpha: 0.7),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSameDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  String _formatDateHeader(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday';
    }
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min $ampm';
  }
}
