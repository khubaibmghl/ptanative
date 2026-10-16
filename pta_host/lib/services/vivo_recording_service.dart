import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pta_shared/pta_shared.dart';

/// Scanner service for Vivo S1 (Funtouch OS) call recordings
class VivoRecordingService {
  static final VivoRecordingService instance = VivoRecordingService._init();
  VivoRecordingService._init();

  static const List<String> candidatePaths = [
    '/storage/emulated/0/Record/Call',
    '/storage/emulated/0/Recordings/Call',
    '/storage/emulated/0/Record',
    '/storage/emulated/0/Recordings',
    '/storage/emulated/0/Recorder/Call',
    '/storage/emulated/0/Recorder',
    '/storage/emulated/0/Sounds/Call',
    '/storage/emulated/0/Sounds',
    '/sdcard/Record/Call',
    '/sdcard/Recordings/Call',
    '/sdcard/Recorder/Call',
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

  /// Locates all candidate directories that exist on the Vivo S1
  List<Directory> getExistingDirectories() {
    final List<Directory> dirs = [];
    for (final p in candidatePaths) {
      try {
        final d = Directory(p);
        if (d.existsSync()) {
          dirs.add(d);
        }
      } catch (_) {}
    }
    return dirs;
  }

  /// Intelligently parses filename and correlates with Android Call History to accurately determine
  /// the phone number, contact name, and duration of the call recording.
  CallRecordingModel parseRecordingMetadata(
    File file,
    FileStat stat, {
    String? filterNumber,
    List<CallLogModel>? cachedCallHistory,
    List<ContactModel>? cachedContacts,
  }) {
    final path = file.path;
    final filename = path.split(Platform.pathSeparator).last;
    final dotIndex = filename.lastIndexOf('.');
    final nameWithoutExt = dotIndex != -1 ? filename.substring(0, dotIndex) : filename;
    final fileTime = stat.modified.millisecondsSinceEpoch;

    String resolvedNumber = (filterNumber != null && filterNumber.isNotEmpty) ? filterNumber : '';
    String resolvedName = '';
    int resolvedDuration = 0;

    // 1. High-Precision Correlation: Match against Android Call History by timestamp
    // Vivo call recording files are saved immediately when the call finishes (within 0-120s of call end).
    if (cachedCallHistory != null && cachedCallHistory.isNotEmpty) {
      CallLogModel? closestMatch;
      int minDiff = 120000; // 2 minute threshold

      for (final log in cachedCallHistory) {
        // Calculate estimated call completion time: call start + duration
        final callEndEst = log.timestamp + (log.durationSeconds * 1000);
        final diffEnd = (fileTime - callEndEst).abs();
        final diffStart = (fileTime - log.timestamp).abs();
        final diff = diffEnd < diffStart ? diffEnd : diffStart;

        if (diff < minDiff) {
          minDiff = diff;
          closestMatch = log;
        }
      }

      if (closestMatch != null) {
        resolvedNumber = closestMatch.remoteNumber;
        resolvedName = closestMatch.callerName;
        resolvedDuration = closestMatch.durationSeconds;
      }
    }

    // 2. Parse phone number and name tokens from filename if not yet resolved
    final tokens = nameWithoutExt.split(RegExp(r'[_ \-@]'));
    for (final token in tokens) {
      final trimmed = token.trim();
      final digits = trimmed.replaceAll(RegExp(r'\D'), '');

      // Identify timestamp token (e.g. 20261016... or 14-digit epoch)
      final isDateToken = (digits.startsWith('202') && digits.length >= 8) || digits.length == 14 || digits.length == 6;

      if (!isDateToken && digits.length >= 7 && digits.length <= 15) {
        // Valid phone number token
        if (resolvedNumber.isEmpty) {
          resolvedNumber = trimmed;
        }
      } else if (trimmed.length >= 2 && !RegExp(r'^\d+$').hasMatch(trimmed)) {
        final lower = trimmed.toLowerCase();
        if (lower != 'call' && lower != 'record' && lower != 'recorder' && lower != 'voice' && lower != 'audio' && lower != 'sound') {
          if (resolvedName.isEmpty) {
            resolvedName = trimmed;
          }
        }
      }
    }

    // 3. Match against Contacts cache to resolve missing names or numbers
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
          if (c.displayName.toLowerCase() == resolvedName.toLowerCase()) {
            if (c.phoneNumbers.isNotEmpty) {
              resolvedNumber = c.phoneNumbers.first.rawNumber;
              break;
            }
          }
        }
      }
    }

    return CallRecordingModel(
      filename: filename,
      filePath: path,
      remoteNumber: resolvedNumber,
      callerName: resolvedName,
      timestamp: fileTime,
      sizeBytes: stat.size,
      durationSeconds: resolvedDuration,
    );
  }

  /// Finds all recordings matching a given phone number or contact
  Future<List<CallRecordingModel>> getRecordingsForNumber(
    String rawNumber, {
    List<String> contactNames = const [],
    List<CallLogModel>? cachedCallHistory,
    List<ContactModel>? cachedContacts,
  }) async {
    final List<CallRecordingModel> results = [];
    final normNumber = PhoneNumberNormalizer.normalize(rawNumber);
    final significantDigits = normNumber.length >= 7
        ? normNumber.substring(normNumber.length - 7)
        : normNumber;

    final existingDirs = getExistingDirectories();
    final Set<String> seenFilenames = {};
    debugPrint('[VIVO_RECORDINGS] Scanning ${existingDirs.length} existing directories for $rawNumber (sig: $significantDigits)');

    for (final dir in existingDirs) {
      try {
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is! File) continue;

          final filename = entity.path.split(Platform.pathSeparator).last;
          if (seenFilenames.contains(filename)) continue;

          final lowerExt = filename.toLowerCase();
          final hasValidExt = validExtensions.any((ext) => lowerExt.endsWith(ext));
          if (!hasValidExt) continue;

          final stat = entity.statSync();
          final parsed = parseRecordingMetadata(
            entity,
            stat,
            cachedCallHistory: cachedCallHistory,
            cachedContacts: cachedContacts,
          );

          bool matches = false;

          // 1. Direct number match against parsed model
          if (parsed.remoteNumber.isNotEmpty) {
            final parsedNorm = PhoneNumberNormalizer.normalize(parsed.remoteNumber);
            final parsedSig = parsedNorm.length >= 7 ? parsedNorm.substring(parsedNorm.length - 7) : parsedNorm;
            if (parsedSig.isNotEmpty && (significantDigits.contains(parsedSig) || parsedSig.contains(significantDigits))) {
              matches = true;
            }
          }

          // 2. Contact name match in parsed model
          if (!matches && parsed.callerName != null && parsed.callerName!.isNotEmpty) {
            for (final name in contactNames) {
              if (name.trim().isNotEmpty && parsed.callerName!.toLowerCase().contains(name.trim().toLowerCase())) {
                matches = true;
                break;
              }
            }
          }

          // 3. Raw filename check for significant digits (ensuring it's not part of the date/time timestamp)
          if (!matches && significantDigits.isNotEmpty) {
            final dotIdx = filename.lastIndexOf('.');
            final base = dotIdx != -1 ? filename.substring(0, dotIdx) : filename;
            final tokens = base.split(RegExp(r'[_ \-@]'));
            for (final token in tokens) {
              final digits = token.replaceAll(RegExp(r'\D'), '');
              final isDate = digits.startsWith('202') || digits.length == 14 || digits.length == 6;
              if (!isDate && digits.length >= 7 && digits.contains(significantDigits)) {
                matches = true;
                break;
              }
            }
          }

          if (matches) {
            seenFilenames.add(filename);
            results.add(parsed);
          }
        }
      } catch (e) {
        debugPrint('[VIVO_RECORDINGS] Error scanning dir ${dir.path}: $e');
      }
    }

    // Sort by newest recording first
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    debugPrint('[VIVO_RECORDINGS] Found ${results.length} recordings for $rawNumber');
    return results;
  }

  /// Retrieves the latest call recordings across all directories regardless of number filter
  Future<List<CallRecordingModel>> getLatestRecordings({
    int limit = 10,
    List<CallLogModel>? cachedCallHistory,
    List<ContactModel>? cachedContacts,
  }) async {
    final List<CallRecordingModel> results = [];
    final existingDirs = getExistingDirectories();
    final Set<String> seenFilenames = {};
    debugPrint('[VIVO_RECORDINGS] Fetching latest recordings (limit: $limit) from ${existingDirs.length} directories');

    for (final dir in existingDirs) {
      try {
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is! File) continue;
          final filename = entity.path.split(Platform.pathSeparator).last;
          if (seenFilenames.contains(filename)) continue;

          final lowerExt = filename.toLowerCase();
          final hasValidExt = validExtensions.any((ext) => lowerExt.endsWith(ext));
          if (!hasValidExt) continue;

          try {
            final stat = entity.statSync();
            seenFilenames.add(filename);
            final parsed = parseRecordingMetadata(
              entity,
              stat,
              cachedCallHistory: cachedCallHistory,
              cachedContacts: cachedContacts,
            );
            results.add(parsed);
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[VIVO_RECORDINGS] Error scanning dir ${dir.path}: $e');
      }
    }

    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (results.length > limit) {
      return results.sublist(0, limit);
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
