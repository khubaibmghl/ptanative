import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../models/sms_thread_model.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';
import 'call_history_screen.dart';
import 'sms_thread_screen.dart';

class ContactDetailScreen extends StatefulWidget {
  final ContactModel? contact;
  final CallLogModel? initialLog;
  final String? rawNumber;
  final String? displayName;

  const ContactDetailScreen({
    super.key,
    this.contact,
    this.initialLog,
    this.rawNumber,
    this.displayName,
  });

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  ContactModel? _contact;
  List<PhoneNumberItem> _phoneNumbers = [];
  List<CallLogModel> _callLogs = [];
  String _displayName = '';
  bool _isLoading = true;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _initContactData();
  }

  Future<void> _initContactData() async {
    ContactModel? resolvedContact = widget.contact;
    final fallbackNumber = widget.rawNumber ?? widget.initialLog?.remoteNumber ?? '';

    // If contact not provided, attempt caller ID lookup in local database
    if (resolvedContact == null && fallbackNumber.isNotEmpty) {
      resolvedContact = await DatabaseHelper.instance.findContactByNumber(fallbackNumber);
    }

    if (resolvedContact != null) {
      _contact = resolvedContact;
      _displayName = resolvedContact.displayName;
      _phoneNumbers = List.from(resolvedContact.phoneNumbers);
      _isFavorite = resolvedContact.isFavorite;
    } else {
      _displayName = widget.displayName ?? widget.initialLog?.callerName ?? (fallbackNumber.isNotEmpty ? fallbackNumber : 'Unknown');
      if (fallbackNumber.isNotEmpty) {
        _phoneNumbers = [
          PhoneNumberItem(
            label: 'mobile',
            rawNumber: fallbackNumber,
            normalizedNumber: PhoneNumberNormalizer.normalize(fallbackNumber),
          ),
        ];
      }
    }

    // Query call logs for these phone numbers
    final numberStrings = _phoneNumbers.map((p) => p.rawNumber).toList();
    if (numberStrings.isEmpty && fallbackNumber.isNotEmpty) {
      numberStrings.add(fallbackNumber);
    }

    List<CallLogModel> logs = [];
    if (numberStrings.isNotEmpty) {
      logs = await DatabaseHelper.instance.getCallLogsForNumbers(numberStrings);
    }

    // If empty but initialLog was passed, use initialLog
    if (logs.isEmpty && widget.initialLog != null) {
      logs = [widget.initialLog!];
    }

    if (mounted) {
      setState(() {
        _callLogs = logs;
        _isLoading = false;
      });
    }
  }

  String get _initialLetter {
    if (_displayName.trim().isNotEmpty) {
      return _displayName.trim().characters.first.toUpperCase();
    }
    return '?';
  }

  String _formatRecentDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp > 1e11 ? timestamp : timestamp * 1000);
    final now = DateTime.now();
    final diffDays = DateTime(now.year, now.month, now.day).difference(DateTime(dt.year, dt.month, dt.day)).inDays;

    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$min $ampm';

    if (diffDays == 0) {
      return 'Today • $timeStr';
    } else if (diffDays == 1) {
      return 'Yesterday • $timeStr';
    } else {
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      return '$day/$month/${dt.year} • $timeStr';
    }
  }

  String _formatRecentDuration(CallLogModel log) {
    if (log.callType == CallType.missed) {
      return 'Missed';
    }
    if (log.durationSeconds == 0) {
      return 'Cancelled';
    }
    final m = log.durationSeconds ~/ 60;
    final s = log.durationSeconds % 60;
    if (m > 0 && s == 0) {
      return m == 1 ? '1 minute' : '$m minutes';
    } else if (m > 0) {
      final mStr = m == 1 ? '1 minute' : '$m minutes';
      final sStr = s == 1 ? '1 second' : '$s seconds';
      return '$mStr $sStr';
    } else {
      return s == 1 ? '1 second' : '$s seconds';
    }
  }

  void _callPrimaryNumber() {
    if (_phoneNumbers.isNotEmpty) {
      HapticFeedback.lightImpact();
      RelayClient.instance.dialNumber(_phoneNumbers.first.rawNumber);
    }
  }

  void _openMessageThread() {
    if (_phoneNumbers.isNotEmpty) {
      final primary = _phoneNumbers.first.rawNumber;
      final norm = PhoneNumberNormalizer.normalize(primary);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SmsThreadScreen(
            thread: SmsThreadModel(
              normalizedKey: norm,
              rawAddress: primary,
              displayName: _displayName != primary ? _displayName : primary,
              contactId: _contact?.id,
              messages: [],
            ),
          ),
        ),
      );
    }
  }

  void _startVideoCall() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.videocam_rounded, color: LiquidGlassTheme.iosBlue),
            const SizedBox(width: 8),
            Text('FaceTime Video calling $_displayName...'),
          ],
        ),
        backgroundColor: LiquidGlassTheme.surfaceDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sendEmail() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _displayName));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Contact info copied to clipboard'),
        backgroundColor: LiquidGlassTheme.surfaceDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openCallHistoryScreen() {
    HapticFeedback.selectionClick();
    final numbers = _phoneNumbers.map((p) => p.rawNumber).toList();
    if (numbers.isEmpty && widget.initialLog != null) {
      numbers.add(widget.initialLog!.remoteNumber);
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallHistoryScreen(
          displayName: _displayName,
          phoneNumbers: numbers,
          contactId: _contact?.id,
        ),
      ),
    );
  }

  void _shareContact() {
    HapticFeedback.lightImpact();
    final primary = _phoneNumbers.isNotEmpty ? _phoneNumbers.first.rawNumber : '';
    final cardText = 'Contact: $_displayName\nPhone: $primary';
    Clipboard.setData(ClipboardData(text: cardText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.share_rounded, color: LiquidGlassTheme.iosBlue),
            SizedBox(width: 8),
            Text('Contact card copied for sharing'),
          ],
        ),
        backgroundColor: LiquidGlassTheme.surfaceDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _toggleFavorite() {
    HapticFeedback.mediumImpact();
    setState(() => _isFavorite = !_isFavorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isFavorite ? 'Added to Favourites' : 'Removed from Favourites'),
        backgroundColor: LiquidGlassTheme.surfaceDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;
    final recentLog = _callLogs.isNotEmpty ? _callLogs.first : widget.initialLog;

    String recentCallTypeLabel = 'Outgoing Call';
    bool recentCallIsMissed = false;
    if (recentLog != null) {
      if (recentLog.callType == CallType.missed) {
        recentCallTypeLabel = 'Incoming Call';
        recentCallIsMissed = true;
      } else if (recentLog.callType == CallType.outgoing) {
        recentCallTypeLabel = 'Outgoing Call';
      } else {
        recentCallTypeLabel = 'Incoming Call';
      }
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF262238), Color(0xFF1B192A), Color(0xFF13111F)]
              : const [Color(0xFFF2F2F7), Color(0xFFE5E5EA)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
          centerTitle: true,
          title: Text(
            _displayName,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
                      width: 0.8,
                    ),
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
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  const SizedBox(height: 8),

                  // Large Circular Monogram Avatar (Matching Screenshot Image 2)
                  Center(
                    child: Container(
                      width: 124,
                      height: 124,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [const Color(0x357B74A8), const Color(0x184B466C)]
                              : [Colors.white.withValues(alpha: 0.7), Colors.white.withValues(alpha: 0.3)],
                        ),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.8),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x286B6396),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initialLetter,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF2C274A),
                          fontSize: 60,
                          fontWeight: FontWeight.w300,
                          fontFamily: '.SF Pro Text',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Contact Name under Avatar
                  Center(
                    child: Text(
                      _displayName,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 4 Circular Glass Action Buttons: Message, Call, Video, Mail
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildActionButton(Icons.chat_bubble_rounded, isDark, _openMessageThread),
                      const SizedBox(width: 16),
                      _buildActionButton(Icons.phone_rounded, isDark, _callPrimaryNumber),
                      const SizedBox(width: 16),
                      _buildActionButton(Icons.videocam_rounded, isDark, _startVideoCall),
                      const SizedBox(width: 16),
                      _buildActionButton(Icons.email_rounded, isDark, _sendEmail),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Card 1: Call History Section (Matching Screenshot Image 1)
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x28554E80) : Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Row 1: "Call History >"
                        InkWell(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                          onTap: _openCallHistoryScreen,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Call History',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black38,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                          height: 1,
                        ),
                        // Row 2: Most recent call
                        InkWell(
                          onTap: _openCallHistoryScreen,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      recentCallTypeLabel,
                                      style: TextStyle(
                                        color: recentCallIsMissed
                                            ? const Color(0xFFFF453A)
                                            : (isDark ? Colors.white : Colors.black87),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      recentLog != null ? _formatRecentDuration(recentLog) : '1 minute',
                                      style: TextStyle(
                                        color: isDark ? Colors.white54 : Colors.black45,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  recentLog != null ? _formatRecentDate(recentLog.timestamp) : 'Today • 6:44 PM',
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Card 2: Phone Numbers Card (Matching Screenshot Image 1)
                  if (_phoneNumbers.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0x28554E80) : Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        children: [
                          ..._phoneNumbers.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final phone = entry.value;
                            final isRecent = idx == 0;

                            return Column(
                              children: [
                                if (idx > 0)
                                  Divider(
                                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                                    height: 1,
                                  ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                phone.label.toLowerCase(),
                                                style: TextStyle(
                                                  color: isDark ? Colors.white60 : Colors.black54,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              if (isRecent) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.07),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'RECENT',
                                                    style: TextStyle(
                                                      color: isDark ? Colors.white : Colors.black87,
                                                      fontSize: 8.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            phone.rawNumber,
                                            style: TextStyle(
                                              color: isDark ? Colors.white : Colors.black87,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.phone_rounded,
                                          color: isDark ? Colors.white70 : Colors.black54,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          HapticFeedback.lightImpact();
                                          RelayClient.instance.dialNumber(phone.rawNumber);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),

                  // Card 3: Notes Card (Matching Screenshot Image 1)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x28554E80) : Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notes',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _contact?.note?.isNotEmpty == true ? _contact!.note! : '',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Card 4: Share / Actions Card (Matching Screenshot Image 1)
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x28554E80) : Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(
                            'Share Contact',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                          onTap: _shareContact,
                        ),
                        Divider(
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                          height: 1,
                        ),
                        ListTile(
                          title: Text(
                            _isFavorite ? 'Remove from Favourites' : 'Add to Favourites',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                          onTap: _toggleFavorite,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isDark ? const Color(0x356A6498) : const Color(0xFFD6D1EA),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        child: Icon(
          icon,
          color: isDark ? Colors.white : const Color(0xFF332E50),
          size: 22,
        ),
      ),
    );
  }
}
