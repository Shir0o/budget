import 'package:budget/app.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Checking with 500.00 in Ready to Assign, and
/// Groceries and Household in Everyday.
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
    final group =
        (engine.execute(
              const CreateCategoryGroup(name: 'Everyday'),
            ) as Accepted).events.single.payload['categoryGroupId']
            as String;
    for (final name in ['Groceries', 'Household']) {
      engine.execute(CreateCategory(groupId: group, name: name));
    }
  }

  final log = InMemoryEventLog();
  late final engine = _engine();

  BudgetEngine _engine() =>
      BudgetEngine(log: log, deviceId: 'test-device', actor: Actor.userAndroid);

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine());

  BudgetState get state => BudgetState.replay(log.readAll());

  String categoryId(String name) =>
      state.categories.firstWhere((c) => c.name == name).id;
}

/// Pumps [app] on a phone-sized screen, like the canvas's 390 × 844.
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

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(ValueKey(key)), text);
  await tester.pump();
}

VoidCallback? _saveButton(WidgetTester tester) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
    .onPressed;

void main() {
  testWidgets('enters a Reviewed outflow and lists it in the register', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());

    await _tap(tester, find.text('Accounts'));
    await _tap(tester, find.text('Checking'));
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('500.00'), findsNWidgets(2)); // Balance and Cleared

    await _tap(tester, find.byTooltip('New transaction'));
    await _enter(tester, 'transaction-amount', '12.50');
    await _enter(tester, 'transaction-payee', 'Farmers market');
    expect(
      find.text(
        'Set a Category and Personal or Business to save it as Reviewed.',
      ),
      findsOneWidget,
    );
    await _tap(tester, find.text('Choose'));
    expect(find.text('Category for Farmers market'), findsOneWidget);
    expect(find.text('Ready to Assign (income)'), findsOneWidget);
    await _tap(tester, find.text('Groceries'));
    await _tap(tester, find.text('Personal'));
    expect(
      find.text('Category and Personal are set, so it saves as Reviewed.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Save'));

    expect(find.text('Farmers market'), findsOneWidget);
    expect(
      find.text('${formatDay(today())} · Groceries · Uncleared'),
      findsOneWidget,
    );
    expect(find.text('−12.50'), findsOneWidget);
    expect(find.text('487.50'), findsOneWidget); // Balance
    expect(find.text('500.00'), findsOneWidget); // Cleared

    final transaction = seed.state.transactions.last;
    expect(transaction.amount, const Money(-1250));
    expect(transaction.lines.single.category, seed.categoryId('Groceries'));
    expect(transaction.lines.single.business, const Personal());
    expect(transaction.lines.single.reviewed, isTrue);
  });

  testWidgets('a split saves only once Left to split reaches 0.00', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());

    await _tap(tester, find.text('New transaction'));
    await _enter(tester, 'transaction-amount', '120');
    await _enter(tester, 'transaction-payee', 'Target');
    await _tap(tester, find.text('Choose'));
    await _tap(tester, find.text('Groceries'));
    await _tap(tester, find.text('Personal'));
    await _tap(tester, find.text('Split'));

    // The first line takes the whole amount.
    expect(find.text('Left to split 0.00'), findsOneWidget);
    await _tap(tester, find.text('Groceries'));
    await _enter(tester, 'line-amount', '80');
    await _tap(tester, find.text('Done'));
    expect(find.text('Left to split 40.00'), findsOneWidget);
    expect(_saveButton(tester), isNull);

    await _tap(tester, find.text('Add line'));
    await _tap(tester, find.byKey(const ValueKey('line-category')));
    await _tap(tester, find.text('Household'));
    await _tap(tester, find.text('Business'));
    await _tap(tester, find.text('Supplies'));
    await _enter(tester, 'line-memo', 'printer paper');
    await _tap(tester, find.text('Done'));

    expect(find.text('Left to split 0.00'), findsOneWidget);
    expect(find.text('Business · Supplies'), findsOneWidget);
    expect(find.text('Memo: printer paper'), findsOneWidget);
    expect(_saveButton(tester), isNotNull);
    await _tap(tester, find.text('Save'));

    final transaction = seed.state.transactions.last;
    expect(transaction.amount, const Money(-12000));
    expect(transaction.lines.map((l) => (l.category, l.amount, l.memo)), [
      (seed.categoryId('Groceries'), const Money(-8000), ''),
      (seed.categoryId('Household'), const Money(-4000), 'printer paper'),
    ]);
    expect(transaction.lines.last.business, const Business('Supplies'));
    final month = thisMonth();
    expect(
      seed.state.activity(seed.categoryId('Household'), month),
      const Money(-4000),
    );
  });

  testWidgets('memo and payee refuse account numbers', (tester) async {
    final seed = _Seed();
    await _pump(tester, seed.app());
    final before = seed.log.readAll().length;

    await _tap(tester, find.text('New transaction'));
    await _enter(tester, 'transaction-amount', '9.75');
    await _enter(tester, 'transaction-payee', 'Corner Store');
    await _enter(tester, 'transaction-memo', 'card 4111 1111 1111 1111');
    await _tap(tester, find.text('Save'));

    expect(find.text(accountNumberMessage), findsOneWidget);
    expect(find.text('New transaction'), findsOneWidget);
    expect(seed.log.readAll(), hasLength(before));

    await _enter(tester, 'transaction-memo', '');
    await _enter(tester, 'transaction-payee', 'acct 12345678');
    await _tap(tester, find.text('Save'));
    expect(seed.log.readAll(), hasLength(before));

    await _enter(tester, 'transaction-payee', 'Corner Store');
    await _tap(tester, find.text('Save'));
    expect(seed.log.readAll(), hasLength(before + 1));
  });

  testWidgets('an uncategorized outflow reduces Ready to Assign', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());
    expect(find.text('\$500.00'), findsOneWidget);

    await _tap(tester, find.text('New transaction'));
    await _enter(tester, 'transaction-amount', '9.75');
    await _tap(tester, find.text('Save'));

    expect(find.text('\$490.25'), findsOneWidget);
    expect(seed.state.transactions.last.lines.single.reviewed, isFalse);
  });

  testWidgets('the Transaction screen edits lines and the cleared status', (
    tester,
  ) async {
    final seed = _Seed();
    seed.engine.execute(
      CreateTransaction(
        accountId: seed.state.accounts.single.id,
        date: today(),
        amount: const Money(-8640),
        payee: 'Paper & Co.',
        lines: [
          LineInput(
            amount: const Money(-8640),
            category: seed.categoryId('Groceries'),
            business: const Personal(),
          ),
        ],
      ),
    );
    await _pump(tester, seed.app());

    await _tap(tester, find.text('Accounts'));
    await _tap(tester, find.text('Checking'));
    await _tap(tester, find.text('Paper & Co.'));
    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('−86.40'), findsWidgets);
    expect(find.text('Uncleared'), findsOneWidget);

    await _tap(tester, find.text('Uncleared'));
    expect(find.text('Cleared'), findsOneWidget);
    await _tap(tester, find.text('Groceries'));
    await _enter(tester, 'line-amount', '64.40');
    await _tap(tester, find.text('Done'));
    expect(find.text('Left to split 22.00'), findsOneWidget);
    expect(_saveButton(tester), isNull);

    await _tap(tester, find.text('Add line'));
    await _tap(tester, find.byKey(const ValueKey('line-category')));
    await _enter(tester, 'category-search', 'house');
    expect(find.text('Ready to Assign (income)'), findsNothing);
    await _tap(tester, find.text('Household'));
    await _tap(tester, find.text('Personal').last);
    await _tap(tester, find.text('Done'));
    expect(find.text('Split · 2 lines'), findsOneWidget);
    await _tap(tester, find.text('Save'));

    expect(find.textContaining('Split · 2 · Cleared'), findsOneWidget);
    final transaction = seed.state.transactions.last;
    expect(transaction.cleared, ClearedStatus.cleared);
    expect(transaction.lines.map((l) => l.amount), [
      const Money(-6440),
      const Money(-2200),
    ]);
  });

  testWidgets('deletes a transaction after asking', (tester) async {
    final seed = _Seed();
    seed.engine.execute(
      CreateTransaction(
        accountId: seed.state.accounts.single.id,
        date: today(),
        amount: const Money(-975),
        payee: 'Corner Store',
        lines: const [LineInput(amount: Money(-975))],
      ),
    );
    await _pump(tester, seed.app());

    await _tap(tester, find.text('Accounts'));
    await _tap(tester, find.text('Checking'));
    await _tap(tester, find.text('Corner Store'));
    await _tap(tester, find.byTooltip('Transaction options'));
    await _tap(tester, find.text('Delete transaction'));
    await _tap(tester, find.text('Delete'));

    expect(find.text('Corner Store'), findsNothing);
    expect(seed.state.transactions.map((t) => t.payee), ['Starting Balance']);
  });
}
