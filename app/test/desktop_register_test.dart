import 'package:budget/app.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Checking starts at 500.00 with a cleared 20.00 Corner
/// cafe purchase and an uncleared 12.34 Paper & Co. purchase, so its working
/// balance is 467.66 and its cleared balance is 480.00. Visa owes 60.00, and
/// 25.00 spent on it is covered by Groceries, so Visa Payment holds 25.00.
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
    checking = engine.state.accounts.single.id;
    engine.execute(
      AddAccount(
        name: 'Visa',
        type: AccountType.creditCard,
        startingBalance: const Money(-6000),
        asOf: today(),
      ),
    );
    visa = engine.state.accounts.firstWhere((a) => a.name == 'Visa').id;
    final group = _id(
      engine.execute(const CreateCategoryGroup(name: 'Everyday')),
      'categoryGroupId',
    );
    groceries = _id(
      engine.execute(CreateCategory(groupId: group, name: 'Groceries')),
      'categoryId',
    );
    dining = _id(
      engine.execute(CreateCategory(groupId: group, name: 'Dining out')),
      'categoryId',
    );
    engine.execute(
      SetAssignment(
        categoryId: groceries,
        month: thisMonth(),
        amount: const Money(4500),
      ),
    );
    cafe = _add(
      accountId: checking,
      payee: 'Corner cafe',
      cents: 2000,
      category: groceries,
      cleared: true,
    );
    paper = _add(
      accountId: checking,
      payee: 'Paper & Co.',
      cents: 1234,
      category: dining,
    );
    wholeFoods = _add(
      accountId: visa,
      payee: 'Whole Foods',
      cents: 2500,
      category: groceries,
    );
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  late final String checking;
  late final String visa;
  late final String groceries;
  late final String dining;
  late final String cafe;
  late final String paper;
  late final String wholeFoods;

  /// Visa's Card Payment Category.
  String get visaPayment => engine.state.cardPaymentCategory(visa)!.id;

  String _add({
    required String accountId,
    required String payee,
    required int cents,
    String? category,
    bool cleared = false,
  }) {
    final id = _id(
      engine.execute(
        CreateTransaction(
          accountId: accountId,
          date: today(),
          amount: Money(-cents),
          payee: payee,
          lines: [
            LineInput(
              amount: Money(-cents),
              category: category,
              business: const Personal(),
            ),
          ],
        ),
      ),
      'transactionId',
    );
    if (cleared) {
      engine.execute(
        EditTransaction(transactionId: id, cleared: ClearedStatus.cleared),
      );
    }
    return id;
  }

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(
    engine: BudgetEngine(
      log: log,
      deviceId: 'test-device',
      actor: Actor.userAndroid,
    ),
  );

  BudgetState get state => BudgetState.replay(log.readAll());
}

String _id(CommandResult result, String field) =>
    (result as Accepted).events.single.payload[field] as String;

/// Pumps [app] in a Mac-sized window, above the desktop breakpoint.
Future<void> _pumpDesktop(
  WidgetTester tester,
  Widget app, {
  Size size = const Size(1280, 820),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Clicks [name] in the sidebar, as the person does.
Future<void> _openAccount(WidgetTester tester, _Seed seed, String name) =>
    _tap(tester, find.byKey(ValueKey('account-${_accountId(seed, name)}')));

String _accountId(_Seed seed, String name) =>
    seed.state.accounts.firstWhere((account) => account.name == name).id;

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// The amount inside a pill keyed [key] (an AvailablePill is not a Text).
String _pillText(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
      ),
    )
    .data!;

Finder _inRow(String transactionId, String text) => find.descendant(
  of: find.byKey(ValueKey('register-row-$transactionId')),
  matching: find.text(text),
);

final _table = find.byKey(const ValueKey('register-table'));
final _sheet = find.byKey(const ValueKey('flow-sheet'));

void main() {
  testWidgets(
    'the sidebar opens Checking with balances and a running balance',
    (tester) async {
      final seed = _Seed();
      await _pumpDesktop(tester, seed.app());
      await _openAccount(tester, seed, 'Checking');

      expect(_table, findsOneWidget);
      expect(_text(tester, 'register-working'), '467.66');
      expect(_text(tester, 'register-cleared'), '480.00');
      expect(_text(tester, 'register-uncleared'), '−12.34');
      expect(find.text('Not reconciled yet'), findsOneWidget);

      // Newest first, with the running balance the engine's math gives.
      expect(seed.state.balance(seed.checking), const Money(46766));
      expect(_text(tester, 'register-running-${seed.paper}'), '467.66');
      expect(_text(tester, 'register-running-${seed.cafe}'), '480.00');

      // Date, payee, Category, outflow and the cleared mark on each row.
      expect(
        find.descendant(of: _table, matching: find.text(formatDay(today()))),
        findsNWidgets(3),
      );
      expect(_inRow(seed.paper, 'Paper & Co.'), findsOneWidget);
      expect(_inRow(seed.paper, 'Dining out'), findsOneWidget);
      expect(_inRow(seed.paper, '12.34'), findsOneWidget); // Outflow.
      expect(_inRow(seed.paper, 'Uncleared'), findsOneWidget);
      expect(_inRow(seed.cafe, 'Cleared'), findsOneWidget);
    },
  );

  testWidgets('a narrow desktop window still fits the register', (
    tester,
  ) async {
    final seed = _Seed();
    // Just above the breakpoint: the sidebar leaves about 660 px.
    await _pumpDesktop(tester, seed.app(), size: const Size(900, 700));
    await _openAccount(tester, seed, 'Checking');

    expect(_table, findsOneWidget);
    expect(_text(tester, 'register-working'), '467.66');
    expect(find.widgetWithText(OutlinedButton, 'Reconcile'), findsOneWidget);
  });

  testWidgets('Reconcile opens as a sheet and locks the cleared lines', (
    tester,
  ) async {
    final seed = _Seed();
    await _pumpDesktop(tester, seed.app());
    await _openAccount(tester, seed, 'Checking');

    await _tap(tester, find.widgetWithText(OutlinedButton, 'Reconcile'));
    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.text('Reconcile Checking')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _sheet,
        matching: find.text('Check 2 cleared transactions'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('reconcile-balance')),
      '480.00',
    );
    await tester.pump();
    await _tap(tester, find.widgetWithText(FilledButton, 'Reconcile'));

    expect(_sheet, findsNothing);
    expect(
      seed.state.transaction(seed.cafe)!.cleared,
      ClearedStatus.reconciled,
    );
    // The uncleared line is left alone.
    expect(
      seed.state.transaction(seed.paper)!.cleared,
      ClearedStatus.uncleared,
    );

    expect(
      find.textContaining('Last reconciled ${formatDay(today())}'),
      findsOneWidget,
    );
    expect(_inRow(seed.cafe, 'Reconciled'), findsOneWidget);
    expect(_text(tester, 'register-cleared'), '480.00');
    expect(_text(tester, 'register-uncleared'), '−12.34');
  });

  testWidgets('the card register shows the Card Payment Category Available', (
    tester,
  ) async {
    final seed = _Seed();
    await _pumpDesktop(tester, seed.app());
    await _openAccount(tester, seed, 'Visa');

    expect(_text(tester, 'register-working'), '−85.00');
    expect(find.text('Visa Payment'), findsOneWidget);
    expect(
      seed.state.available(seed.visaPayment, thisMonth()),
      const Money(2500),
    );
    expect(_pillText(tester, 'register-card-available'), '25.00');
    expect(
      find.widgetWithText(OutlinedButton, 'Record payment'),
      findsOneWidget,
    );
  });

  testWidgets('Record payment moves money from Checking to the card', (
    tester,
  ) async {
    final seed = _Seed();
    await _pumpDesktop(tester, seed.app());
    await _openAccount(tester, seed, 'Visa');

    await _tap(tester, find.widgetWithText(OutlinedButton, 'Record payment'));
    expect(_sheet, findsOneWidget);
    expect(find.text('Record a payment to Visa'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('payment-amount')))
          .controller!
          .text,
      '25.00',
    );

    await _tap(tester, find.widgetWithText(FilledButton, 'Record payment'));

    expect(_sheet, findsNothing);
    expect(seed.state.balance(seed.visa), const Money(-6000));
    expect(seed.state.balance(seed.checking), const Money(44266));
    expect(seed.state.available(seed.visaPayment, thisMonth()), Money.zero);
    expect(_pillText(tester, 'register-card-available'), '0.00');
    expect(find.text('Transfer from Checking'), findsOneWidget);
  });
}
