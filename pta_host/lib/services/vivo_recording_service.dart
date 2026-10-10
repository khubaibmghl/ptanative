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
    '/sdcard/Record/Call',
    '/sdcard/Recordings/Call',
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

  /// Finds all recordings matching a given phone number or contact
  Future<List<CallRecordingModel>> getRecordingsForNumber(
    String rawNumber, {
    List<String> contactNames = const [],
  }) async {
    final List<CallRecordingModel> results = [];
    final normNumber = PhoneNumberNormalizer.normalize(rawNumber);
    final significantDigits = normNumber.length >= 7
        ? normNumber.substring(normNumber.length - 7)
        : normNumber;

    final existingDirs = getExistingDirectories();
    debugPrint('[VIVO_RECORDINGS] Scanning ${existingDirs.length} existing directories for $rawNumber (sig: $significantDigits)');

    for (final dir in existingDirs) {
      try {
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is! File) continue;

          final path = entity.path;
          final filename = path.split(Platform.pathSeparator).last;
          final lowerExt = filename.toLowerCase();

          final hasValidExt = validExtensions.any((ext) => lowerExt.endsWith(ext));
          if (!hasValidExt) continue;

          // Check if filename contains phone digits or contact names
          bool matches = false;
          final cleanFilenameDigits = filename.replaceAll(RegExp(r'\D'), '');

          if (significantDigits.isNotEmpty &&
              (cleanFilenameDigits.contains(significantDigits) || filename.contains(significantDigits))) {
            matches = true;
          }

          if (!matches && normNumber.isNotEmpty && filename.contains(normNumber)) {
            matches = true;
          }

          if (!matches) {
            for (final name in contactNames) {
              if (name.trim().isNotEmpty && filename.toLowerCase().contains(name.trim().toLowerCase())) {
                matches = true;
                break;
              }
            }
          }

          if (matches) {
            try {
              final stat = entity.statSync();
              results.add(CallRecordingModel(
                filename: filename,
                filePath: path,
                remoteNumber: rawNumber,
                timestamp: stat.modified.millisecondsSinceEpoch,
                sizeBytes: stat.size,
                durationSeconds: 0,
              ));
            } catch (_) {}
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
