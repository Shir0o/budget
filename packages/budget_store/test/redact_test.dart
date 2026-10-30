import 'dart:convert';
import 'dart:io';

import 'package:budget_core/budget_core.dart';
import 'package:budget_store/budget_store.dart';
import 'package:test/test.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('budget_store_redact');
    path = '${dir.path}/budget.db';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('a redaction rewrites the store, and a reopen sees only it', () {
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
      CreateTransaction(
        accountId: checking,
        date: CivilDate(2026, 11, 12),
        amount: const Money(-4820),
        payee: 'Sunset Storage',
        memo: 'Gate code 7781',
        lines: [const LineInput(amount: Money(-4820))],
      ),
    );
    final transactionId = engine.state.transactions
        .firstWhere((transaction) => transaction.payee == 'Sunset Storage')
        .id;

    final result = engine.execute(
      RedactField(
        targets: [
          RedactTarget(EntityRef.transaction(transactionId), 'payee'),
          RedactTarget(EntityRef.transaction(transactionId), 'memo'),
        ],
      ),
    );
    expect(result, isA<Accepted>());
    expect(
      store.readAll().map((event) => jsonEncode(event.toJson())),
      everyElement(
        allOf(
          isNot(contains('Sunset Storage')),
          isNot(contains('Gate code 7781')),
        ),
      ),
    );
    store.close();

    final reopened = SqlCipherEventLog.open(path, keyHex: _key);
    addTearDown(reopened.close);
    final events = reopened.readAll();
    final transaction = BudgetState.replay(events).transaction(transactionId)!;
    expect(transaction.payee, redactedValue);
    expect(transaction.memo, redactedValue);
    expect(events, hasLength(engine.events.length));
    expect(
      events.where((event) => event.type == EventType.redacted),
      hasLength(1),
    );

    final wholeFile = File(path).readAsStringSync(encoding: latin1);
    expect(wholeFile, isNot(contains('Sunset Storage')));
    expect(wholeFile, isNot(contains('Gate code 7781')));
    expect(wholeFile, isNot(contains(redactedValue)));
  });

  test('rewriting Events the store does not have changes nothing', () {
    final store = SqlCipherEventLog.open(path, keyHex: _key);
    addTearDown(store.close);
    final engine = BudgetEngine(
      log: store,
      deviceId: 'device-a',
      actor: Actor.userAndroid,
    );
    engine.execute(const CreateBudget(name: 'Home'));
    final before = store.readAll().map((event) => jsonEncode(event.toJson()));
    store.rewrite([
      Event(
        id: 'unknown',
        budgetId: engine.state.budget!.id,
        deviceId: 'device-a',
        hlc: const Hlc(1, 0, 'device-a'),
        actor: Actor.userAndroid,
        groupId: 'unknown',
        type: EventType.budgetCreated,
        payload: const {'name': redactedValue},
      ),
    ]);
    expect(store.readAll().map((event) => jsonEncode(event.toJson())), before);
  });
}
