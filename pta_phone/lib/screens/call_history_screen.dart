import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../services/native_audio_service.dart';
import '../theme/liquid_glass_theme.dart';

class CallHistoryScreen extends StatefulWidget {
  final String displayName;
  final List<String> phoneNumbers;
  final String? contactId;

  const CallHistoryScreen({
    super.key,
    required this.displayName,
    required this.phoneNumbers,
    this.contactId,
  });

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallLogModel> _logs = [];
  List<CallRecordingModel> _recordings = [];
  bool _isLoading = true;
  final Map<String, String> _localRecordingPaths = {};
  final Set<String> _downloadingFiles = {};
  String? _requestedDownloadFilename;
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _syncSub = RelayClient.instance.syncStream.listen((_) {
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    NativeAudioService.instance.stop();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    // 1. Fetch all call logs for this contact
    final logs = await DatabaseHelper.instance.getCallLogsForContact(
      rawNumbers: widget.phoneNumbers,
      displayName: widget.displayName,
    );

    // 2. Fetch all recordings for this contact / numbers strictly
    final localRecs = await DatabaseHelper.instance.getLocalRecordings(
      numbers: widget.phoneNumbers,
      name: widget.displayName,
      limit: 50,
    );

    // Sort newest to oldest
    localRecs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (mounted) {
      setState(() {
        _logs = logs;
        _recordings = localRecs;
        _isLoading = false;
      });
    }

    // Resolve local disk paths for cached recordings
    for (final rec in localRecs) {
      if (rec.localPath != null && rec.localPath!.isNotEmpty && File(rec.localPath!).existsSync()) {
        _localRecordingPaths[rec.filename] = rec.localPath!;
      } else {
        RelayClient.instance.getLocalRecordingPath(rec.filename).then((path) {
          if (path != null && mounted) {
            setState(() => _localRecordingPaths[rec.filename] = path);
          }
        });
      }
    }

    // 3. Query host in background if connected
    final primaryNumber = widget.phoneNumbers.isNotEmpty ? widget.phoneNumbers.first : '';
    if (RelayClient.instance.isConnected && primaryNumber.isNotEmpty) {
      final remoteRecs = await RelayClient.instance.fetchRecordings(
        primaryNumber,
        contactName: widget.displayName,
      );
      if (mounted && remoteRecs.isNotEmpty) {
        // Double filter remote recordings so ONLY this contact's recordings can ever be added
        final filteredRemote = remoteRecs.where((r) {
          final norm = PhoneNumberNormalizer.normalize(r.remoteNumber);
          final numMatch = widget.phoneNumbers.any((n) {
            final sig = PhoneNumberNormalizer.normalize(n);
            return sig.isNotEmpty && (norm.contains(sig) || sig.contains(norm));
          });
          final rName = r.callerName?.toLowerCase() ?? '';
          final nameMatch = widget.displayName.trim().isNotEmpty && rName.isNotEmpty &&
              (rName.contains(widget.displayName.toLowerCase()) ||
               widget.displayName.toLowerCase().contains(rName));
          return numMatch || nameMatch;
        }).toList();

        setState(() {
          final filenames = _recordings.map((r) => r.filename).toSet();
          for (final r in filteredRemote) {
            if (!filenames.contains(r.filename)) {
              _recordings.add(r);
            }
          }
          _recordings.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        });
      }
    }
  }

  CallRecordingModel? _findMatchingRecording(CallLogModel log) {
    if (_recordings.isEmpty) return null;

    CallRecordingModel? bestMatch;
    int smallestDiff = 300000; // max 5 minutes window

    for (final rec in _recordings) {
      final diff = (rec.timestamp - log.timestamp).abs();
      if (diff < smallestDiff) {
        if (log.durationSeconds > 0 && rec.durationSeconds > 0) {
          if ((rec.durationSeconds - log.durationSeconds).abs() <= 5) {
            smallestDiff = diff;
            bestMatch = rec;
          } else if (diff < 60000) {
            smallestDiff = diff;
            bestMatch = rec;
          }
        } else if (diff < 120000) {
          smallestDiff = diff;
          bestMatch = rec;
        }
      }
    }
    return bestMatch;
  }

  Future<void> _togglePlayRecording(CallRecordingModel recording) async {
    final filename = recording.filename;
    final state = NativeAudioService.instance.currentState;
    String? localPath = _localRecordingPaths[filename];

    // If this exact recording is currently active and playing -> pause
    if (state.activeUrl != null && state.activeUrl == localPath && state.isPlaying) {
      await NativeAudioService.instance.pause();
      return;
    }

    // If this exact recording is currently paused -> resume
    if (state.activeUrl != null && state.activeUrl == localPath && !state.isPlaying) {
      await NativeAudioService.instance.resume();
      return;
    }

    // Otherwise, user wants to play a new clip.
    // Stop any existing audio immediately to prevent overlap!
    await NativeAudioService.instance.stop();

    _requestedDownloadFilename = filename;

    if (localPath == null || !File(localPath).existsSync()) {
      setState(() => _downloadingFiles.add(filename));
      localPath = await RelayClient.instance.downloadRecordingAudio(filename);
      if (mounted) {
        setState(() {
          _downloadingFiles.remove(filename);
          if (localPath != null) {
            _localRecordingPaths[filename] = localPath;
          }
        });
      }
    }

    // If user tapped a different clip while this was downloading, do NOT play it
    if (_requestedDownloadFilename != filename) {
      return;
    }

    if (localPath == null || !File(localPath).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not download audio from host. Check hotspot/Wi-Fi connection.'),
            backgroundColor: Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    await NativeAudioService.instance.play(localPath);
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
          content: Text('Could not prepare audio file for sharing.'),
          backgroundColor: Color(0xFFFF3B30),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatDate(int timestamp) {
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

  String _formatDuration(CallLogModel log) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

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
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.displayName,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                'Call History',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty && _recordings.isEmpty
                ? Center(
                    child: Text(
                      'No call history available',
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      // Native Call History Glass Card (Matching Screenshot Image 3)
                      if (_logs.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0x28554E80) : Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                              width: 0.8,
                            ),
                          ),
                          child: Column(
                            children: [
                              ..._logs.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final log = entry.value;
                                final isMissed = log.callType == CallType.missed;
                                final matchingRecording = _findMatchingRecording(log);

                                String callTypeTitle;
                                if (isMissed) {
                                  callTypeTitle = 'Incoming Call';
                                } else if (log.callType == CallType.outgoing) {
                                  callTypeTitle = 'Outgoing Call';
                                } else {
                                  callTypeTitle = 'Incoming Call';
                                }

                                return Column(
                                  children: [
                                    if (idx > 0)
                                      Divider(
                                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                                        height: 1,
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Top Row: Call Type (Left) & Date/Time (Right)
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                callTypeTitle,
                                                style: TextStyle(
                                                  color: isMissed
                                                      ? const Color(0xFFFF453A)
                                                      : (isDark ? Colors.white : Colors.black87),
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                              Text(
                                                _formatDate(log.timestamp),
                                                style: TextStyle(
                                                  color: isDark ? Colors.white70 : Colors.black54,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          // Bottom Row: Duration
                                          Row(
                                            children: [
                                              Text(
                                                _formatDuration(log),
                                                style: TextStyle(
                                                  color: isDark ? Colors.white54 : Colors.black45,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              if (matchingRecording != null) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.16),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.3),
                                                      width: 0.6,
                                                    ),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.mic_rounded, size: 10, color: LiquidGlassTheme.iosBlue),
                                                      SizedBox(width: 3),
                                                      Text(
                                                        'RECORDED',
                                                        style: TextStyle(
                                                          fontSize: 8.5,
                                                          fontWeight: FontWeight.w700,
                                                          color: LiquidGlassTheme.iosBlue,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),

                                          // Attached Audio Player for this Call Log
                                          if (matchingRecording != null) ...[
                                            const SizedBox(height: 10),
                                            _buildInlineRecordingPlayer(matchingRecording, isDark),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),

                      // If there are additional recordings that did not match an exact call log timestamp
                      Builder(
                        builder: (context) {
                          final matchedFilenames = <String>{};
                          for (final log in _logs) {
                            final rec = _findMatchingRecording(log);
                            if (rec != null) matchedFilenames.add(rec.filename);
                          }
                          final unmatchedRecordings = _recordings.where((r) => !matchedFilenames.contains(r.filename)).toList();

                          if (unmatchedRecordings.isEmpty) return const SizedBox.shrink();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 22),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.mic_rounded, size: 14, color: LiquidGlassTheme.iosBlue),
                                    const SizedBox(width: 6),
                                    Text(
                                      'ADDITIONAL RECORDINGS (${widget.displayName.toUpperCase()})',
                                      style: TextStyle(
                                        color: isDark ? Colors.white60 : Colors.black54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0x28554E80) : Colors.white.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                                    width: 0.8,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    ...unmatchedRecordings.asMap().entries.map((entry) {
                                      final idx = entry.key;
                                      final rec = entry.value;

                                      return Column(
                                        children: [
                                          if (idx > 0)
                                            Divider(
                                              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                                              height: 1,
                                            ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            child: _buildInlineRecordingPlayer(rec, isDark),
                                          ),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
      ),
    );
  }

  Widget _buildInlineRecordingPlayer(CallRecordingModel rec, bool isDark) {
    return StreamBuilder<AudioPlaybackState>(
      stream: NativeAudioService.instance.stateStream,
      initialData: NativeAudioService.instance.currentState,
      builder: (context, snapshot) {
        final audioState = snapshot.data ?? const AudioPlaybackState();
        final localPath = _localRecordingPaths[rec.filename];
        final isDownloaded = localPath != null;
        final isDownloading = _downloadingFiles.contains(rec.filename);
        final recUrl = RelayClient.instance.getRecordingAudioUrl(rec.filename);
        final isThisActive = (audioState.activeUrl == localPath || audioState.activeUrl == recUrl);
        final isThisPlaying = isThisActive && audioState.isPlaying;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isThisActive
                ? LiquidGlassTheme.iosBlue.withValues(alpha: 0.14)
                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isThisActive
                  ? LiquidGlassTheme.iosBlue.withValues(alpha: 0.35)
                  : (isDownloaded ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08)),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Play/Pause Circular Glass Button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _togglePlayRecording(rec);
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isThisPlaying
                            ? LiquidGlassTheme.iosBlue
                            : (isDownloaded
                                ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.22)
                                : (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08))),
                        shape: BoxShape.circle,
                        boxShadow: isThisPlaying
                            ? [
                                BoxShadow(
                                  color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
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
                              size: 24,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Recording metadata & source pill
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                rec.dateFormatted,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: (isDownloaded ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.iosBlue)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isDownloaded ? Icons.check_circle_rounded : Icons.cloud_download_outlined,
                                    size: 9,
                                    color: isDownloaded ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.iosBlue,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    isDownloaded ? 'iPhone Cached' : 'Vivo Host',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isDownloaded ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.iosBlue,
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
                            color: isDark ? Colors.white54 : Colors.black45,
                            fontSize: 11,
                            fontFamily: 'monospace',
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
                      color: isDownloaded ? LiquidGlassTheme.iosBlue : (isDark ? Colors.white70 : Colors.black54),
                      size: 19,
                    ),
                    onPressed: () => _shareRecording(rec),
                    tooltip: 'Share Recording File',
                  ),
                ],
              ),
              // Scrubber and Audio Timestamps if Active
              if (isThisActive && audioState.duration > 0) ...[
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: LiquidGlassTheme.iosBlue,
                    inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
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
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        audioState.positionFormatted,
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 10),
                      ),
                      Text(
                        audioState.durationFormatted,
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
