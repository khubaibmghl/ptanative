import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pta_shared/pta_shared.dart';

/// High-performance scanner & indexer for Vivo S1 (Funtouch OS / OriginOS) call recordings.
/// Supports 6,000+ files with in-memory caching and instant regex parsing.
class VivoRecordingService {
  static final VivoRecordingService instance = VivoRecordingService._init();
  VivoRecordingService._init();

  static const List<String> candidatePaths = [
    '/storage/emulated/0/Recordings/Record/Call',
    '/sdcard/Recordings/Record/Call',
    '/storage/emulated/0/Record/Call',
    '/sdcard/Record/Call',
    '/storage/emulated/0/Recordings/Record/Record_old/Call',
    '/sdcard/Recordings/Record/Record_old/Call',
    '/storage/emulated/0/Recordings/Call',
    '/sdcard/Recordings/Call',
    '/storage/emulated/0/Recorder/Call',
    '/sdcard/Recorder/Call',
    '/storage/emulated/0/Record',
    '/storage/emulated/0/Recordings',
    '/storage/emulated/0/Sounds/Call',
    '/storage/emulated/0/Sounds',
    '/storage/emulated/0/Music/Record/Call',
  ];

  static const Set<String> validExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.amr',
    '.wav',
    '.ogg',
  };

  // Standard Vivo call recording regex:
  // e.g. "Prof Attique GGCP 2026-10-17 11-17-19.m4a" or "03354594546 2026-10-17 09-11-35.m4a"
  static final RegExp _vivoFileRegex = RegExp(
    r'^(.+?)\s+(\d{4}-\d{2}-\d{2})\s+(\d{2})[-:](\d{2})[-:](\d{2})\.(m4a|amr|mp3|aac|wav|ogg)$',
    caseSensitive: false,
  );

  // In-memory cache to prevent blocking the Dart isolate on 6,000+ files
  List<IndexedRecordingFile>? _cachedIndex;
  DateTime? _lastIndexTime;

  /// Locates all candidate directories that exist on the Vivo S1
  List<Directory> getExistingDirectories() {
    final List<Directory> dirs = [];
    final Set<String> resolvedPaths = {};
    for (final p in candidatePaths) {
      try {
        final d = Directory(p);
        if (d.existsSync()) {
          final canonical = d.resolveSymbolicLinksSync();
          if (!resolvedPaths.contains(canonical)) {
            resolvedPaths.add(canonical);
            dirs.add(d);
          }
        }
      } catch (_) {}
    }
    return dirs;
  }

  /// Fast directory indexer that reads filenames without expensive statSync calls
  List<IndexedRecordingFile> _getOrBuildIndex() {
    final now = DateTime.now();
    if (_cachedIndex != null && _lastIndexTime != null && now.difference(_lastIndexTime!) < const Duration(seconds: 20)) {
      return _cachedIndex!;
    }

    final List<IndexedRecordingFile> index = [];
    final Set<String> seenFilenames = {};
    final dirs = getExistingDirectories();

    for (final dir in dirs) {
      try {
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is! File) continue;

          final filename = entity.path.split(Platform.pathSeparator).last;
          if (seenFilenames.contains(filename)) continue;

          final dotIdx = filename.lastIndexOf('.');
          if (dotIdx == -1) continue;
          final ext = filename.substring(dotIdx).toLowerCase();
          if (!validExtensions.contains(ext)) continue;

          seenFilenames.add(filename);

          // Fast regex parsing
          final match = _vivoFileRegex.firstMatch(filename);
          if (match != null) {
            final identifier = match.group(1)!.trim();
            final dateStr = '${match.group(2)} ${match.group(3)}:${match.group(4)}:${match.group(5)}';
            final dt = DateTime.tryParse(dateStr);
            final timestamp = dt?.millisecondsSinceEpoch ?? 0;

            index.add(IndexedRecordingFile(
              file: entity,
              filename: filename,
              filePath: entity.path,
              identifier: identifier,
              timestamp: timestamp,
            ));
          } else {
            // Non-standard filename fallback
            index.add(IndexedRecordingFile(
              file: entity,
              filename: filename,
              filePath: entity.path,
              identifier: filename.substring(0, dotIdx),
              timestamp: 0, // Resolved lazily via stat if needed
            ));
          }
        }
      } catch (e) {
        debugPrint('[VIVO_RECORDINGS] Error indexing ${dir.path}: $e');
      }
    }

    // Sort index newest first
    index.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _cachedIndex = index;
    _lastIndexTime = now;
    debugPrint('[VIVO_RECORDINGS] Indexed ${index.length} call recordings across ${dirs.length} directories');
    return index;
  }

  /// Intelligently parses filename and correlates with Android Call History to accurately determine
  /// the phone number, contact name, and duration of the call recording.
  CallRecordingModel parseRecordingMetadata(
    IndexedRecordingFile item, {
    String? filterNumber,
    List<CallLogModel>? cachedCallHistory,
    List<ContactModel>? cachedContacts,
    bool populateStat = false,
  }) {
    final identifier = item.identifier;
    int fileTime = item.timestamp;
    int fileSize = 0;

    if (populateStat || fileTime == 0) {
      try {
        final stat = item.file.statSync();
        fileSize = stat.size;
        if (fileTime == 0) fileTime = stat.modified.millisecondsSinceEpoch;
      } catch (_) {}
    }

    String resolvedNumber = (filterNumber != null && filterNumber.isNotEmpty) ? filterNumber : '';
    String resolvedName = '';
    int resolvedDuration = 0;

    // Check if identifier is numeric (raw phone number) or contact name
    final digitsOnly = identifier.replaceAll(RegExp(r'\D'), '');
    final isNumberToken = digitsOnly.length >= 7 && (identifier.startsWith('+') || RegExp(r'^[\d\s\-()]+$').hasMatch(identifier));

    if (isNumberToken) {
      if (resolvedNumber.isEmpty) resolvedNumber = identifier;
    } else {
      resolvedName = identifier;
    }

    // 1. High-Precision Correlation: Match against Android Call History by timestamp proximity
    // Vivo call recorder starts recording when the call is answered (typically 5-30s after call start).
    if (cachedCallHistory != null && cachedCallHistory.isNotEmpty && fileTime > 0) {
      CallLogModel? closestMatch;
      int minDiff = 120000; // 2 minute threshold

      for (final log in cachedCallHistory) {
        // Vivo file timestamp is call answered time, log.timestamp is call initiated time.
        // Difference should typically be between 0 and 60 seconds.
        final diffStart = (fileTime - log.timestamp).abs();
        final callEndEst = log.timestamp + (log.durationSeconds * 1000);
        final diffEnd = (fileTime - callEndEst).abs();
        final diff = diffStart < diffEnd ? diffStart : diffEnd;

        // If either the name or number matches, give it strong preference
        final nameMatch = resolvedName.isNotEmpty && (
            log.callerName.toLowerCase().contains(resolvedName.toLowerCase()) ||
            resolvedName.toLowerCase().contains(log.callerName.toLowerCase())
        );
        final normLog = PhoneNumberNormalizer.normalize(log.remoteNumber);
        final normRes = PhoneNumberNormalizer.normalize(resolvedNumber);
        final numMatch = normRes.isNotEmpty && (
            normLog == normRes ||
            (normRes.length >= 7 && normLog.contains(normRes.substring(normRes.length - 7)))
        );

        if ((nameMatch || numMatch) && diff < 180000) {
          closestMatch = log;
          break;
        }

        if (diff < minDiff) {
          minDiff = diff;
          closestMatch = log;
        }
      }

      if (closestMatch != null) {
        if (resolvedNumber.isEmpty) resolvedNumber = closestMatch.remoteNumber;
        if (resolvedName.isEmpty) resolvedName = closestMatch.callerName;
        resolvedDuration = closestMatch.durationSeconds;
      }
    }

    // 2. Correlate with Contacts cache
    if (cachedContacts != null && cachedContacts.isNotEmpty) {
      if (resolvedNumber.isNotEmpty && (resolvedName.isEmpty || resolvedName == resolvedNumber)) {
        for (final c in cachedContacts) {
          if (c.matchesNumber(resolvedNumber)) {
            resolvedName = c.displayName;
            break;
          }
        }
      } else if (resolvedNumber.isEmpty && resolvedName.isNotEmpty) {
        for (final c in cachedContacts) {
          if (c.displayName.toLowerCase() == resolvedName.toLowerCase() ||
              c.displayName.toLowerCase().contains(resolvedName.toLowerCase())) {
            if (c.phoneNumbers.isNotEmpty) {
              resolvedNumber = c.phoneNumbers.first.rawNumber;
              break;
            }
          }
        }
      }
    }

    return CallRecordingModel(
      filename: item.filename,
      filePath: item.filePath,
      remoteNumber: resolvedNumber,
      callerName: resolvedName,
      timestamp: fileTime,
      sizeBytes: fileSize,
      durationSeconds: resolvedDuration,
    );
  }

  /// Finds all recordings matching a given phone number, contact name, or specific call timestamp.
  Future<List<CallRecordingModel>> getRecordingsForNumber(
    String rawNumber, {
    List<String> contactNames = const [],
    int? callTimestamp,
    int? durationSeconds,
    List<CallLogModel>? cachedCallHistory,
    List<ContactModel>? cachedContacts,
    int limit = 20,
  }) async {
    final List<CallRecordingModel> results = [];
    final normNumber = PhoneNumberNormalizer.normalize(rawNumber);
    final significantDigits = normNumber.length >= 7
        ? normNumber.substring(normNumber.length - 7)
        : normNumber;

    final index = _getOrBuildIndex();
    debugPrint('[VIVO_RECORDINGS] Searching ${index.length} indexed files for $rawNumber (sig: $significantDigits, names: $contactNames)');

    for (final item in index) {
      bool matches = false;
      final identLower = item.identifier.toLowerCase();
      final identDigits = item.identifier.replaceAll(RegExp(r'\D'), '');

      // 1. Check if identifier directly matches significant phone digits
      if (significantDigits.isNotEmpty && identDigits.contains(significantDigits)) {
        matches = true;
      }

      // 2. Check if identifier matches any of the contact names
      if (!matches) {
        for (final name in contactNames) {
          final trimmed = name.trim().toLowerCase();
          if (trimmed.isNotEmpty && (identLower.contains(trimmed) || trimmed.contains(identLower))) {
            matches = true;
            break;
          }
        }
      }

      if (matches) {
        final parsed = parseRecordingMetadata(
          item,
          filterNumber: rawNumber,
          cachedCallHistory: cachedCallHistory,
          cachedContacts: cachedContacts,
          populateStat: true,
        );
        results.add(parsed);
      }
    }

    // If callTimestamp was provided, sort so that the recording made during this call comes first!
    if (callTimestamp != null && callTimestamp > 0 && results.isNotEmpty) {
      results.sort((a, b) {
        final diffA = (a.timestamp - callTimestamp).abs();
        final diffB = (b.timestamp - callTimestamp).abs();
        return diffA.compareTo(diffB);
      });
    } else {
      // Sort by newest recording first
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    if (results.length > limit) {
      return results.sublist(0, limit);
    }

    debugPrint('[VIVO_RECORDINGS] Found ${results.length} recordings for $rawNumber');
    return results;
  }

  /// Retrieves the latest call recordings across all directories regardless of number filter
  Future<List<CallRecordingModel>> getLatestRecordings({
    int limit = 25,
    List<CallLogModel>? cachedCallHistory,
    List<ContactModel>? cachedContacts,
  }) async {
    final index = _getOrBuildIndex();
    final slice = index.length > limit ? index.sublist(0, limit) : index;
    final List<CallRecordingModel> results = [];

    for (final item in slice) {
      final parsed = parseRecordingMetadata(
        item,
        cachedCallHistory: cachedCallHistory,
        cachedContacts: cachedContacts,
        populateStat: true,
      );
      results.add(parsed);
    }

    return results;
  }

  /// Retrieves a specific recording file by its filename
  File? getRecordingFile(String filename) {
    if (filename.isEmpty || filename.contains('..') || filename.contains('/') || filename.contains('\\')) {
      return null;
    }
    for (final dir in getExistingDirectories()) {
      try {
        final candidate = File('${dir.path}${Platform.pathSeparator}$filename');
        if (candidate.existsSync()) {
          return candidate;
        }
      } catch (_) {}
    }
    return null;
  }
}

class IndexedRecordingFile {
  final File file;
  final String filename;
  final String filePath;
  final String identifier;
  final int timestamp;

  IndexedRecordingFile({
    required this.file,
    required this.filename,
    required this.filePath,
    required this.identifier,
    required this.timestamp,
  });
}
