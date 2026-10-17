import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/database_helper.dart';
import '../models/sms_thread_model.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';

/// Pixel-perfect iOS Native SMS Thread Conversation Screen matching Image 2 & 3
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
  bool _hasInputText = false;

  @override
  void initState() {
    super.initState();
    _messages = List.from(widget.thread.messages);
    _markThreadAsRead();

    _replyController.addListener(() {
      final hasText = _replyController.text.trim().isNotEmpty;
      if (hasText != _hasInputText) {
        setState(() {
          _hasInputText = hasText;
        });
      }
    });

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

  Future<void> _openUrl(String url) async {
    try {
      var uriStr = url.trim();
      if (!uriStr.startsWith('http://') && !uriStr.startsWith('https://')) {
        uriStr = 'https://$uriStr';
      }
      final uri = Uri.parse(uriStr);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '';
    if (RegExp(r'^[+\d\s\-\(\)]+$').hasMatch(clean)) return '';
    if (clean.contains('-') || clean.contains('_')) return '';

    final words = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2) {
      final firstLetter = words[0][0].toUpperCase();
      final secondLetter = words[1][0].toUpperCase();
      return '$firstLetter$secondLetter';
    } else if (words.isNotEmpty) {
      return words[0][0].toUpperCase();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initials = _getInitials(widget.thread.displayName);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(88),
        child: SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white10 : const Color(0xFFF2F2F7),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                // 1. Native Circular Back Button (<)
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      border: Border.all(
                        color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 28,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),

                // 2. Centered Avatar + Capsule Pill (matching Image 2 & 3)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // iOS Slate Blue Avatar
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFF8A9BB8),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: initials.isNotEmpty
                            ? Text(
                                initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 28,
                              ),
                      ),
                      const SizedBox(height: 3),

                      // iOS Pill Capsule: [ 9771 ❯ ] or [ 4263 ❯ ]
                      GestureDetector(
                        onTap: _dialContact,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.thread.displayName,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 14,
                                color: Color(0xFF8E8E93),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Placeholder to balance back button width
                const SizedBox(width: 42),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Message Bubbles List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isOutgoing = msg.sender.startsWith('To:');
                final isFirst = index == 0;
                final showDateHeader = isFirst || !_isSameDay(_messages[index - 1].timestamp, msg.timestamp);

                return Column(
                  children: [
                    if (isFirst) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Text Message • SMS',
                        style: TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatIosTimestampHeader(msg.timestamp),
                        style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ] else if (showDateHeader) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          _formatIosTimestampHeader(msg.timestamp),
                          style: const TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                    _buildMessageBubble(msg, isOutgoing, isDark),
                  ],
                );
              },
            ),
          ),

          // Bottom Native iOS SMS Input Bar (matching Image 2 & 3)
          Container(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : const Color(0xFFE5E5EA),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left Native iOS (+) Circle Button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.add,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Pill Text Message Input Capsule with Audio Waveform / Green Send Button
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 38),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? Colors.white24 : const Color(0xFFE5E5EA),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.only(left: 14, right: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyController,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 15,
                              ),
                              maxLines: 4,
                              minLines: 1,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _handleSend(),
                              decoration: const InputDecoration(
                                hintText: 'Text Message • SMS',
                                hintStyle: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 14.5,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Right Icon: Audio Waveform icon when empty, or Green Upward Send Pill when text entered
                          if (_hasInputText)
                            GestureDetector(
                              onTap: _isSending ? null : _handleSend,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34C759),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: _isSending
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.arrow_upward_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                              ),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.graphic_eq_rounded,
                                color: Color(0xFF8E8E93),
                                size: 20,
                              ),
                            ),
                        ],
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

  Widget _buildMessageBubble(SmsMessageModel msg, bool isOutgoing, bool isDark) {
    final hasOtp = msg.extractedOtp != null && msg.extractedOtp!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: isOutgoing
                ? const Color(0xFF34C759) // Exact Apple SMS Green
                : (isDark ? const Color(0xFF26252A) : const Color(0xFFE9E9EB)), // Exact Apple SMS Grey
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isOutgoing ? 18 : 4),
              bottomRight: Radius.circular(isOutgoing ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // OTP Banner inside bubble if detected
              if (hasOtp) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_rounded, color: LiquidGlassTheme.goldOtp, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        msg.extractedOtp!,
                        style: const TextStyle(
                          color: LiquidGlassTheme.goldOtp,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _copyOtpToClipboard(msg.extractedOtp!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: LiquidGlassTheme.goldOtp,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Copy',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Message Body with Clickable Blue Links matching Image 3
              _buildRichMessageText(msg.body, isOutgoing, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRichMessageText(String body, bool isOutgoing, bool isDark) {
    final urlRegex = RegExp(r'(https?://[^\s]+|www\.[^\s]+|[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}(?:/[^\s]*)?)');
    final matches = urlRegex.allMatches(body);

    if (matches.isEmpty) {
      return Text(
        body,
        style: TextStyle(
          color: isOutgoing ? Colors.white : (isDark ? Colors.white : Colors.black),
          fontSize: 15.5,
          height: 1.3,
        ),
      );
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: body.substring(lastEnd, match.start),
          style: TextStyle(
            color: isOutgoing ? Colors.white : (isDark ? Colors.white : Colors.black),
            fontSize: 15.5,
            height: 1.3,
          ),
        ));
      }

      final urlText = match.group(0)!;
      spans.add(TextSpan(
        text: urlText,
        style: TextStyle(
          color: isOutgoing ? Colors.white : const Color(0xFF007AFF),
          decoration: TextDecoration.underline,
          decorationColor: isOutgoing ? Colors.white70 : const Color(0xFF007AFF),
          fontSize: 15.5,
          height: 1.3,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _openUrl(urlText),
      ));

      lastEnd = match.end;
    }

    if (lastEnd < body.length) {
      spans.add(TextSpan(
        text: body.substring(lastEnd),
        style: TextStyle(
          color: isOutgoing ? Colors.white : (isDark ? Colors.white : Colors.black),
          fontSize: 15.5,
          height: 1.3,
        ),
      ));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }

  bool _isSameDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  String _formatIosTimestampHeader(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekday = days[dt.weekday - 1];
    final month = months[dt.month - 1];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$weekday, ${dt.day} $month at $hour:$min $ampm';
  }
}
