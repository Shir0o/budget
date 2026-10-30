import 'dart:convert';

import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

BudgetEngine _engine() => BudgetEngine(
  log: InMemoryEventLog(),
  deviceId: 'device-a',
  actor: Actor.userAndroid,
);

/// A synthetic budget: Home, a checking account that starts at 4,210.55,
/// and a 3,000.00 paycheck whose payee needs CSV quoting.
BudgetEngine _home() {
  final engine = _engine();
  engine.execute(const CreateBudget(name: 'Home'));
  engine.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: const Money(421055),
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  engine.execute(
    RecordIncome(
      accountId: engine.state.accounts.single.id,
      amount: const Money(300000),
      date: CivilDate(2026, 11, 5),
      payee: 'Acme, "Inc"',
    ),
  );
  return engine;
}

void main() {
  group('transactionsCsv', () {
    test('writes a header and one row per line, quoting where needed', () {
      final engine = _home();
      final ids = engine.state.transactions.map((t) => t.id).toList();

      expect(
        transactionsCsv(engine.state),
        'Transaction ID,Date,Account,Payee,Category,Amount\r\n'
        '${ids[0]},2026-11-01,Checking,Starting Balance,Ready to Assign,4210.55\r\n'
        '${ids[1]},2026-11-05,Checking,"Acme, ""Inc""",Ready to Assign,3000.00\r\n',
      );
    });

    test('is just the header for an empty budget', () {
      expect(
        transactionsCsv(BudgetState.replay(const [])),
        'Transaction ID,Date,Account,Payee,Category,Amount\r\n',
      );
    });
  });

  group('assignmentsCsv', () {
    test('uses the YNAB Plan columns', () {
      expect(
        assignmentsCsv(_home().state),
        'Month,Category Group/Category,Category Group,Category,Assigned\r\n',
      );
    });
  });

  group('stateJson', () {
    test('holds the whole current state in cents', () {
      final engine = _home();
      final json = jsonDecode(stateJson(engine.state)) as Map;

      expect(json['format'], 'budget-state');
      expect((json['budget'] as Map)['name'], 'Home');
      expect(
        (json['accounts'] as List).single,
        containsPair('name', 'Checking'),
      );
      final transactions = (json['transactions'] as List).cast<Map>();
      expect(transactions.map((t) => t['payee']), [
        'Starting Balance',
        'Acme, "Inc"',
      ]);
      expect(transactions.last['amountCents'], 300000);
      expect(
        ((transactions.last['lines'] as List).single as Map)['category'],
        readyToAssignCategory,
      );
      expect(json['readyToAssignCents'], 721055);
    });
  });
}
