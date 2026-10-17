import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:pta_shared/pta_shared.dart';

/// Local SQLite Database for PTA Phone (iPhone 15 Pro)
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pta_phone_v1.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onOpen: (db) async {
        await _createRecordingsTable(db);
      },
    );
  }

  static Future<void> _createRecordingsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS call_recordings (
        filename TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        remote_number TEXT,
        caller_name TEXT,
        timestamp INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        local_path TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recordings_timestamp ON call_recordings (timestamp DESC)
    ''');
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Contacts Table
    await db.execute('''
      CREATE TABLE contacts (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        avatar_url TEXT,
        note TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 2. Phone Numbers Table (1-to-many relationship)
    await db.execute('''
      CREATE TABLE phone_numbers (
        id TEXT PRIMARY KEY,
        contact_id TEXT NOT NULL,
        normalized_number TEXT NOT NULL,
        raw_number TEXT NOT NULL,
        label TEXT NOT NULL,
        FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_phone_numbers_norm ON phone_numbers (normalized_number)
    ''');

    // 3. Call Logs Table
    await db.execute('''
      CREATE TABLE call_logs (
        id INTEGER PRIMARY KEY,
        remote_number TEXT NOT NULL,
        caller_name TEXT NOT NULL,
        number_label TEXT,
        call_type TEXT NOT NULL,
        service_type TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL
      )
    ''');

    // 4. SMS / OTP Messages Table
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        extracted_otp TEXT,
        timestamp INTEGER NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 5. Call Recordings Table
    await _createRecordingsTable(db);
  }

  // --- Contacts CRUD & Sync ---

  /// Bulk upsert contacts and phone numbers during delta-sync
  Future<void> syncContacts(List<ContactModel> contactList) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final contact in contactList) {
        await txn.insert(
          'contacts',
          {
            'id': contact.id,
            'display_name': contact.displayName,
            'is_favorite': contact.isFavorite ? 1 : 0,
            'avatar_url': contact.avatarUrl,
            'note': contact.note,
            'updated_at': contact.updatedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.delete(
          'phone_numbers',
          where: 'contact_id = ?',
          whereArgs: [contact.id],
        );

        for (int i = 0; i < contact.phoneNumbers.length; i++) {
          final item = contact.phoneNumbers[i];
          await txn.insert(
            'phone_numbers',
            {
              'id': '${contact.id}_$i',
              'contact_id': contact.id,
              'normalized_number': item.normalizedNumber,
              'raw_number': item.rawNumber,
              'label': item.label,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Permanently backfill call_logs with newly synced contact names
          await txn.rawUpdate('''
            UPDATE call_logs 
            SET caller_name = ? 
            WHERE (remote_number = ? OR remote_number = ?) AND (caller_name IS NULL OR caller_name = '' OR caller_name = remote_number)
          ''', [contact.displayName, item.normalizedNumber, item.rawNumber]);
        }
      }
    });
  }

  /// Get all contacts sorted alphabetically
  Future<List<ContactModel>> getContacts() async {
    final db = await database;
    final contactRows = await db.query('contacts', orderBy: 'display_name COLLATE NOCASE ASC');
    if (contactRows.isEmpty) return [];

    final numberRows = await db.query('phone_numbers');
    final Map<String, List<PhoneNumberItem>> numbersByContact = {};

    for (final row in numberRows) {
      final contactId = row['contact_id'] as String;
      final item = PhoneNumberItem(
        label: row['label'] as String,
        rawNumber: row['raw_number'] as String,
        normalizedNumber: row['normalized_number'] as String,
      );
      numbersByContact.putIfAbsent(contactId, () => []).add(item);
    }

    return contactRows.map((row) {
      final id = row['id'] as String;
      return ContactModel(
        id: id,
        displayName: row['display_name'] as String,
        isFavorite: (row['is_favorite'] as int) == 1,
        avatarUrl: row['avatar_url'] as String?,
        note: row['note'] as String?,
        phoneNumbers: numbersByContact[id] ?? [],
        updatedAt: row['updated_at'] as int,
      );
    }).toList();
  }

  /// Search contacts by name or phone number
  Future<List<ContactModel>> searchContacts(String query) async {
    final all = await getContacts();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;

    final normQuery = PhoneNumberNormalizer.normalize(q);

    return all.where((c) {
      if (c.displayName.toLowerCase().contains(q)) return true;
      for (final p in c.phoneNumbers) {
        if (p.rawNumber.contains(q)) return true;
        if (normQuery.isNotEmpty && p.normalizedNumber.contains(normQuery)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  /// Instant caller ID lookup by any phone number (matches normalized 10 digits)
  Future<ContactModel?> findContactByNumber(String rawNumber) async {
    final db = await database;
    final norm = PhoneNumberNormalizer.normalize(rawNumber);
    if (norm.isEmpty) return null;

    final result = await db.query(
      'phone_numbers',
      where: 'normalized_number = ?',
      whereArgs: [norm],
      limit: 1,
    );

    if (result.isEmpty) return null;
    final contactId = result.first['contact_id'] as String;

    final contactResult = await db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: [contactId],
      limit: 1,
    );

    if (contactResult.isEmpty) return null;

    final numRows = await db.query(
      'phone_numbers',
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );

    final numbers = numRows.map((r) => PhoneNumberItem(
      label: r['label'] as String,
      rawNumber: r['raw_number'] as String,
      normalizedNumber: r['normalized_number'] as String,
    )).toList();

    return ContactModel(
      id: contactId,
      displayName: contactResult.first['display_name'] as String,
      isFavorite: (contactResult.first['is_favorite'] as int) == 1,
      avatarUrl: contactResult.first['avatar_url'] as String?,
      note: contactResult.first['note'] as String?,
      phoneNumbers: numbers,
      updatedAt: contactResult.first['updated_at'] as int,
    );
  }

  // --- Call Logs CRUD ---

  Future<void> saveCallLog(CallLogModel log) async {
    final db = await database;
    var nameToStore = log.callerName.trim();
    if (nameToStore.isEmpty || nameToStore == log.remoteNumber) {
      final matchedContact = await findContactByNumber(log.remoteNumber);
      if (matchedContact != null) {
        nameToStore = matchedContact.displayName;
      }
    }

    // Deduplication check: check if an identical or near-simultaneous log exists within 30 seconds
    final clean = log.remoteNumber.trim();
    final norm = PhoneNumberNormalizer.normalize(clean);
    final sig = norm.length >= 7 ? norm.substring(norm.length - 7) : norm;

    final windowStart = log.timestamp - 30000;
    final windowEnd = log.timestamp + 30000;

    final existing = await db.query(
      'call_logs',
      where: 'timestamp BETWEEN ? AND ?',
      whereArgs: [windowStart, windowEnd],
    );

    for (final row in existing) {
      final rowNum = (row['remote_number'] as String? ?? '').trim();
      final rowNorm = PhoneNumberNormalizer.normalize(rowNum);
      final rowSig = rowNorm.length >= 7 ? rowNorm.substring(rowNorm.length - 7) : rowNorm;
      final rowName = (row['caller_name'] as String? ?? '').trim();

      final bool numberMatch = (sig.isNotEmpty && rowSig.isNotEmpty && sig == rowSig) ||
          (clean.isNotEmpty && rowNum.isNotEmpty && clean == rowNum);
      final bool nameMatch = nameToStore.isNotEmpty &&
          rowName.isNotEmpty &&
          nameToStore.toLowerCase() == rowName.toLowerCase();

      if (numberMatch || nameMatch) {
        final existingDuration = row['duration_seconds'] as int? ?? 0;
        final newDuration = log.durationSeconds > existingDuration ? log.durationSeconds : existingDuration;
        await db.update(
          'call_logs',
          {
            'remote_number': (clean.isNotEmpty && clean != 'Cellular Call') ? clean : rowNum,
            'caller_name': nameToStore.isNotEmpty ? nameToStore : rowName,
            'duration_seconds': newDuration,
            'call_type': log.callType.name,
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        return; // Successfully merged into existing call log!
      }
    }

    await db.insert(
      'call_logs',
      {
        'id': log.id,
        'remote_number': log.remoteNumber,
        'caller_name': nameToStore,
        'number_label': log.numberLabel,
        'call_type': log.callType.name,
        'service_type': log.serviceType.name,
        'duration_seconds': log.durationSeconds,
        'timestamp': log.timestamp,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> cleanDuplicateCallLogs() async {
    try {
      final db = await database;
      final rows = await db.query('call_logs', orderBy: 'timestamp DESC');
      if (rows.length < 2) return;

      final idsToDelete = <int>{};
      for (int i = 0; i < rows.length; i++) {
        final rowI = rows[i];
        final idI = rowI['id'] as int;
        if (idsToDelete.contains(idI)) continue;

        final timeI = rowI['timestamp'] as int? ?? 0;
        final numI = rowI['remote_number']?.toString().trim() ?? '';
        final nameI = rowI['caller_name']?.toString().trim() ?? '';
        final durI = rowI['duration_seconds'] as int? ?? 0;

        for (int j = i + 1; j < rows.length; j++) {
          final rowJ = rows[j];
          final idJ = rowJ['id'] as int;
          if (idsToDelete.contains(idJ)) continue;

          final timeJ = rowJ['timestamp'] as int? ?? 0;
          final diff = (timeI - timeJ).abs();
          // Since sorted timestamp DESC, once diff > 120s, subsequent rows are even further
          if (diff > 120000) break;

          final numJ = rowJ['remote_number']?.toString().trim() ?? '';
          final nameJ = rowJ['caller_name']?.toString().trim() ?? '';
          final durJ = rowJ['duration_seconds'] as int? ?? 0;

          final bool numMatch = numI.isNotEmpty && numJ.isNotEmpty &&
              (numI == numJ || PhoneNumberNormalizer.areMatching(numI, numJ));
          final bool nameMatch = nameI.isNotEmpty && nameJ.isNotEmpty &&
              nameI.toLowerCase() == nameJ.toLowerCase();

          if (numMatch || nameMatch) {
            // Clustered duplicate detected within 2 minutes!
            if (durI == 0 && durJ == 0) {
              idsToDelete.add(idJ);
            } else if (durI > 0 && durJ == 0) {
              idsToDelete.add(idJ);
            } else if (durI == 0 && durJ > 0) {
              idsToDelete.add(idI);
              break;
            } else if (durI == durJ) {
              idsToDelete.add(idJ);
            }
          }
        }
      }

      for (final id in idsToDelete) {
        await db.delete('call_logs', where: 'id = ?', whereArgs: [id]);
      }
    } catch (_) {}
  }

  Future<List<CallLogModel>> getCallLogs({bool missedOnly = false}) async {
    await cleanDuplicateCallLogs();
    final db = await database;
    final List<Map<String, dynamic>> rows;

    if (missedOnly) {
      rows = await db.query(
        'call_logs',
        where: 'call_type = ?',
        whereArgs: ['missed'],
        orderBy: 'timestamp DESC',
        limit: 100,
      );
    } else {
      rows = await db.query(
        'call_logs',
        orderBy: 'timestamp DESC',
        limit: 100,
      );
    }

    return rows.map((r) {
      return CallLogModel(
        id: r['id'] as int,
        remoteNumber: r['remote_number'] as String,
        callerName: r['caller_name'] as String,
        numberLabel: r['number_label'] as String?,
        callType: CallType.values.firstWhere(
          (t) => t.name == (r['call_type'] as String),
          orElse: () => CallType.incoming,
        ),
        serviceType: ServiceType.values.firstWhere(
          (c) => c.name == (r['service_type'] as String),
          orElse: () => ServiceType.zongGsm,
        ),
        durationSeconds: r['duration_seconds'] as int,
        timestamp: r['timestamp'] as int,
      );
    }).toList();
  }

  Future<List<CallLogModel>> getCallLogsForNumbers(List<String> rawNumbers) async {
    final allLogs = await getCallLogs();
    final normalizedSet = rawNumbers
        .map((n) => PhoneNumberNormalizer.normalize(n))
        .where((n) => n.isNotEmpty)
        .toSet();
    final rawSet = rawNumbers
        .map((n) => n.replaceAll(RegExp(r'\s+'), ''))
        .where((n) => n.isNotEmpty)
        .toSet();

    return allLogs.where((log) {
      final logNorm = PhoneNumberNormalizer.normalize(log.remoteNumber);
      final logRaw = log.remoteNumber.replaceAll(RegExp(r'\s+'), '');
      return normalizedSet.contains(logNorm) || rawSet.contains(logRaw);
    }).toList();
  }

  Future<List<CallLogModel>> getCallLogsForContact({
    required List<String> rawNumbers,
    required String displayName,
  }) async {
    final allLogs = await getCallLogs();
    final normalizedSet = rawNumbers
        .map((n) => PhoneNumberNormalizer.normalize(n))
        .where((n) => n.isNotEmpty)
        .toSet();
    final rawSet = rawNumbers
        .map((n) => n.replaceAll(RegExp(r'\s+'), ''))
        .where((n) => n.isNotEmpty)
        .toSet();
    final cleanName = displayName.trim().toLowerCase();

    return allLogs.where((log) {
      final logNorm = PhoneNumberNormalizer.normalize(log.remoteNumber);
      final logRaw = log.remoteNumber.replaceAll(RegExp(r'\s+'), '');
      final logName = log.callerName.trim().toLowerCase();

      final numMatch = normalizedSet.contains(logNorm) || rawSet.contains(logRaw);
      final nameMatch = cleanName.isNotEmpty &&
          cleanName != 'cellular call' &&
          (logName == cleanName || (logName.isNotEmpty && logName.contains(cleanName)));

      return numMatch || nameMatch;
    }).toList();
  }

  // --- Messages & OTP CRUD ---

  Future<void> saveMessage(SmsMessageModel message) async {
    final db = await database;
    await db.insert(
      'messages',
      {
        'id': message.id,
        'sender': message.sender,
        'body': message.body,
        'extracted_otp': message.extractedOtp,
        'timestamp': message.timestamp,
        'is_read': message.isRead ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveMessages(List<SmsMessageModel> messages) async {
    if (messages.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final message in messages) {
      batch.insert(
        'messages',
        {
          'id': message.id,
          'sender': message.sender,
          'body': message.body,
          'extracted_otp': message.extractedOtp,
          'timestamp': message.timestamp,
          'is_read': message.isRead ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<SmsMessageModel>> getMessages({int limit = 500}) async {
    final db = await database;
    final rows = await db.query(
      'messages',
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return rows.map((r) {
      return SmsMessageModel(
        id: r['id'] as int,
        sender: r['sender'] as String,
        body: r['body'] as String,
        extractedOtp: r['extracted_otp'] as String?,
        timestamp: r['timestamp'] as int,
        isRead: (r['is_read'] as int) == 1,
      );
    }).toList();
  }

  Future<void> markMessageRead(int id) async {
    final db = await database;
    await db.update(
      'messages',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markThreadRead(String address) async {
    final db = await database;
    await db.update(
      'messages',
      {'is_read': 1},
      where: 'sender = ? OR sender = ?',
      whereArgs: [address, 'To: $address'],
    );
  }

  // --- Call Recordings CRUD & Offline Cache ---

  Future<void> saveRecordings(List<CallRecordingModel> list) async {
    final db = await database;
    Directory? docDir;
    try {
      docDir = await getApplicationDocumentsDirectory();
    } catch (_) {}

    await db.transaction((txn) async {
      for (final rec in list) {
        String? resolvedLocalPath = rec.localPath;

        // If localPath is null in incoming model, check if existing record already had a local_path
        if (resolvedLocalPath == null || resolvedLocalPath.isEmpty) {
          final existing = await txn.query(
            'call_recordings',
            columns: ['local_path'],
            where: 'filename = ?',
            whereArgs: [rec.filename],
            limit: 1,
          );
          if (existing.isNotEmpty && existing.first['local_path'] != null) {
            final oldPath = existing.first['local_path'] as String;
            if (oldPath.isNotEmpty && File(oldPath).existsSync()) {
              resolvedLocalPath = oldPath;
            }
          }
        }

        // Check if the physical file already exists on iPhone in /Documents/recordings/
        if ((resolvedLocalPath == null || resolvedLocalPath.isEmpty) && docDir != null) {
          final candidate = File('${docDir.path}/recordings/${rec.filename}');
          if (candidate.existsSync() && candidate.lengthSync() > 0) {
            resolvedLocalPath = candidate.path;
          }
        }

        await txn.insert(
          'call_recordings',
          {
            'filename': rec.filename,
            'file_path': rec.filePath,
            'remote_number': rec.remoteNumber,
            'caller_name': rec.callerName,
            'timestamp': rec.timestamp,
            'size_bytes': rec.sizeBytes,
            'duration_seconds': rec.durationSeconds,
            'local_path': resolvedLocalPath,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> updateRecordingLocalPath(String filename, String localPath) async {
    final db = await database;
    await db.update(
      'call_recordings',
      {'local_path': localPath},
      where: 'filename = ?',
      whereArgs: [filename],
    );
  }

  Future<List<CallRecordingModel>> getLocalRecordings({
    String? number,
    List<String>? numbers,
    String? name,
    int? callTimestamp,
    int limit = 50,
  }) async {
    final db = await database;
    Directory? docDir;
    try {
      docDir = await getApplicationDocumentsDirectory();
    } catch (_) {}

    // Collect all candidate numbers
    final candidateNumbers = <String>[];
    if (numbers != null) {
      candidateNumbers.addAll(numbers);
    }
    if (number != null && number.trim().isNotEmpty) {
      candidateNumbers.add(number.trim());
    }

    // Extract significant phone signatures (minimum 6 digits to avoid greedy matches)
    final sigs = <String>[];
    for (final numStr in candidateNumbers) {
      final norm = PhoneNumberNormalizer.normalize(numStr);
      if (norm.length >= 6) {
        sigs.add(norm.length >= 7 ? norm.substring(norm.length - 7) : norm);
      }
    }

    final trimmedName = name?.trim() ?? '';
    final hasValidName = trimmedName.length >= 3 && !trimmedName.toLowerCase().contains('cellular call');

    // If caller specifically asked for a contact's recordings, but neither valid numbers nor valid name exists:
    // DO NOT return all recordings! Return empty list!
    final bool filteringRequested = candidateNumbers.isNotEmpty || (name != null && name.trim().isNotEmpty);
    if (filteringRequested && sigs.isEmpty && !hasValidName) {
      return [];
    }

    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (sigs.isNotEmpty && hasValidName) {
      final orParts = <String>[];
      for (final s in sigs) {
        orParts.add('remote_number LIKE ?');
        whereArgs.add('%$s%');
      }
      orParts.add('caller_name LIKE ?');
      whereArgs.add('%$trimmedName%');
      whereClauses.add('(${orParts.join(' OR ')})');
    } else if (sigs.isNotEmpty) {
      final orParts = <String>[];
      for (final s in sigs) {
        orParts.add('remote_number LIKE ?');
        whereArgs.add('%$s%');
      }
      whereClauses.add('(${orParts.join(' OR ')})');
    } else if (hasValidName) {
      whereClauses.add('caller_name LIKE ?');
      whereArgs.add('%$trimmedName%');
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final maps = await db.query(
      'call_recordings',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    final results = <CallRecordingModel>[];
    for (final m in maps) {
      final rec = CallRecordingModel.fromJson(m);
      if (filteringRequested) {
        // Double check in Dart: must match either one of sigs OR the name
        final recNum = rec.remoteNumber.trim();
        final recNorm = PhoneNumberNormalizer.normalize(recNum);
        final bool numMatch = sigs.any((s) => recNorm.contains(s));
        final recName = rec.callerName?.toLowerCase() ?? '';
        final bool nameMatch = hasValidName && recName.isNotEmpty &&
            (recName.contains(trimmedName.toLowerCase()) ||
             trimmedName.toLowerCase().contains(recName));

        if (!numMatch && !nameMatch) {
          // Reject foreign contact!
          continue;
        }
      }

      if ((rec.localPath == null || rec.localPath!.isEmpty) && docDir != null) {
        final candidate = File('${docDir.path}/recordings/${rec.filename}');
        if (candidate.existsSync() && candidate.lengthSync() > 0) {
          results.add(rec.copyWith(localPath: candidate.path));
          continue;
        }
      }
      results.add(rec);
    }

    if (callTimestamp != null && callTimestamp > 0 && results.isNotEmpty) {
      results.sort((a, b) {
        final diffA = (a.timestamp - callTimestamp).abs();
        final diffB = (b.timestamp - callTimestamp).abs();
        return diffA.compareTo(diffB);
      });
    }
    return results;
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('call_recordings');
    await db.delete('call_logs');
    await db.delete('messages');
    await db.delete('phone_numbers');
    await db.delete('contacts');
  }
}
