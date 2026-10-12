import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../models/sms_thread_model.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';
import '../widgets/contact_avatar_widget.dart';
import 'sms_thread_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<SmsThreadModel> _threads = [];
  List<SmsThreadModel> _filteredThreads = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _smsSubscription;

  @override
  void initState() {
    super.initState();
    _loadThreads();

    _smsSubscription = RelayClient.instance.smsStream.listen((_) {
      _loadThreads();
    });
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadThreads() async {
    final messages = await DatabaseHelper.instance.getMessages();
    final contacts = await DatabaseHelper.instance.getContacts();

    // Group messages by contact / phone number
    final Map<String, List<SmsMessageModel>> grouped = {};
    final Map<String, String> rawAddresses = {};

    for (final msg in messages) {
      final clean = msg.sender.startsWith('To:') ? msg.sender.substring(3).trim() : msg.sender.trim();
      final norm = PhoneNumberNormalizer.normalize(clean);
      final key = norm.isNotEmpty ? norm : clean.toLowerCase();

      grouped.putIfAbsent(key, () => []).add(msg);
      rawAddresses.putIfAbsent(key, () => clean);
    }

    // Build thread models
    final List<SmsThreadModel> threadList = [];

    for (final entry in grouped.entries) {
      final key = entry.key;
      final msgs = entry.value;
      // Sort chronologically (oldest to newest for chat view)
      msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final rawAddr = rawAddresses[key] ?? key;
      String displayName = rawAddr;
      String? contactId;

      // Find matching contact in permanent SQLite contact list
      for (final c in contacts) {
        bool matches = false;
        for (final p in c.phoneNumbers) {
          if (PhoneNumberNormalizer.areMatching(p.rawNumber, rawAddr) ||
              PhoneNumberNormalizer.areMatching(p.normalizedNumber, rawAddr)) {
            matches = true;
            break;
          }
        }
        if (!matches && c.displayName.trim().toLowerCase() == rawAddr.trim().toLowerCase()) {
          matches = true;
        }

        if (matches) {
          displayName = c.displayName;
          contactId = c.id;
          break;
        }
      }

      if (contactId == null && PhoneNumberNormalizer.normalize(rawAddr).isNotEmpty) {
        displayName = PhoneNumberNormalizer.formatForDisplay(rawAddr);
      }

      threadList.add(SmsThreadModel(
        normalizedKey: key,
        rawAddress: rawAddr,
        displayName: displayName,
        contactId: contactId,
        messages: msgs,
      ));
    }

    // Sort threads by most recent message descending
    threadList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (mounted) {
      setState(() {
        _threads = threadList;
        _applyFilter();
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    if (_searchQuery.trim().isEmpty) {
      _filteredThreads = List.from(_threads);
    } else {
      final q = _searchQuery.trim().toLowerCase();
      _filteredThreads = _threads.where((t) {
        if (t.displayName.toLowerCase().contains(q)) return true;
        if (t.rawAddress.toLowerCase().contains(q)) return true;
        for (final m in t.messages) {
          if (m.body.toLowerCase().contains(q)) return true;
          if (m.extractedOtp != null && m.extractedOtp!.contains(q)) return true;
        }
        return false;
      }).toList();
    }
  }

  void _openThread(SmsThreadModel thread) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SmsThreadScreen(thread: thread),
      ),
    );
    _loadThreads();
  }

  void _openComposeSheet([String? initialRecipient]) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SmsComposeSheet(
        initialRecipient: initialRecipient,
        onDispatched: (recipient) {
          _loadThreads();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Messages'),
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
          : Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 15),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                          _applyFilter();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search conversations or messages...',
                        hintStyle: TextStyle(
                          color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: LiquidGlassTheme.textSecondary),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: LiquidGlassTheme.textSecondary),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _applyFilter();
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ),

                // Thread List
                Expanded(
                  child: _filteredThreads.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 54,
                                color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty ? 'No conversations found' : 'No SMS messages yet',
                                style: const TextStyle(
                                  color: LiquidGlassTheme.textSecondary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Try another search query'
                                    : 'Messages sent and received via Vivo S1 appear here',
                                style: TextStyle(
                                  color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.7),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 140),
                          itemCount: _filteredThreads.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final thread = _filteredThreads[index];
                            return _buildThreadCard(thread);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildThreadCard(SmsThreadModel thread) {
    final latest = thread.latestMessage;
    final isOutgoing = latest.sender.startsWith('To:');
    final hasOtp = thread.hasOtp;
    final unread = thread.unreadCount > 0;

    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => _openThread(thread),
      color: hasOtp
          ? const Color(0x352A2410)
          : (unread ? LiquidGlassTheme.iosBlue.withValues(alpha: 0.08) : LiquidGlassTheme.glassFill),
      border: hasOtp
          ? Border.all(color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.4), width: 1)
          : (unread
              ? Border.all(color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.35), width: 1)
              : null),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Monogram Contact Avatar
          ContactAvatarWidget(
            contactId: thread.contactId,
            displayName: thread.displayName,
            size: 48,
            fontSize: 20,
          ),
          const SizedBox(width: 12),

          // Thread Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Name / Address + Time
                Row(
                  children: [
                    if (isOutgoing) ...[
                      Icon(
                        Icons.arrow_outward_rounded,
                        size: 13,
                        color: LiquidGlassTheme.gsmGreen.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        thread.displayName,
                        style: TextStyle(
                          color: LiquidGlassTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(thread.timestamp),
                      style: TextStyle(
                        color: unread ? LiquidGlassTheme.iosBlue : LiquidGlassTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Row 2: Message preview snippet + Badges
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        latest.body,
                        style: TextStyle(
                          color: unread
                              ? LiquidGlassTheme.textPrimary
                              : LiquidGlassTheme.textSecondary.withValues(alpha: 0.8),
                          fontSize: 13.5,
                          fontWeight: unread ? FontWeight.w500 : FontWeight.normal,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // OTP badge
                    if (hasOtp) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.4), width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shield_outlined, color: LiquidGlassTheme.goldOtp, size: 10),
                            const SizedBox(width: 3),
                            Text(
                              thread.latestOtp ?? 'OTP',
                              style: const TextStyle(
                                color: LiquidGlassTheme.goldOtp,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],

                    // Message count pill
                    if (thread.messages.length > 1) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${thread.messages.length}',
                          style: const TextStyle(
                            color: LiquidGlassTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],

                    // Unread blue indicator dot
                    if (unread) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: LiquidGlassTheme.iosBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();

    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $ampm';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday';
    }

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

/// Apple Liquid Glass SMS Compose Sheet
class _SmsComposeSheet extends StatefulWidget {
  final String? initialRecipient;
  final ValueChanged<String>? onDispatched;

  const _SmsComposeSheet({
    this.initialRecipient,
    this.onDispatched,
  });

  @override
  State<_SmsComposeSheet> createState() => _SmsComposeSheetState();
}

class _SmsComposeSheetState extends State<_SmsComposeSheet> {
  late final TextEditingController _recipientController;
  final TextEditingController _bodyController = TextEditingController();
  bool _isSending = false;
  List<ContactModel> _contacts = [];
  List<ContactModel> _matchingContacts = [];

  @override
  void initState() {
    super.initState();
    _recipientController = TextEditingController(text: widget.initialRecipient ?? '');
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final list = await DatabaseHelper.instance.getContacts();
    if (mounted) {
      setState(() {
        _contacts = list;
      });
    }
  }

  void _onRecipientChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() => _matchingContacts = []);
      return;
    }
    final q = query.trim().toLowerCase();
    final matches = _contacts.where((c) {
      if (c.displayName.toLowerCase().contains(q)) return true;
      for (final p in c.phoneNumbers) {
        if (p.rawNumber.contains(q) || p.normalizedNumber.contains(q)) return true;
      }
      return false;
    }).take(4).toList();

    setState(() => _matchingContacts = matches);
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
      widget.onDispatched?.call(recipient);
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
                  const Text(
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
            onChanged: _onRecipientChanged,
            style: const TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'To:',
              labelStyle: const TextStyle(color: LiquidGlassTheme.textSecondary, fontWeight: FontWeight.bold),
              hintText: 'Phone number or contact name',
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

          // Contact suggestions dropdown
          if (_matchingContacts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF22222C) : const Color(0xFFEFEFF4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: _matchingContacts.map((c) {
                  final primaryNumber = c.phoneNumbers.isNotEmpty ? c.phoneNumbers.first.rawNumber : '';
                  return ListTile(
                    dense: true,
                    leading: ContactAvatarWidget(
                      contactId: c.id,
                      displayName: c.displayName,
                      size: 32,
                      fontSize: 13,
                    ),
                    title: Text(
                      c.displayName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      primaryNumber,
                      style: const TextStyle(fontSize: 12, color: LiquidGlassTheme.textSecondary),
                    ),
                    onTap: () {
                      _recipientController.text = primaryNumber;
                      setState(() => _matchingContacts = []);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Body text field
          TextField(
            controller: _bodyController,
            maxLines: 4,
            style: const TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 15),
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
