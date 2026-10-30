import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:cryptography/cryptography.dart';

import 'bip39_english.dart';
import 'envelope.dart';

/// The 24-word BIP39 spelling of a Budget Key (ticket 12): the only way back
/// into a budget once every device is lost.
///
/// The key's 32 bytes and one SHA-256 checksum byte are 264 bits, which is
/// 24 words of 11 bits. The words are the key, so they are never logged,
/// never written to the Event log, and shown only when the person asks.
final class RecoveryPhrase {
  const RecoveryPhrase._(this.words, this.key);

  /// BIP39's longest phrase, which is exactly a 256-bit key.
  static const wordCount = 24;
  static const _wordBits = 11;
  static const _refusal = 'That isn’t a recovery phrase';

  /// The phrase that spells [key].
  static Future<RecoveryPhrase> of(BudgetKey key) async {
    final checksum = (await Sha256().hash(key.bytes)).bytes.first;
    final bits = _bits([...key.bytes, checksum]);
    return RecoveryPhrase._([
      for (var word = 0; word < wordCount; word++)
        bip39EnglishWords[_value(bits, word)],
    ], key);
  }

  /// The key [words] spells. Case and extra spaces don't matter, but a
  /// wrong word, a missing word or a bad checksum is refused.
  static Future<RecoveryPhrase> parse(Iterable<String> words) async {
    final list = [
      for (final word in words)
        if (word.trim().isNotEmpty) word.trim().toLowerCase(),
    ];
    if (list.length != wordCount) throw const SyncException(_refusal);
    final bits = <int>[];
    for (final word in list) {
      final index = bip39EnglishWords.indexOf(word);
      if (index < 0) throw const SyncException(_refusal);
      for (var shift = _wordBits - 1; shift >= 0; shift--) {
        bits.add((index >> shift) & 1);
      }
    }
    final bytes = Uint8List.fromList([
      for (var start = 0; start < 256; start += 8) _byte(bits, start),
    ]);
    // The last 8 bits are the first byte of the key's own hash.
    final checksum = (await Sha256().hash(bytes)).bytes.first;
    if (_byte(bits, 256) != checksum) throw const SyncException(_refusal);
    return RecoveryPhrase._(list, BudgetKey.fromBytes(bytes));
  }

  /// The 24 words, in order, lower case.
  final List<String> words;

  /// The key they spell. Never printed.
  final BudgetKey key;

  /// The phrase as one line, which is what a person writes down.
  String get text => words.join(' ');

  /// Never prints the words, which are the key.
  @override
  String toString() => 'RecoveryPhrase(<redacted>)';

  /// Each byte of [bytes] as eight bits, most significant first.
  static List<int> _bits(List<int> bytes) => [
    for (final byte in bytes)
      for (var shift = 7; shift >= 0; shift--) (byte >> shift) & 1,
  ];

  /// One word's 11-bit index: word [word] of [bits].
  static int _value(List<int> bits, int word) {
    var value = 0;
    for (var bit = 0; bit < _wordBits; bit++) {
      value = (value << 1) | bits[word * _wordBits + bit];
    }
    return value;
  }

  /// The byte of [bits] that starts at [start].
  static int _byte(List<int> bits, int start) {
    var byte = 0;
    for (var bit = 0; bit < 8; bit++) {
      byte = (byte << 1) | bits[start + bit];
    }
    return byte;
  }
}
