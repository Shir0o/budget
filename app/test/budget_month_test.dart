import 'package:budget/app.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BudgetEngine _engine(EventLog log) =>
    BudgetEngine(log: log, deviceId: 'test-device', actor: Actor.userAndroid);

String _id(CommandResult result, String field) =>
    (result as Accepted).events.single.payload[field] as String;

/// A budget with $500.00 in checking and an Everyday group holding
/// Groceries and Dining out.
final class _Seed {
  _Seed() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
        asOf: CivilDate(month.year, month.month, 1),
      ),
    );
    final everyday = _id(
      engine.execute(const CreateCategoryGroup(name: 'Everyday')),
      'categoryGroupId',
    );
    groceries = _id(
      engine.execute(CreateCategory(groupId: everyday, name: 'Groceries')),
      'categoryId',
    );
    dining = _id(
      engine.execute(CreateCategory(groupId: everyday, name: 'Dining out')),
      'categoryId',
    );
  }

  final log = InMemoryEventLog();
  late final engine = _engine(log);
  final month = thisMonth();
  late final String groceries;
  late final String dining;

  void assign(String categoryId, int cents, {CalendarMonth? month}) =>
      engine.execute(
        SetAssignment(
          categoryId: categoryId,
          month: month ?? this.month,
          amount: Money(cents),
        ),
      );

  /// No command records spending until ticket 03, so this writes the
  /// TransactionCreated Event a spend from checking produces.
  void spend(String categoryId, int cents) => log.append([
    Event(
      id: newId(),
      budgetId: engine.state.budget!.id,
      deviceId: 'test-device',
      hlc: Hlc(engine.events.last.hlc.wallMs + 1, 0, 'test-device'),
      actor: Actor.userAndroid,
      groupId: newId(),
      type: EventType.transactionCreated,
      payload: {
        'transactionId': newId(),
        'accountId': engine.state.accounts.single.id,
        'date': CivilDate(month.year, month.month, 1).toIso(),
        'payee': 'Corner Bistro',
        'amountCents': -cents,
        'lines': [
          {'lineId': newId(), 'amountCents': -cents, 'category': categoryId},
        ],
      },
    ),
  ]);

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine(log));

  BudgetState get state => BudgetState.replay(log.readAll());
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _assign(WidgetTester tester, String amount) async {
  await _tap(tester, find.text('Assign'));
  await tester.enterText(find.byKey(const ValueKey('assign-amount')), amount);
  await _tap(tester, find.text('Save'));
}

void main() {
  testWidgets('adds a Category and assigns to it from Ready to Assign', (
    tester,
  ) async {
    final log = InMemoryEventLog();
    final engine = _engine(log);
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
        asOf: today(),
      ),
    );
    await tester.pumpWidget(BudgetApp(engine: _engine(log)));

    expect(find.text('Budget'), findsOneWidget); // the bottom nav
    await _tap(tester, find.text('Add category'));
    await tester.enterText(find.byKey(const ValueKey('group-name')), 'Bills');
    await tester.enterText(find.byKey(const ValueKey('category-name')), 'Rent');
    await _tap(tester, find.text('Save'));

    expect(find.text('Bills'), findsOneWidget);
    await _tap(tester, find.text('Rent'));
    expect(find.text('Bills · ${formatMonth(thisMonth())}'), findsOneWidget);
    await _assign(tester, '300');

    expect(find.text('\$300.00'), findsOneWidget); // Available
    expect(find.text('+ 300.00'), findsOneWidget);
    await _tap(tester, find.byTooltip('Back to budget'));

    expect(find.text('\$200.00'), findsOneWidget);
    final state = BudgetState.replay(log.readAll());
    final rent = state.categories.single;
    expect(state.categoryGroup(rent.groupId)?.name, 'Bills');
    expect(state.assigned(rent.id, thisMonth()), const Money(30000));
  });

  testWidgets('assigning ahead reduces Ready to Assign right away', (
    tester,
  ) async {
    final seed = _Seed();
    await tester.pumpWidget(seed.app());

    expect(find.text('\$500.00'), findsOneWidget);
    await _tap(tester, find.byTooltip('Next month'));
    expect(find.text(formatMonth(seed.month.next)), findsOneWidget);
    await _tap(tester, find.text('Groceries'));
    await _assign(tester, '120');
    await _tap(tester, find.byTooltip('Back to budget'));

    expect(find.text('\$380.00'), findsOneWidget);
    expect(
      seed.state.assigned(seed.groceries, seed.month.next),
      const Money(12000),
    );

    // This month's Groceries still has nothing assigned.
    await _tap(tester, find.byTooltip('Previous month'));
    expect(find.text('\$380.00'), findsOneWidget);
    expect(find.text('120.00'), findsNothing);
  });

  testWidgets('moving money covers overspending and leaves Ready to Assign '
      'unchanged', (tester) async {
    final seed = _Seed();
    seed.assign(seed.groceries, 6000);
    seed.assign(seed.dining, 2000);
    seed.spend(seed.dining, 5000);
    await tester.pumpWidget(seed.app());

    expect(find.text('\$420.00'), findsOneWidget);
    expect(find.text('−30.00'), findsOneWidget);
    expect(
      find.text(
        'Overspent · comes out of ${monthName(seed.month.next)}’s '
        'Ready to Assign',
      ),
      findsOneWidget,
    );

    await _tap(tester, find.text('Groceries'));
    await _tap(tester, find.text('Move money'));
    await _tap(tester, find.text('Choose a Category'));
    await _tap(tester, find.text('Dining out'));
    await _tap(tester, find.text('Cover overspending'));

    expect(find.text('60.00 → 30.00'), findsOneWidget);
    expect(find.text('−30.00 → 0.00'), findsOneWidget);
    expect(find.text('Ready to Assign doesn’t change.'), findsOneWidget);
    await _tap(tester, find.text('Move \$30.00'));

    expect(find.text('\$30.00'), findsOneWidget); // Groceries Available
    await _tap(tester, find.byTooltip('Back to budget'));
    expect(find.text('\$420.00'), findsOneWidget);
    expect(find.textContaining('Overspent'), findsNothing);
    expect(seed.state.available(seed.dining, seed.month), Money.zero);
  });

  testWidgets('shows over-assigned when Ready to Assign is negative', (
    tester,
  ) async {
    final seed = _Seed();
    seed.assign(seed.groceries, 65000);
    await tester.pumpWidget(seed.app());

    expect(find.text('−\$150.00'), findsOneWidget);
    expect(find.text('Over-assigned'), findsOneWidget);
  });

  testWidgets('archiving is blocked until the Available is 0.00', (
    tester,
  ) async {
    final seed = _Seed();
    seed.assign(seed.groceries, 6000);
    await tester.pumpWidget(seed.app());

    await _tap(tester, find.text('Groceries'));
    await _tap(tester, find.byTooltip('Category options'));
    await _tap(tester, find.text('Archive category'));
    expect(find.text('Move its money first'), findsOneWidget);
    await _tap(tester, find.text('OK'));
    expect(seed.state.category(seed.groceries)?.archived, isFalse);
    await _tap(tester, find.byTooltip('Back to budget'));

    await _tap(tester, find.text('Dining out'));
    await _tap(tester, find.byTooltip('Category options'));
    await _tap(tester, find.text('Archive category'));

    expect(find.text('Dining out', skipOffstage: false), findsNothing);
    // Scrolled out of view by the tap on Dining out, but still listed.
    expect(find.text('Groceries', skipOffstage: false), findsOneWidget);
    expect(seed.state.category(seed.dining)?.archived, isTrue);
  });
}
