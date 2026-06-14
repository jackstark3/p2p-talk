import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/contact.dart';
import '../models/message.dart';

/// Local SQLite storage for contacts, messages, and identity keys.
class StorageService {
  final String profile;
  StorageService({this.profile = 'default'});

  static Database? _db;

  Future<Database> get db async {
    _db ??= await _initDB();
    return _db!;
  }

  /// Database version. Bump this when the schema changes.
  static const int _dbVersion = 1;

  /// Ordered list of migrations. Index = version number (1-based).
  /// Each entry is a list of SQL statements to run for that version.
  static final Map<int, List<String>> _migrations = {
    1: [
      '''
      CREATE TABLE contacts (
        peer_id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        public_key TEXT NOT NULL,
        is_online INTEGER DEFAULT 0,
        added_at INTEGER NOT NULL,
        last_seen INTEGER
      )
      ''',
      '''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        receiver_id TEXT NOT NULL,
        ciphertext TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        seq INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        chat_with TEXT NOT NULL
      )
      ''',
      '''
      CREATE TABLE identity (
        id INTEGER PRIMARY KEY DEFAULT 1,
        peer_id TEXT NOT NULL,
        public_hex TEXT NOT NULL,
        private_hex TEXT NOT NULL
      )
      ''',
      'CREATE INDEX idx_messages_chat ON messages(chat_with, timestamp)',
      'CREATE INDEX idx_messages_status ON messages(status)',
    ],
    // Example for future v2:
    // 2: [
    //   'ALTER TABLE contacts ADD COLUMN avatar TEXT',
    //   'ALTER TABLE messages ADD COLUMN edited_at INTEGER',
    // ],
  };

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final dbName = profile == 'default' ? 'p2p_talk.db' : 'p2p_talk_$profile.db';
    final path = p.join(dbPath, dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _runMigrations(db, 1, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _runMigrations(db, oldVersion + 1, newVersion);
      },
    );
  }

  /// Runs all migrations from [from] to [to] (inclusive).
  Future<void> _runMigrations(Database db, int from, int to) async {
    for (int v = from; v <= to; v++) {
      final statements = _migrations[v];
      if (statements != null) {
        for (final sql in statements) {
          await db.execute(sql);
        }
      }
    }
  }

  // ---- Identity ----

  Future<void> saveIdentity(Map<String, String> keys) async {
    final d = await db;
    final existing = await d.query('identity', where: 'id = 1');
    if (existing.isNotEmpty) {
      await d.update('identity', keys, where: 'id = 1');
    } else {
      keys['id'] = '1';
      await d.insert('identity', keys);
    }
  }

  Future<Map<String, String>?> loadIdentity() async {
    final d = await db;
    final rows = await d.query('identity', where: 'id = 1');
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'peer_id': row['peer_id'] as String,
      'public_hex': row['public_hex'] as String,
      'private_hex': row['private_hex'] as String,
    };
  }

  // ---- Contacts ----

  Future<void> saveContact(Contact contact) async {
    final d = await db;
    await d.insert(
      'contacts',
      {
        'peer_id': contact.peerId,
        'nickname': contact.nickname,
        'public_key': base64.encode(contact.publicKey),
        'is_online': contact.isOnline ? 1 : 0,
        'added_at': contact.addedAt.millisecondsSinceEpoch,
        'last_seen': contact.lastSeen?.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Contact>> loadContacts() async {
    final d = await db;
    final rows = await d.query('contacts', orderBy: 'added_at DESC');
    return rows.map(_rowToContact).toList();
  }

  Future<void> deleteContact(String peerId) async {
    final d = await db;
    await d.delete('contacts', where: 'peer_id = ?', whereArgs: [peerId]);
  }

  Future<void> updateContactOnline(String peerId, bool online) async {
    final d = await db;
    await d.update(
      'contacts',
      {
        'is_online': online ? 1 : 0,
        'last_seen': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
  }

  // ---- Messages ----

  Future<void> saveMessage(Message msg, {required String chatWith}) async {
    final d = await db;
    await d.insert(
      'messages',
      {
        'id': msg.id.isEmpty ? const Uuid().v4() : msg.id,
        'sender_id': msg.senderId,
        'receiver_id': msg.receiverId,
        'ciphertext': msg.ciphertext,
        'timestamp': msg.timestamp,
        'seq': msg.seq,
        'status': msg.status.name,
        'chat_with': chatWith,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Message>> loadMessages(String chatWith, {int limit = 100}) async {
    final d = await db;
    final rows = await d.query(
      'messages',
      where: 'chat_with = ?',
      whereArgs: [chatWith],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return rows.map(_rowToMessage).toList();
  }

  Future<List<Message>> loadPendingMessages(String peerId) async {
    final d = await db;
    final rows = await d.query(
      'messages',
      where: 'chat_with = ? AND status = ?',
      whereArgs: [peerId, MessageStatus.pending.name],
      orderBy: 'timestamp ASC',
    );
    return rows.map(_rowToMessage).toList();
  }

  Future<void> updateMessageStatus(String msgId, MessageStatus status) async {
    final d = await db;
    await d.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [msgId],
    );
  }

  Contact _rowToContact(Map<String, dynamic> row) {
    return Contact(
      peerId: row['peer_id'] as String,
      nickname: row['nickname'] as String,
      publicKey: base64.decode(row['public_key'] as String),
      isOnline: (row['is_online'] as int) == 1,
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
      lastSeen: row['last_seen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['last_seen'] as int)
          : null,
    );
  }

  Message _rowToMessage(Map<String, dynamic> row) {
    return Message(
      id: row['id'] as String,
      senderId: row['sender_id'] as String,
      receiverId: row['receiver_id'] as String,
      ciphertext: row['ciphertext'] as String,
      timestamp: row['timestamp'] as int,
      seq: row['seq'] as int,
      status: MessageStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => MessageStatus.pending,
      ),
    );
  }
}
