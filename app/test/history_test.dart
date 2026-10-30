import 'package:budget/app.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Checking with 500.00 in Ready to Assign, and
/// Groceries in Everyday.
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
    group =
        (engine.execute(
              const CreateCategoryGroup(name: 'Everyday'),
            ) as Accepted).events.single.payload['categoryGroupId']
            as String;
    groceries = category('Groceries');
  }

  final log = InMemoryEventLog();
  late final engine = _engine();
  late final String group;
  late final String groceries;

  BudgetEngine _engine() =>
      BudgetEngine(log: log, deviceId: 'test-device', actor: Actor.userAndroid);

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine());

  BudgetState get state => BudgetState.replay(log.readAll());

  String category(String name) =>
      (engine.execute(
            CreateCategory(groupId: group, name: name),
          ) as Accepted).events.single.payload['categoryId']
          as String;

  /// An outflow to Corner Bistro, returning its id.
  String spend({String? categoryId}) =>
      (engine.execute(
            CreateTransaction(
              accountId: state.accounts.single.id,
              date: today(),
              amount: const Money(-4820),
              payee: 'Corner Bistro',
              lines: [
                LineInput(
                  amount: const Money(-4820),
                  category: categoryId ?? groceries,
                ),
              ],
            ),
          ) as Accepted).events.single.payload['transactionId']
          as String;
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

/// The [label] button on the history card that reads [summary].
Finder _button(String summary, String label) => find.descendant(
  of: find
      .ancestor(of: find.text(summary), matching: find.byType(Container))
      .first,
  matching: find.widgetWithText(OutlinedButton, label),
);

void main() {
  testWidgets('History lists changes by day; a revert applies and redoes', (
    tester,
  ) async {
    final seed = _Seed();
    seed.engine.execute(
      SetAssignment(
        categoryId: seed.groceries,
        month: thisMonth(),
        amount: const Money(10000),
      ),
    );
    await _pump(tester, seed.app());

    await _tap(tester, find.text('History'));
    expect(find.text('Change History'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Assigned \$100.00 to Groceries'), findsOneWidget);
    expect(find.text('You'), findsWidgets); // The Actor badge's label
    expect(find.byIcon(Icons.person_outline), findsWidgets); // and icon

    await _tap(tester, _button('Assigned \$100.00 to Groceries', 'Revert'));
    expect(find.text('Undid “Assigned \$100.00 to Groceries”'), findsOneWidget);
    expect(find.text('Revert · by you'), findsOneWidget);
    expect(find.text('Reverted'), findsOneWidget);
    expect(seed.state.assigned(seed.groceries, thisMonth()), Money.zero);

    await _tap(
      tester,
      _button('Undid “Assigned \$100.00 to Groceries”', 'Redo'),
    );
    expect(find.text('Redid “Assigned \$100.00 to Groceries”'), findsOneWidget);
    expect(
      seed.state.assigned(seed.groceries, thisMonth()),
      const Money(10000),
    );

    await _tap(tester, find.text('Bank sync'));
    expect(find.text('No changes yet.'), findsOneWidget);
    await _tap(tester, find.text('Budget'));
    expect(find.text('Home'), findsOneWidget); // the Budget screen
  });

  testWidgets('a field changed again later: Revert anyway or Skip', (
    tester,
  ) async {
    final seed = _Seed();
    final id = seed.spend();
    seed.engine.execute(
      EditTransaction(transactionId: id, payee: 'Bistro', memo: 'Lunch'),
    );
    seed.engine.execute(EditTransaction(transactionId: id, memo: 'Client'));
    await _pump(tester, seed.app());
    await _tap(tester, find.text('History'));

    const first = 'Changed payee and memo of Corner Bistro −48.20';
    await _tap(tester, _button(first, 'Revert'));
    expect(find.text('Changed again later'), findsOneWidget);
    expect(find.text('Skip this field'), findsOneWidget);

    await _tap(tester, find.text('Revert anyway (restore empty)'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Revert'));

    final t = seed.state.transaction(id)!;
    expect(t.payee, 'Corner Bistro');
    expect(t.memo, '');
  });

  testWidgets('later changes that depend on it: Cancel or Revert these too', (
    tester,
  ) async {
    final seed = _Seed();
    final dining = seed.category('Dining out');
    final id = seed.spend(categoryId: dining);
    await _pump(tester, seed.app());
    await _tap(tester, find.text('History'));

    const created = 'Added category Dining out';
    await _tap(tester, _button(created, 'Revert'));
    expect(find.text('Depends on what this created'), findsOneWidget);
    expect(find.text('Added Corner Bistro −48.20 · You'), findsOneWidget);

    await _tap(tester, find.text('Cancel'));
    expect(seed.state.category(dining), isNotNull);

    await _tap(tester, _button(created, 'Revert'));
    await _tap(tester, find.text('Revert these too'));
    expect(seed.state.category(dining), isNull);
    expect(seed.state.transaction(id), isNull);
    expect(
      find.text('Undid “Added category Dining out” and 1 later change'),
      findsOneWidget,
    );
  });

  testWidgets('per-entity history on the register, transaction and category', (
    tester,
  ) async {
    final seed = _Seed();
    final id = seed.spend();
    seed.engine.execute(
      EditTransaction(transactionId: id, memo: 'Client lunch'),
    );
    // A wide screen: the Category screen's breakdown is too wide for 390 px
    // in the test font.
    tester.view.physicalSize = const Size(1440, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(seed.app());

    await _tap(tester, find.text('Accounts'));
    await _tap(tester, find.text('Checking'));
    await _tap(tester, find.text('History'));
    expect(find.text('Set memo of Corner Bistro −48.20'), findsOneWidget);
    expect(find.text('Added account Checking'), findsOneWidget);
    expect(find.text('Added category Groceries'), findsNothing);

    await _tap(tester, find.text('Transactions'));
    await _tap(tester, find.text('Corner Bistro'));
    expect(find.textContaining('Created by you · '), findsOneWidget);
    expect(find.textContaining('Last changed by you · '), findsOneWidget);
    await _tap(tester, find.text('See Change History'));
    expect(find.text('Change History'), findsOneWidget);
    expect(find.text('Added Corner Bistro −48.20'), findsOneWidget);
    expect(find.text('Added account Checking'), findsNothing);

    await _tap(tester, find.byTooltip('Back'));
    await _tap(tester, find.byTooltip('Close'));
    await _tap(tester, find.byTooltip('Back'));
    await _tap(tester, find.text('Budget'));
    await _tap(tester, find.text('Groceries'));
    await _tap(tester, find.byTooltip('Category options'));
    await _tap(tester, find.text('Change History'));
    expect(find.text('Added category Groceries'), findsOneWidget);
    expect(find.text('Set memo of Corner Bistro −48.20'), findsOneWidget);
  });
}
