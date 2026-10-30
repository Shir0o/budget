import 'dart:math';
import 'dart:typed_data';

/// The random 256-bit key that seals one budget's backups, and later its
/// sync files (ticket 12). It lives in secure storage, never in the Event
/// log.
final class BudgetKey {
  BudgetKey.fromBytes(List<int> bytes) : bytes = Uint8List.fromList(bytes) {
    if (bytes.length != 32) {
      throw ArgumentError.value('<redacted>', 'bytes', 'Need 32 bytes');
    }
  }

  /// 256 bits from the platform's secure random source.
  factory BudgetKey.generate() {
    final random = Random.secure();
    return BudgetKey.fromBytes([
      for (var i = 0; i < 32; i++) random.nextInt(256),
    ]);
  }

  /// Restores a key from the 64 hex digits [toHex] wrote.
  factory BudgetKey.fromHex(String hex) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw ArgumentError.value('<redacted>', 'hex', 'Need 64 hex digits');
    }
    return BudgetKey.fromBytes([
      for (var i = 0; i < 64; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  final Uint8List bytes;

  String toHex() =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Never prints the key.
  @override
  String toString() => 'BudgetKey(<redacted>)';
}
