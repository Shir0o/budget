import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

List<Event> _events() {
  final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'device-a',
    actor: Actor.userAndroid,
  );
  engine.execute(const CreateBudget(name: 'Home'));
  engine.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: const Money(421055),
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  return engine.events;
}

void main() {
  group('BudgetKey', () {
    test('is 256 random bits that round-trip through hex', () {
      final key = BudgetKey.generate();

      expect(key.bytes, hasLength(32));
      expect(BudgetKey.fromHex(key.toHex()).bytes, key.bytes);
      expect(BudgetKey.generate().toHex(), isNot(key.toHex()));
    });

    test('never prints itself', () {
      final key = BudgetKey.generate();
      expect('$key', isNot(contains(key.toHex())));
    });

    test('refuses a key of the wrong size', () {
      expect(() => BudgetKey.fromBytes([1, 2, 3]), throwsArgumentError);
      expect(() => BudgetKey.fromHex('abc'), throwsArgumentError);
    });
  });

  group('Backup', () {
    test('opens with the same key and restores every Event', () async {
      final key = BudgetKey.generate();
      final events = _events();

      final file = await Backup.seal(events, key);
      final restored = await Backup.open(file, key);

      expect(restored.map((e) => e.toJson()), events.map((e) => e.toJson()));
      expect(BudgetState.replay(restored).budget?.name, 'Home');
    });

    test('is encrypted: no plaintext appears in the file', () async {
      final file = await Backup.seal(_events(), BudgetKey.generate());

      expect(latin1.decode(file), isNot(contains('Checking')));
      expect(latin1.decode(file), isNot(contains('Home')));
    });

    test('seals the same Events differently each time', () async {
      final key = BudgetKey.generate();
      final events = _events();

      expect(
        await Backup.seal(events, key),
        isNot(await Backup.seal(events, key)),
      );
    });

    test('refuses a different key', () async {
      final file = await Backup.seal(_events(), BudgetKey.generate());

      expect(
        Backup.open(file, BudgetKey.generate()),
        throwsA(isA<BackupException>()),
      );
    });

    test('refuses a file that was changed', () async {
      final key = BudgetKey.generate();
      final file = await Backup.seal(_events(), key);

      final body = Uint8List.fromList(file)..[file.length ~/ 2] ^= 1;
      final header = Uint8List.fromList(file)..[8] = 2;

      expect(Backup.open(body, key), throwsA(isA<BackupException>()));
      expect(Backup.open(header, key), throwsA(isA<BackupException>()));
    });

    test('refuses something that is not a backup', () {
      expect(
        Backup.open(
          Uint8List.fromList(utf8.encode('hello')),
          BudgetKey.generate(),
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('names files by date', () {
      expect(Backup.fileName('2026-11-01'), 'budget-2026-11-01.budgetbackup');
    });
  });
}
