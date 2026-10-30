import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:test/test.dart';

void main() {
  final key = BudgetKey.generate();
  const name = 'budget-1/device-a/seg-000001.bin';
  const body = <String, Object?>{
    'kind': SyncFileKind.segment,
    'budgetId': 'budget-1',
    'deviceId': 'device-a',
    'seq': 1,
    'events': <Object?>[],
  };

  test('opens with the same name and key', () async {
    final sealed = await SealedFile.seal(name: name, body: body, key: key);
    expect(await SealedFile.open(name: name, file: sealed, key: key), body);
  });

  test('seals nothing readable', () async {
    final sealed = await SealedFile.seal(
      name: name,
      body: {...body, 'payee': 'Corner Bistro'},
      key: key,
    );
    final text = String.fromCharCodes(sealed);
    expect(text, isNot(contains('Corner Bistro')));
    expect(sealed.take(8).toList(), utf8.encode('BUDGETSY'));
  });

  test('refuses a different key', () async {
    final sealed = await SealedFile.seal(name: name, body: body, key: key);
    expect(
      () =>
          SealedFile.open(name: name, file: sealed, key: BudgetKey.generate()),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          'Wrong Budget Key, or the file was changed',
        ),
      ),
    );
  });

  test('refuses a file opened under another name', () async {
    final sealed = await SealedFile.seal(name: name, body: body, key: key);
    expect(
      () => SealedFile.open(
        name: 'budget-1/device-b/seg-000001.bin',
        file: sealed,
        key: key,
      ),
      throwsA(isA<SyncException>()),
    );
  });

  test('refuses a changed byte', () async {
    final sealed = await SealedFile.seal(name: name, body: body, key: key);
    final changed = Uint8List.fromList(sealed)..[sealed.length - 1] ^= 1;
    expect(
      () => SealedFile.open(name: name, file: changed, key: key),
      throwsA(isA<SyncException>()),
    );
  });

  test('refuses something that is not a sync file', () {
    expect(
      () => SealedFile.open(name: name, file: Uint8List(4), key: key),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          'Not a sync file',
        ),
      ),
    );
  });
}
