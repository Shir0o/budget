import 'dart:convert';

import 'package:budget_core/budget_core.dart';

import 'envelope.dart';

/// What one device shows as a QR code so another can join its budget
/// (ticket 12): the Budget Key and the Drive budget id, and nothing else.
///
/// It travels screen to camera, so no server, account or relay of ours is
/// involved. The code is a secret for as long as it is on screen.
final class PairingPayload {
  const PairingPayload({required this.budgetId, required this.key});

  /// The custom scheme the code uses, `budget://pair`.
  static const scheme = 'budget';
  static const _host = 'pair';
  static const _version = 1;
  static const _refusal = 'That isn’t a budget pairing code';

  /// The Drive folder this budget's files live under.
  final String budgetId;

  /// The Budget Key that opens them.
  final BudgetKey key;

  /// What the QR code holds:
  /// `budget://pair?v=1&budget=<id>&key=<base64url of 32 bytes>`.
  String get code => Uri(
    scheme: scheme,
    host: _host,
    queryParameters: {
      'v': '$_version',
      'budget': budgetId,
      'key': base64Url.encode(key.bytes).replaceAll('=', ''),
    },
  ).toString();

  /// Reads a scanned or pasted [code], refusing anything this version can't
  /// use.
  static PairingPayload parse(String code) {
    final uri = Uri.tryParse(code.trim());
    if (uri == null || uri.scheme != scheme || uri.host != _host) {
      throw const SyncException(_refusal);
    }
    final budgetId = uri.queryParameters['budget'];
    final key = uri.queryParameters['key'];
    if (uri.queryParameters['v'] != '$_version' ||
        budgetId == null ||
        budgetId.isEmpty ||
        key == null) {
      throw const SyncException(_refusal);
    }
    final List<int> bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(key));
    } on FormatException {
      throw const SyncException(_refusal);
    }
    if (bytes.length != 32) throw const SyncException(_refusal);
    return PairingPayload(budgetId: budgetId, key: BudgetKey.fromBytes(bytes));
  }

  /// Never prints the key.
  @override
  String toString() => 'PairingPayload($budgetId)';
}
