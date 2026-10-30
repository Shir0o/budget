import 'dart:convert';
import 'dart:io';

import 'package:budget_core/budget_core.dart';
import 'package:budget_store/budget_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('budget_store_test');
    path = '${dir.path}/budget.db';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('append, reopen and replay give the same projection', () {
    final store = SqlCipherEventLog.open(path, keyHex: _key);
    final engine = BudgetEngine(
      log: store,
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
    final checking = engine.state.accounts.single.id;
    engine.execute(
      RecordIncome(
        accountId: checking,
        amount: const Money(300000),
        date: CivilDate(2026, 11, 14),
        payee: 'Employer',
      ),
    );
    final before = engine.state;
    final eventsBefore = engine.events.map((e) => jsonEncode(e.toJson()));
    store.close();

    final reopened = SqlCipherEventLog.open(path, keyHex: _key);
    addTearDown(reopened.close);
    final after = BudgetState.replay(reopened.readAll());

    expect(reopened.readAll().map((e) => jsonEncode(e.toJson())), eventsBefore);
    expect(after.budget, before.budget);
    expect(after.accounts, before.accounts);
    expect(after.readyToAssign, const Money(721055));
    expect(after.readyToAssign, before.readyToAssign);
  });

  test('the file is encrypted and needs the key', () {
    final store = SqlCipherEventLog.open(path, keyHex: _key);
    BudgetEngine(
      log: store,
      deviceId: 'device-a',
      actor: Actor.userAndroid,
    ).execute(const CreateBudget(name: 'Home'));
    store.close();

    final header = File(path).readAsBytesSync().take(15);
    expect(
      ascii.decode(header.toList(), allowInvalid: true),
      isNot('SQLite format 3'),
    );
    expect(
      File(path).readAsStringSync(encoding: latin1),
      isNot(contains('Home')),
    );

    final wrongKey = 'f' * 64;
    expect(
      () => SqlCipherEventLog.open(path, keyHex: wrongKey),
      throwsA(isA<SqliteException>()),
    );
  });
}
