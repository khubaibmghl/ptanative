import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../services/native_audio_service.dart';
import '../theme/liquid_glass_theme.dart';
import '../widgets/contact_avatar_widget.dart';

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  List<CallLogModel> _logs = [];
  Map<String, String> _contactIdByNumber = {};
  bool _isLoading = true;
  StreamSubscription? _syncSub;

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
    _syncSub = RelayClient.instance.syncStream.listen((_) {
      _loadLogs();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final logs = await DatabaseHelper.instance.getCallLogs(missedOnly: false);
    final contacts = await DatabaseHelper.instance.getContacts();
    final Map<String, String> contactIdMap = {};
    final Map<String, String> contactNameMap = {};
    for (final c in contacts) {
      for (final p in c.phoneNumbers) {
        contactIdMap[p.normalizedNumber] = c.id;
        contactIdMap[p.rawNumber] = c.id;
        contactNameMap[p.normalizedNumber] = c.displayName;
        contactNameMap[p.rawNumber] = c.displayName;
      }
    }

    final resolvedLogs = logs.map((log) {
      if (log.callerName.isNotEmpty && log.callerName != log.remoteNumber) {
        return log;
      }
      final norm = PhoneNumberNormalizer.normalize(log.remoteNumber);
      final matchedName = contactNameMap[norm] ?? contactNameMap[log.remoteNumber];
      if (matchedName != null && matchedName.isNotEmpty) {
        return CallLogModel(
          id: log.id,
          remoteNumber: log.remoteNumber,
          callerName: matchedName,
          numberLabel: log.numberLabel,
          callType: log.callType,
          serviceType: log.serviceType,
          durationSeconds: log.durationSeconds,
          timestamp: log.timestamp,
        );
      }
      return log;
    }).toList();

    if (mounted) {
      setState(() {
        _logs = resolvedLogs;
        _contactIdByNumber = contactIdMap;
        _isLoading = false;
      });
    }
  }

  Color _getAvatarColor(String name) {
    if (name.isEmpty) return _avatarColors[0];
    final hash = name.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return _avatarColors[hash % _avatarColors.length];
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
    final contactId = _contactIdByNumber[PhoneNumberNormalizer.normalize(log.remoteNumber)] ?? _contactIdByNumber[log.remoteNumber];
    final avatarBgColor = _getAvatarColor(displayName);
    final isDark = LiquidGlassTheme.isDarkMode;

    final arrow = log.callType == CallType.outgoing ? '↗' : '↙';

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        RelayClient.instance.dialNumber(log.remoteNumber);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Left Initials / Profile Photo Avatar Streamed from Vivo S1
            ContactAvatarWidget(
              contactId: contactId,
              displayName: displayName,
              size: 44,
              fontSize: 16,
              backgroundColor: isMissed
                  ? const Color(0xFFFF3B30).withValues(alpha: 0.18)
                  : avatarBgColor,
              textColor: isMissed ? const Color(0xFFFF453A) : Colors.white,
              border: isMissed
                  ? Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.35), width: 1)
                  : null,
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
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        isMissed ? '↙ Missed' : '$arrow Zong GSM',
                        style: TextStyle(
                          color: isMissed ? const Color(0xFFFF453A) : LiquidGlassTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: isMissed ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isMissed) ...[
                        if (log.durationSeconds > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFFF3B30).withValues(alpha: 0.25),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.notifications_active_outlined,
                                  color: Color(0xFFFF453A),
                                  size: 11,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${log.durationSeconds}s',
                                  style: const TextStyle(
                                    color: Color(0xFFFF453A),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              'Missed',
                              style: TextStyle(
                                color: Color(0xFFFF453A),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            log.durationFormatted,
                            style: const TextStyle(
                              color: LiquidGlassTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
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
            const SizedBox(width: 8),

            // Native iOS (i) Info Button
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showCallDetailsSheet(context, log);
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.85),
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCallDetailsSheet(BuildContext context, CallLogModel log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CallDetailsSheet(log: log),
    );
  }
}

class CallDetailsSheet extends StatefulWidget {
  final CallLogModel log;

  const CallDetailsSheet({super.key, required this.log});

  @override
  State<CallDetailsSheet> createState() => _CallDetailsSheetState();
}

class _CallDetailsSheetState extends State<CallDetailsSheet> {
  List<CallRecordingModel>? _recordings;
  bool _isLoadingRecordings = true;
  String? _contactId;
  final Map<String, String> _localRecordingPaths = {};
  final Set<String> _downloadingFiles = {};

  @override
  void initState() {
    super.initState();
    _fetchRecordings();
  }

  @override
  void dispose() {
    NativeAudioService.instance.stop();
    super.dispose();
  }

  Future<void> _fetchRecordings() async {
    final contact = await DatabaseHelper.instance.findContactByNumber(widget.log.remoteNumber);
    if (mounted && contact != null) {
      _contactId = contact.id;
    }

    // 1. Instant load from local SQLite cache
    final local = await DatabaseHelper.instance.getLocalRecordings(number: widget.log.remoteNumber);
    if (mounted && local.isNotEmpty) {
      setState(() {
        _recordings = local;
        _isLoadingRecordings = false;
      });
      for (final rec in local) {
        if (rec.localPath != null && rec.localPath!.isNotEmpty) {
          _localRecordingPaths[rec.filename] = rec.localPath!;
        } else {
          RelayClient.instance.getLocalRecordingPath(rec.filename).then((p) {
            if (p != null && mounted) {
              setState(() => _localRecordingPaths[rec.filename] = p);
            }
          });
        }
      }
    }

    // 2. Query host/update cache
    var list = await RelayClient.instance.fetchRecordings(widget.log.remoteNumber);
    if (list.isEmpty) {
      // Fallback to latest 10 synced recordings across all calls
      list = await DatabaseHelper.instance.getLocalRecordings(limit: 10);
    }

    if (mounted) {
      setState(() {
        _recordings = list;
        _isLoadingRecordings = false;
      });
    }

    // Check which recordings already exist locally on iPhone
    for (final rec in list) {
      final localPath = await RelayClient.instance.getLocalRecordingPath(rec.filename);
      if (localPath != null && mounted) {
        setState(() {
          _localRecordingPaths[rec.filename] = localPath;
        });
      }
    }
  }

  Future<void> _togglePlayRecording(CallRecordingModel recording) async {
    if (_downloadingFiles.contains(recording.filename)) return;

    // Check if downloaded locally, if not download over network first
    String? localPath = _localRecordingPaths[recording.filename];
    if (localPath == null) {
      setState(() => _downloadingFiles.add(recording.filename));
      localPath = await RelayClient.instance.downloadRecordingAudio(recording.filename);
      if (mounted) {
        setState(() {
          _downloadingFiles.remove(recording.filename);
          if (localPath != null) {
            _localRecordingPaths[recording.filename] = localPath;
          }
        });
      }
    }

    if (localPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not download audio from Vivo host. Check hotspot/Wi-Fi connection.'),
            backgroundColor: Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final state = NativeAudioService.instance.currentState;
    if (state.activeUrl == localPath && state.isPlaying) {
      await NativeAudioService.instance.pause();
    } else if (state.activeUrl == localPath && !state.isPlaying) {
      await NativeAudioService.instance.resume();
    } else {
      await NativeAudioService.instance.play(localPath);
    }
  }

  Future<void> _shareRecording(CallRecordingModel recording) async {
    String? localPath = _localRecordingPaths[recording.filename];
    if (localPath == null) {
      setState(() => _downloadingFiles.add(recording.filename));
      localPath = await RelayClient.instance.downloadRecordingAudio(recording.filename);
      if (mounted) {
        setState(() {
          _downloadingFiles.remove(recording.filename);
          if (localPath != null) {
            _localRecordingPaths[recording.filename] = localPath;
          }
        });
      }
    }

    if (localPath != null) {
      await NativeAudioService.instance.shareFile(localPath);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not prepare file for sharing.'),
          backgroundColor: Color(0xFFFF3B30),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMissed = widget.log.callType == CallType.missed;
    final displayName = widget.log.callerName.isNotEmpty ? widget.log.callerName : widget.log.remoteNumber;
    final formattedNum = PhoneNumberNormalizer.formatForDisplay(widget.log.remoteNumber);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 36),
      decoration: const BoxDecoration(
        color: Color(0xF21C1C24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            ContactAvatarWidget(
              contactId: _contactId,
              displayName: displayName,
              size: 64,
              fontSize: 26,
            ),
            const SizedBox(height: 12),
            Text(
              displayName,
              style: TextStyle(
                color: isMissed ? const Color(0xFFFF3B30) : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formattedNum,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),

            // Call Overview Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    isMissed
                        ? Icons.phone_missed_rounded
                        : (widget.log.callType == CallType.outgoing
                            ? Icons.call_made_rounded
                            : Icons.call_received_rounded),
                    color: isMissed ? const Color(0xFFFF3B30) : LiquidGlassTheme.gsmGreen,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMissed
                              ? (widget.log.durationSeconds > 0
                                  ? 'Missed Call • ${widget.log.durationSeconds}s'
                                  : 'Missed Call')
                              : (widget.log.callType == CallType.outgoing
                                  ? 'Outgoing Call • ${widget.log.durationFormatted}'
                                  : 'Incoming Call • ${widget.log.durationFormatted}'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Recorded from Vivo S1 Host • ${widget.log.dateFormatted}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons (Call Back & Copy Number)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LiquidGlassTheme.gsmGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Call Back', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(context);
                      RelayClient.instance.dialNumber(widget.log.remoteNumber);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy Number'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.log.remoteNumber));
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied $formattedNum to clipboard'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            // Vivo Call Recordings Section
            const SizedBox(height: 22),
            Row(
              children: [
                const Icon(Icons.mic_none_rounded, color: LiquidGlassTheme.iosBlue, size: 17),
                const SizedBox(width: 6),
                const Text(
                  'Vivo S1 Call Recordings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                if (_isLoadingRecordings)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            if (_isLoadingRecordings)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: const Text('Scanning Vivo host storage...', style: TextStyle(color: Colors.white54, fontSize: 13)),
              )
            else if (_recordings == null || _recordings!.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.white38, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No recordings found for this contact on Vivo storage',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else
              StreamBuilder<AudioPlaybackState>(
                stream: NativeAudioService.instance.stateStream,
                initialData: NativeAudioService.instance.currentState,
                builder: (context, audioSnapshot) {
                  final audioState = audioSnapshot.data ?? const AudioPlaybackState();

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _recordings!.map((rec) {
                      final recUrl = RelayClient.instance.getRecordingAudioUrl(rec.filename);
                      final localPath = _localRecordingPaths[rec.filename];
                      final isDownloaded = localPath != null;
                      final isDownloading = _downloadingFiles.contains(rec.filename);
                      final isThisPlaying = (audioState.activeUrl == localPath || audioState.activeUrl == recUrl) && audioState.isPlaying;
                      final isThisActive = (audioState.activeUrl == localPath || audioState.activeUrl == recUrl);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isThisActive
                              ? LiquidGlassTheme.iosBlue.withValues(alpha: 0.14)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isThisActive
                                ? LiquidGlassTheme.iosBlue.withValues(alpha: 0.4)
                                : (isDownloaded ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.1)),
                            width: 0.75,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                // Play / Pause Circle Button
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _togglePlayRecording(rec);
                                  },
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isThisPlaying
                                          ? LiquidGlassTheme.iosBlue
                                          : (isDownloaded
                                              ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.25)
                                              : Colors.white.withValues(alpha: 0.16)),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: isDownloading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : Icon(
                                            isThisPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                            color: isDownloaded && !isThisPlaying ? LiquidGlassTheme.gsmGreen : Colors.white,
                                            size: 22,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              rec.dateFormatted,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: isDownloaded
                                                  ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.2)
                                                  : Colors.white.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isDownloaded
                                                    ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.4)
                                                    : Colors.white12,
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isDownloaded ? Icons.check_circle_rounded : Icons.cloud_download_outlined,
                                                  size: 10,
                                                  color: isDownloaded ? LiquidGlassTheme.gsmGreen : Colors.white70,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  isDownloaded ? 'iPhone Native File' : 'Vivo Host',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: isDownloaded ? LiquidGlassTheme.gsmGreen : Colors.white70,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${rec.filename} • ${rec.sizeFormatted}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.6),
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // Native iOS Share Button
                                IconButton(
                                  icon: Icon(
                                    Icons.share_rounded,
                                    color: isDownloaded ? LiquidGlassTheme.iosBlue : Colors.white70,
                                    size: 18,
                                  ),
                                  onPressed: () => _shareRecording(rec),
                                  tooltip: 'Share Native Audio File',
                                ),
                              ],
                            ),
                            if (isThisActive && audioState.duration > 0) ...[
                              const SizedBox(height: 8),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                  activeTrackColor: LiquidGlassTheme.iosBlue,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.white,
                                ),
                                child: Slider(
                                  value: audioState.progress,
                                  onChanged: (val) {
                                    final targetSec = val * audioState.duration;
                                    NativeAudioService.instance.seek(targetSec);
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(audioState.positionFormatted, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                    Text(audioState.durationFormatted, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
