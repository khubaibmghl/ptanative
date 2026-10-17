import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pta_host/services/vivo_recording_service.dart';
import 'package:pta_shared/pta_shared.dart';

void main() {
  group('VivoRecordingService tests', () {
    test('Regex correctly parses Vivo recording filenames', () {
      final filenames = [
        'Prof Attique GGCP 2026-10-17 11-17-19.m4a',
        'Madam Isha Noor 2026-10-17 09-10-38.m4a',
        '03354594546 2026-10-17 09-11-35.m4a',
        '03346757701 2026-10-17 07-59-59.m4a',
        'Zia Bhae 2026-10-17 08-24-09.m4a',
        '+923008642940 2025-04-06 13-35-22.m4a',
      ];

      for (final fn in filenames) {
        final match = RegExp(
          r'^(.+?)\s+(\d{4}-\d{2}-\d{2})\s+(\d{2})[-:](\d{2})[-:](\d{2})\.(m4a|amr|mp3|aac|wav|ogg)$',
          caseSensitive: false,
        ).firstMatch(fn);

        expect(match, isNotNull, reason: 'Failed to match: $fn');
        final identifier = match!.group(1)!.trim();
        final dateStr = '${match.group(2)} ${match.group(3)}:${match.group(4)}:${match.group(5)}';
        final dt = DateTime.tryParse(dateStr);
        expect(dt, isNotNull, reason: 'Failed to parse date for: $fn');
        expect(identifier.isNotEmpty, isTrue);
      }
    });

    test('parseRecordingMetadata accurately correlates contact names and call logs', () {
      final sampleFile = IndexedRecordingFile(
        file: File('/storage/emulated/0/Recordings/Record/Call/Prof Attique GGCP 2026-10-17 11-17-19.m4a'),
        filename: 'Prof Attique GGCP 2026-10-17 11-17-19.m4a',
        filePath: '/storage/emulated/0/Recordings/Record/Call/Prof Attique GGCP 2026-10-17 11-17-19.m4a',
        identifier: 'Prof Attique GGCP',
        timestamp: DateTime.parse('2026-10-17 11:17:19').millisecondsSinceEpoch,
      );

      final cachedContacts = [
        ContactModel(
          id: 'contact_1',
          displayName: 'Prof Attique GGCP',
          phoneNumbers: [
            PhoneNumberItem(label: 'Mobile', rawNumber: '03007107568', normalizedNumber: '03007107568'),
          ],
        ),
      ];

      final cachedCallHistory = [
        CallLogModel(
          id: 1,
          remoteNumber: '03007107568',
          callerName: 'Prof Attique GGCP',
          callType: CallType.incoming,
          durationSeconds: 151,
          timestamp: DateTime.parse('2026-10-17 11:17:07').millisecondsSinceEpoch,
        ),
      ];

      final result = VivoRecordingService.instance.parseRecordingMetadata(
        sampleFile,
        cachedCallHistory: cachedCallHistory,
        cachedContacts: cachedContacts,
      );

      expect(result.callerName, equals('Prof Attique GGCP'));
      expect(result.remoteNumber, equals('03007107568'));
      expect(result.durationSeconds, equals(151));
    });
  });
}
