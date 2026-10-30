import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:test/test.dart';

/// A synthetic Budget Key and budget id, so nothing real is written anywhere.
final _key = BudgetKey.fromHex(
  '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
);
const _budgetId = 'b7d3c1e0-4a2f-4c8e-9b1d-5f6a70819233';

void main() {
  group('Pairing code', () {
    test('carries the Budget Key and the budget id, and reads back', () {
      final payload = PairingPayload(budgetId: _budgetId, key: _key);
      expect(payload.code, startsWith('budget://pair?'));

      final scanned = PairingPayload.parse(payload.code);
      expect(scanned.budgetId, _budgetId);
      expect(scanned.key.toHex(), _key.toHex());
    });

    test('holds a version, the budget id and the key, and no readable key', () {
      final code = PairingPayload(budgetId: _budgetId, key: _key).code;
      expect(
        Uri.parse(code).queryParameters.keys,
        unorderedEquals(['v', 'budget', 'key']),
      );
      expect(code, isNot(contains(_key.toHex())));
      // A second code for the same budget and key is the same string.
      expect(code, PairingPayload(budgetId: _budgetId, key: _key).code);
    });

    test('refuses anything that isn’t a current pairing code', () {
      final code = PairingPayload(budgetId: _budgetId, key: _key).code;
      for (final wrong in [
        '',
        'hello',
        'https://example.com/pair?budget=x',
        code.replaceFirst('v=1', 'v=2'),
        code.replaceFirst('budget=', 'budgetId='),
        code.replaceFirst(RegExp('key=[^&]+'), 'key=abc'),
        // 31 bytes, not a 256-bit key.
        code.replaceFirst(RegExp('key=[^&]+'), 'key=${'A' * 42}'),
      ]) {
        expect(
          () => PairingPayload.parse(wrong),
          throwsA(isA<SyncException>()),
          reason: wrong,
        );
      }
    });

    test('never prints the key', () {
      final payload = PairingPayload(budgetId: _budgetId, key: _key);
      expect(payload.toString(), isNot(contains(_key.toHex())));
      expect(payload.toString(), contains(_budgetId));
    });
  });
}
