import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  List<CallLogModel> _logs = [];
  bool _isLoading = true;

  final List<Color> _avatarColors = const [
    Color(0xFF7A8DBE),
    Color(0xFF8B7ABE),
    Color(0xFFBE7A93),
    Color(0xFF5A9B8D),
    Color(0xFFB57ABE),
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final logs = await DatabaseHelper.instance.getCallLogs(missedOnly: false);
    if (mounted) {
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    }
  }

  Color _getAvatarColor(String name) {
    if (name.isEmpty) return _avatarColors[0];
    final hash = name.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return _avatarColors[hash % _avatarColors.length];
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 10, bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEFEFF4),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Edit',
              style: TextStyle(
                color: LiquidGlassTheme.iosBlue,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        title: Text(
          'Calls',
          style: TextStyle(
            color: LiquidGlassTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEFEFF4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.filter_list, color: LiquidGlassTheme.textPrimary, size: 20),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await RelayClient.instance.fetchHistory();
          await _loadLogs();
        },
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
                ? const Center(
                    child: Text(
                      'No recent calls',
                      style: TextStyle(color: LiquidGlassTheme.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(top: 8, bottom: 100),
                    itemCount: _logs.length,
                    separatorBuilder: (context, index) => Divider(
                      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                      height: 1,
                      indent: 68,
                    ),
                    itemBuilder: (context, index) {
                      final item = _logs[index];
                      return _buildCallLogItem(item);
                    },
                  ),
      ),
    );
  }

  Widget _buildCallLogItem(CallLogModel log) {
    final isMissed = log.callType == CallType.missed;
    final displayName = log.callerName.isNotEmpty ? log.callerName : log.remoteNumber;
    final initials = _getInitials(displayName);
    final avatarBgColor = _getAvatarColor(displayName);

    final arrow = log.callType == CallType.outgoing ? '↗' : '↙';
    final durString = isMissed
        ? 'Missed'
        : (log.durationSeconds > 0
            ? '${(log.durationSeconds ~/ 60).toString().padLeft(2, '0')}:${(log.durationSeconds % 60).toString().padLeft(2, '0')}'
            : '00:00');

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        RelayClient.instance.dialNumber(log.remoteNumber);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Left Initials Avatar Circle
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: avatarBgColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Caller Name & Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      color: isMissed ? const Color(0xFFFF3B30) : LiquidGlassTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '$arrow Zong GSM',
                        style: const TextStyle(
                          color: LiquidGlassTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          durString,
                          style: const TextStyle(
                            color: LiquidGlassTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Time Label
            Text(
              log.dateFormatted,
              style: const TextStyle(
                color: LiquidGlassTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 12),

            // Redial Blue Circular Phone Icon Button
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                RelayClient.instance.dialNumber(log.remoteNumber);
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F1FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.phone,
                  color: LiquidGlassTheme.iosBlue,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
