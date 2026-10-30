import 'package:budget/app.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Checking at 500.00 (cleared), with a cleared 20.00
/// purchase, so the app's cleared balance is 480.00.
final class _Seed {
  _Seed() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
        asOf: today(),
      ),
    );
    final account = engine.state.accounts.single.id;
    final created = engine.execute(
      CreateTransaction(
        accountId: account,
        date: today(),
        amount: const Money(-2000),
        payee: 'Corner cafe',
        lines: [const LineInput(amount: Money(-2000))],
      ),
    ) as Accepted;
    purchase = created.events.single.payload['transactionId'] as String;
    engine.execute(
      EditTransaction(transactionId: purchase, cleared: ClearedStatus.cleared),
    );
  }

  final log = InMemoryEventLog();
  late final engine = _engine();
  late final String purchase;

  BudgetEngine _engine() =>
      BudgetEngine(log: log, deviceId: 'test-device', actor: Actor.userAndroid);

  Widget app() => BudgetApp(engine: _engine());

  BudgetState get state => BudgetState.replay(log.readAll());
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openReconcile(WidgetTester tester) async {
  await _tap(tester, find.text('Accounts'));
  await _tap(tester, find.text('Checking'));
  await _tap(tester, find.text('Reconcile'));
}

Future<void> _enterBalance(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('reconcile-balance')), text);
  await tester.pump();
}

void main() {
  testWidgets('a matching balance reconciles the cleared transactions', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());
    await _openReconcile(tester);

    expect(find.text('Reconcile Checking'), findsOneWidget);
    expect(find.text('Check 2 cleared transactions'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Reconcile'))
          .onPressed,
      isNull,
    );

    await _enterBalance(tester, '480.00');
    await _tap(tester, find.widgetWithText(FilledButton, 'Reconcile'));

    expect(
      seed.state.transaction(seed.purchase)!.cleared,
      ClearedStatus.reconciled,
    );
    expect(find.text('Reconcile Checking'), findsNothing);
  });

  testWidgets('a mismatch offers an adjustment to Ready to Assign', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());
    await _openReconcile(tester);

    await _enterBalance(tester, '475.00');
    expect(find.text('−5.00'), findsOneWidget); // The Difference row.
    final adjust = find.text('Add −5.00 adjustment and reconcile');
    expect(adjust, findsOneWidget);
    await _tap(tester, adjust);

    final adjustment = seed.state.transactions.firstWhere(
      (t) => t.payee == 'Reconciliation Adjustment',
    );
    expect(adjustment.amount, const Money(-500));
    expect(adjustment.lines.single.category, readyToAssignCategory);
    expect(adjustment.lines.single.reviewed, isFalse);
    expect(seed.state.clearedBalance(adjustment.accountId), const Money(47500));
  });

  testWidgets('editing a reconciled transaction asks first', (tester) async {
    final seed = _Seed();
    seed.engine.execute(
      Reconcile(
        accountId: seed.state.accounts.single.id,
        date: today(),
        bankBalance: const Money(48000),
      ),
    );
    await _pump(tester, seed.app());
    await _tap(tester, find.text('Accounts'));
    await _tap(tester, find.text('Checking'));
    await _tap(tester, find.text('Corner cafe'));

    await _tap(tester, find.text('Save'));
    expect(find.text('Change a reconciled transaction?'), findsOneWidget);

    await _tap(tester, find.text('Cancel'));
    expect(find.text('Change a reconciled transaction?'), findsNothing);
    expect(find.text('Transaction'), findsOneWidget); // Still editing.

    await _tap(tester, find.text('Save'));
    await _tap(tester, find.text('Change it'));
    expect(find.text('Transaction'), findsNothing);
  });
}
