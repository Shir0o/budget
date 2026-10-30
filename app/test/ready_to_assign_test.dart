import 'package:budget/app.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _nov = CalendarMonth(2026, 11);

BudgetEngine _engine(EventLog log) =>
    BudgetEngine(log: log, deviceId: 'test-device', actor: Actor.userAndroid);

Future<void> _saveFirstAccount(WidgetTester tester, String balance) async {
  await tester.tap(find.text('Add your first account'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('account-balance')),
    balance,
  );
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first account and income show up in Ready to Assign', (
    tester,
  ) async {
    final log = InMemoryEventLog();
    await tester.pumpWidget(BudgetApp(engine: _engine(log)));

    expect(find.text('Give every dollar a job'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('budget-name')), 'Home');
    await _saveFirstAccount(tester, '4,210.55');

    // The Starting Balance went to Ready to Assign.
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('\$4,210.55'), findsOneWidget);

    await tester.tap(find.text('Record income'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('income-amount')), '3000');
    await tester.enterText(
      find.byKey(const ValueKey('income-payee')),
      'Employer',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('\$7,210.55'), findsOneWidget);

    // Everything went through the core as Events.
    final state = BudgetState.replay(log.readAll());
    expect(state.budget?.name, 'Home');
    expect(state.accounts.single.name, 'Checking');
    expect(state.transactions.map((t) => t.payee), [
      'Starting Balance',
      'Employer',
    ]);
    expect(state.readyToAssign(_nov), const Money(721055));
  });

  testWidgets('an amount that is not exact cents is refused', (tester) async {
    final log = InMemoryEventLog();
    await tester.pumpWidget(BudgetApp(engine: _engine(log)));

    await _saveFirstAccount(tester, '12.345');

    expect(find.text('Enter an amount like 1,234.56'), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);
    expect(log.readAll(), isEmpty);
  });

  testWidgets('opens on the Budget screen once a budget exists', (
    tester,
  ) async {
    final log = InMemoryEventLog();
    final engine = _engine(log);
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Savings',
        type: AccountType.savings,
        startingBalance: const Money(41200),
        asOf: CivilDate(2026, 11, 1),
      ),
    );

    await tester.pumpWidget(BudgetApp(engine: _engine(log)));

    expect(find.text('Give every dollar a job'), findsNothing);
    expect(find.text('\$412.00'), findsOneWidget);
  });
}
