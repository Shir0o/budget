import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'budget_key.dart';
import 'event.dart';

/// A `.budgetbackup` that can't be opened: wrong key, damaged, or not a
/// backup.
final class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => 'BackupException: $message';
}

/// The encrypted backup file (ticket 12): the Event log, sealed with the
/// Budget Key using XChaCha20-Poly1305.
///
/// Layout: `"BUDGETBK"`, a version byte, a 24-byte random nonce, then the
/// ciphertext and its 16-byte tag. The 9 header bytes are authenticated too.
abstract final class Backup {
  static const _magic = [0x42, 0x55, 0x44, 0x47, 0x45, 0x54, 0x42, 0x4B];
  static const _version = 1;
  static const _headerLength = 9;
  static const _nonceLength = 24;
  static const _macLength = 16;

  static final _cipher = Xchacha20.poly1305Aead();

  /// `budget-2026-11-01.budgetbackup` for the ISO date [isoDate].
  static String fileName(String isoDate) => 'budget-$isoDate.budgetbackup';

  static Future<Uint8List> seal(List<Event> events, BudgetKey key) async {
    final header = Uint8List.fromList([..._magic, _version]);
    final clear = utf8.encode(
      jsonEncode({
        'events': [for (final e in events) e.toJson()],
      }),
    );
    final box = await _cipher.encrypt(
      clear,
      secretKey: SecretKey(key.bytes),
      nonce: _cipher.newNonce(),
      aad: header,
    );
    return Uint8List.fromList([...header, ...box.concatenation(nonce: true)]);
  }

  /// Throws [BackupException] if [file] isn't a backup, was altered, or was
  /// sealed with a different key.
  static Future<List<Event>> open(Uint8List file, BudgetKey key) async {
    if (file.length < _headerLength + _nonceLength + _macLength ||
        !_hasHeader(file)) {
      throw const BackupException('Not a budget backup file');
    }
    final box = SecretBox.fromConcatenation(
      file.sublist(_headerLength),
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    final List<int> clear;
    try {
      clear = await _cipher.decrypt(
        box,
        secretKey: SecretKey(key.bytes),
        aad: file.sublist(0, _headerLength),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupException('Wrong key, or the file was changed');
    }
    final body = jsonDecode(utf8.decode(clear)) as Map;
    return [
      for (final e in (body['events'] as List).cast<Map>())
        Event.fromJson(e.cast<String, Object?>()),
    ];
  }

  static bool _hasHeader(Uint8List file) {
    for (var i = 0; i < _magic.length; i++) {
      if (file[i] != _magic[i]) return false;
    }
    return file[_magic.length] == _version;
  }
}
