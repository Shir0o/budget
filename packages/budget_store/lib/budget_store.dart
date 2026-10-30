/// SQLCipher-encrypted, append-only Event store for `budget_core`.
library;

import 'dart:convert';

import 'package:budget_core/budget_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// An [EventLog] in an SQLite database encrypted with SQLCipher.
///
/// The app keeps the key in Android Keystore (or the macOS Keychain) and
/// passes it in; the store never persists it.
final class SqlCipherEventLog implements EventLog {
  SqlCipherEventLog._(this._db);

  /// Opens (or creates) the store file at [path]. [keyHex] is a 256-bit key
  /// as 64 hex digits.
  ///
  /// Throws a [StateError] if SQLCipher isn't the linked SQLite, so the
  /// store can never silently fall back to an unencrypted file. Throws a
  /// [SqliteException] if [keyHex] doesn't match an existing file.
  factory SqlCipherEventLog.open(String path, {required String keyHex}) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(keyHex)) {
      throw ArgumentError.value('<redacted>', 'keyHex', 'Need 64 hex digits');
    }
    final db = sqlite3.open(path);
    try {
      final cipher = db.select('PRAGMA cipher_version');
      if (cipher.isEmpty) {
        throw StateError('SQLCipher is not available; refusing to open.');
      }
      db.execute("PRAGMA key = \"x'$keyHex'\"");
      // Fails here, not later, if the key is wrong.
      db.select('SELECT count(*) FROM sqlite_master');
      db.execute('''
        CREATE TABLE IF NOT EXISTS events (
          id TEXT PRIMARY KEY,
          hlc TEXT NOT NULL,
          body TEXT NOT NULL
        ) STRICT
      ''');
      db.execute('CREATE INDEX IF NOT EXISTS events_by_hlc ON events (hlc)');
    } catch (_) {
      db.close();
      rethrow;
    }
    return SqlCipherEventLog._(db);
  }

  final Database _db;

  @override
  List<Event> readAll() => [
    for (final row in _db.select('SELECT body FROM events ORDER BY hlc'))
      Event.fromJson(
        (jsonDecode(row['body'] as String) as Map).cast<String, Object?>(),
      ),
  ];

  @override
  void append(List<Event> group) {
    final insert = _db.prepare(
      'INSERT INTO events (id, hlc, body) VALUES (?, ?, ?)',
    );
    _db.execute('BEGIN');
    try {
      for (final event in group) {
        insert.execute([
          event.id,
          event.hlc.toString(),
          jsonEncode(event.toJson()),
        ]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      insert.close();
    }
  }

  void close() => _db.close();
}
