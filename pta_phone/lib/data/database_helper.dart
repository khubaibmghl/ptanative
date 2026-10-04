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
      version: 1,
      onCreate: _createDB,
    );
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
    await db.insert(
      'call_logs',
      {
        'id': log.id,
        'remote_number': log.remoteNumber,
        'caller_name': log.callerName,
        'number_label': log.numberLabel,
        'call_type': log.callType.name,
        'service_type': log.serviceType.name,
        'duration_seconds': log.durationSeconds,
        'timestamp': log.timestamp,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CallLogModel>> getCallLogs({bool missedOnly = false}) async {
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

  Future<List<SmsMessageModel>> getMessages() async {
    final db = await database;
    final rows = await db.query(
      'messages',
      orderBy: 'timestamp DESC',
      limit: 100,
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

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('call_logs');
    await db.delete('messages');
    await db.delete('phone_numbers');
    await db.delete('contacts');
  }
}
