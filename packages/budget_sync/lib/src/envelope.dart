import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:cryptography/cryptography.dart';

/// A sync file that can't be opened: wrong Budget Key, damaged, or renamed.
final class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => 'SyncException: $message';
}

/// One sync file in Drive (ticket 12): a JSON body sealed with the Budget
/// Key using XChaCha20-Poly1305.
///
/// Layout: `"BUDGETSY"`, a version byte, a 24-byte random nonce, then the
/// ciphertext and its 16-byte tag. The 9 header bytes and the file's whole
/// [name] are authenticated, so a file can't be swapped for, or renamed to,
/// another one. Google sees the name, the size and the timing only.
abstract final class SealedFile {
  static const _magic = [0x42, 0x55, 0x44, 0x47, 0x45, 0x54, 0x53, 0x59];
  static const _version = 1;
  static const _headerLength = 9;
  static const _nonceLength = 24;
  static const _macLength = 16;

  static final _cipher = Xchacha20.poly1305Aead();

  static Future<Uint8List> seal({
    required String name,
    required Map<String, Object?> body,
    required BudgetKey key,
  }) async {
    final header = Uint8List.fromList([..._magic, _version]);
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(body)),
      secretKey: SecretKey(key.bytes),
      nonce: _cipher.newNonce(),
      aad: [...header, ...utf8.encode(name)],
    );
    return Uint8List.fromList([...header, ...box.concatenation(nonce: true)]);
  }

  /// Throws [SyncException] if [file] isn't a sync file, was altered, was
  /// sealed under another [name], or was sealed with a different key.
  static Future<Map<String, Object?>> open({
    required String name,
    required Uint8List file,
    required BudgetKey key,
  }) async {
    if (file.length < _headerLength + _nonceLength + _macLength ||
        !_hasHeader(file)) {
      throw const SyncException('Not a sync file');
    }
    final header = file.sublist(0, _headerLength);
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
        aad: [...header, ...utf8.encode(name)],
      );
    } on SecretBoxAuthenticationError {
      throw const SyncException('Wrong Budget Key, or the file was changed');
    }
    return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
  }

  static bool _hasHeader(Uint8List file) {
    for (var i = 0; i < _magic.length; i++) {
      if (file[i] != _magic[i]) return false;
    }
    return file[_magic.length] == _version;
  }
}
