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
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Top Action Row: [Edit] capsule on Left, [≡] Filter circle on Right
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Native iOS [Edit] Pill Button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Edit',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  // Native iOS Filter Menu Circle Button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Large Bold "Messages" Title
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 10),
              child: Text(
                'Messages',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                ),
              ),
            ),

            // 3. Thread List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () async {
                        await RelayClient.instance.fetchMessages();
                        await _loadThreads();
                      },
                      child: _filteredThreads.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                                Center(
                                  child: Column(
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
                                            : 'Pull down to sync messages from Vivo S1',
                                        style: TextStyle(
                                          color: LiquidGlassTheme.textSecondary.withValues(alpha: 0.7),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(top: 0, bottom: 160),
                              itemCount: _filteredThreads.length,
                              separatorBuilder: (context, index) => Divider(
                                color: isDark ? Colors.white12 : const Color(0xFFE5E5EA),
                                height: 1,
                                indent: 76,
                              ),
                              itemBuilder: (context, index) {
                                final thread = _filteredThreads[index];
                                return _buildThreadCard(thread);
                              },
                            ),
                    ),
            ),

            // 4. Native iOS Bottom Floating Search & Compose Bar
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 94, top: 4),
              child: Row(
                children: [
                  // Pill Search Input Capsule
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFEFEFF4),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 20, color: Color(0xFF8E8E93)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 15,
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val;
                                  _applyFilter();
                                });
                              },
                              decoration: const InputDecoration(
                                hintText: 'Search',
                                hintStyle: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 15,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _applyFilter();
                                });
                              },
                              child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF8E8E93)),
                            )
                          else
                            const Icon(Icons.mic_rounded, size: 20, color: Color(0xFF8E8E93)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Native iOS Compose Circle Button [📝]
                  GestureDetector(
                    onTap: () => _openComposeSheet(),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFEFEFF4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit_square,
                        size: 20,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadCard(SmsThreadModel thread) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final latest = thread.latestMessage;
    final hasOtp = thread.hasOtp;
    final unread = thread.unreadCount > 0;
    final initials = _getInitials(thread.displayName);

    return InkWell(
      onTap: () => _openThread(thread),
      splashColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
      highlightColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.02),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // iOS unread indicator dot (left of avatar if unread)
            if (unread) ...[
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF007AFF),
                  shape: BoxShape.circle,
                ),
              ),
            ],

            // iOS Slate Blue Avatar (Letter Initials or Person Silhouette)
            Container(
              width: 48,
              height: 48,
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
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    )
                  : const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 28,
                    ),
            ),
            const SizedBox(width: 12),

            // Content: Display Name + Date + Chevron, and 2-line preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Name / Number and Date >
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.displayName,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatIosDate(thread.timestamp),
                        style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Color(0xFFC7C7CC),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // Row 2: 2-line Message snippet & OTP chip if detected
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          latest.body,
                          style: TextStyle(
                            color: isDark ? const Color(0xFF98989E) : const Color(0xFF8E8E93),
                            fontSize: 14,
                            height: 1.25,
                            fontWeight: unread ? FontWeight.w500 : FontWeight.normal,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasOtp) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: LiquidGlassTheme.goldOtp.withValues(alpha: 0.4),
                              width: 0.5,
                            ),
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
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '';
    // If it's a numeric phone number or shortcode (e.g. 9771, 2300, 8901), return ''
    if (RegExp(r'^[+\d\s\-\(\)]+$').hasMatch(clean)) return '';
    // If it has hyphens or resembles service short name like Zong-OR, return ''
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

  String _formatIosDate(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();

    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $ampm';
    }

    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
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
