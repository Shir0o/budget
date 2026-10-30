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
    final group =
        (engine.execute(
              const CreateCategoryGroup(name: 'Everyday'),
            ) as Accepted).events.single.payload['categoryGroupId']
            as String;
    engine.execute(CreateCategory(groupId: group, name: 'Groceries'));
  }

  final log = InMemoryEventLog();
  late final engine = _engine();

  BudgetEngine _engine() =>
      BudgetEngine(log: log, deviceId: 'test-device', actor: Actor.userAndroid);

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine());

  BudgetState get state => BudgetState.replay(log.readAll());

  String accountId(String name) =>
      state.accounts.firstWhere((a) => a.name == name).id;
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

void main() {
  testWidgets('adds a card whose existing balance is unfunded debt', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());

    await _tap(tester, find.text('Accounts'));
    expect(find.textContaining('\$500.00'), findsOneWidget); // Net worth
    await _tap(tester, find.text('Add account'));
    await _tap(tester, find.text('Credit card'));
    expect(find.text('Amount owed'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('account-name')), 'Visa');
    await tester.enterText(
      find.byKey(const ValueKey('account-balance')),
      '642.18',
    );
    await _tap(tester, find.text('Save'));

    expect(find.text('Budget accounts'), findsOneWidget);
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('−642.18'), findsOneWidget);
    expect(find.text('642.18 not funded'), findsOneWidget);
    expect(find.text('−142.18'), findsOneWidget); // Budget accounts total
    expect(
      tester.widget<Text>(find.text('642.18 not funded')).style?.color,
      const Color(0xFF8F3F09),
    );

    // The Budget month shows the Card Payment Category, and Ready to Assign
    // is unchanged.
    await _tap(tester, find.text('Budget'));
    expect(find.text('Credit Card Payments'), findsOneWidget);
    expect(find.text('Visa Payment'), findsOneWidget);
    expect(find.text('\$642.18 of card debt not funded'), findsOneWidget);
    expect(find.text('\$500.00'), findsOneWidget);

    final state = seed.state;
    final visa = seed.accountId('Visa');
    expect(state.account(visa)?.type, AccountType.creditCard);
    expect(state.cardPaymentCategory(visa)?.name, 'Visa Payment');
    expect(state.readyToAssign(thisMonth()), const Money(50000));
  });

  testWidgets('tracking accounts count toward net worth only', (tester) async {
    final seed = _Seed();
    seed.engine.execute(
      AddAccount(
        name: 'Retirement 401k',
        type: AccountType.tracking,
        startingBalance: const Money(4830000),
        asOf: today(),
      ),
    );
    await _pump(tester, seed.app());

    expect(find.text('\$500.00'), findsOneWidget); // Ready to Assign
    await _tap(tester, find.text('Accounts'));
    expect(find.text('Tracking accounts'), findsOneWidget);
    expect(find.text('Net worth only'), findsOneWidget);
    expect(find.text('48,300.00'), findsNWidgets(2)); // Row and subtotal
    expect(find.textContaining('\$48,800.00'), findsOneWidget); // Net worth
  });

  testWidgets('pays a card with a transfer from checking', (tester) async {
    final seed = _Seed();
    seed.engine.execute(
      AddAccount(
        name: 'Visa',
        type: AccountType.creditCard,
        startingBalance: const Money(-6000),
        asOf: today(),
      ),
    );
    await _pump(tester, seed.app());

    await _tap(tester, find.text('New transaction'));
    await _tap(tester, find.text('Transfer'));
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '60',
    );
    await _tap(tester, find.byTooltip('Choose account to transfer to'));
    await _tap(tester, find.text('Visa').last);
    await _tap(tester, find.text('Save'));

    final state = seed.state;
    expect(state.balance(seed.accountId('Visa')), Money.zero);
    expect(state.balance(seed.accountId('Checking')), const Money(44000));

    await _tap(tester, find.text('Accounts'));
    await _tap(tester, find.text('Checking'));
    expect(find.text('Transfer to Visa'), findsOneWidget);
  });
}
