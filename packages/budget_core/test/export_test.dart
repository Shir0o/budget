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

    test('writes one row per Category per month', () {
      final engine = _home();
      String group(String name) =>
          (engine.execute(
                CreateCategoryGroup(name: name),
              ) as Accepted).events.single.payload['categoryGroupId']
              as String;
      String category(String groupId, String name) =>
          (engine.execute(
                CreateCategory(groupId: groupId, name: name),
              ) as Accepted).events.single.payload['categoryId']
              as String;
      final rent = category(group('Bills'), 'Rent');
      final groceries = category(group('Everyday'), 'Groceries');
      engine.execute(
        SetAssignment(
          categoryId: rent,
          month: CalendarMonth(2026, 11),
          amount: const Money(165000),
        ),
      );
      engine.execute(
        SetAssignment(
          categoryId: groceries,
          month: CalendarMonth(2026, 12),
          amount: const Money(30000),
        ),
      );

      expect(
        assignmentsCsv(engine.state),
        'Month,Category Group/Category,Category Group,Category,Assigned\r\n'
        'Nov 2026,Bills: Rent,Bills,Rent,1650.00\r\n'
        'Nov 2026,Everyday: Groceries,Everyday,Groceries,0.00\r\n'
        'Dec 2026,Bills: Rent,Bills,Rent,0.00\r\n'
        'Dec 2026,Everyday: Groceries,Everyday,Groceries,300.00\r\n',
      );

      final json = jsonDecode(
        stateJson(engine.state, month: CalendarMonth(2026, 11)),
      ) as Map;
      expect((json['categories'] as List).map((c) => (c as Map)['name']), [
        'Rent',
        'Groceries',
      ]);
      expect(json['assignments'], [
        {'category': rent, 'month': '2026-11', 'assignedCents': 165000},
        {'category': groceries, 'month': '2026-12', 'assignedCents': 30000},
      ]);
      expect(json['readyToAssignCents'], 721055 - 165000 - 30000);
    });
  });

  group('stateJson', () {
    test('holds the whole current state in cents', () {
      final engine = _home();
      final json = jsonDecode(
        stateJson(engine.state, month: CalendarMonth(2026, 11)),
      ) as Map;

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
