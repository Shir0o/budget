import 'package:budget/app.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Checking, Dining out and Groceries, an earlier
/// Reviewed Corner Bistro meal, and two lines bank sync filled in that
/// still need Review.
final class _Seed {
  _Seed() {
    final person = _engine(Actor.userAndroid);
    person.execute(const CreateBudget(name: 'Home'));
    person.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
        asOf: today(),
      ),
    );
    final group =
        (person.execute(
              const CreateCategoryGroup(name: 'Everyday'),
            ) as Accepted).events.single.payload['categoryGroupId']
            as String;
    for (final name in ['Dining out', 'Groceries']) {
      person.execute(CreateCategory(groupId: group, name: name));
    }
    final checking = state.accounts.single.id;
    final week = CivilDate.fromDateTime(
      DateTime.now().subtract(const Duration(days: 7)),
    );
    person.execute(
      CreateTransaction(
        accountId: checking,
        date: week,
        amount: const Money(-3100),
        payee: 'Corner Bistro',
        lines: [
          LineInput(
            amount: const Money(-3100),
            category: categoryId('Dining out'),
            business: const Business('Meals'),
          ),
        ],
      ),
    );
    final bank = _engine(const Actor.fromValue('bank-sync'));
    for (final (payee, cents) in [
      ('Paper & Co.', 8640),
      ('Corner Bistro', 4820),
    ]) {
      bank.execute(
        CreateTransaction(
          accountId: checking,
          date: today(),
          amount: Money(-cents),
          payee: payee,
          lines: [LineInput(amount: Money(-cents))],
        ),
      );
    }
  }

  final log = InMemoryEventLog();

  BudgetEngine _engine(Actor actor) =>
      BudgetEngine(log: log, deviceId: 'test-device', actor: actor);

  Widget app() => BudgetApp(engine: _engine(Actor.userAndroid));

  BudgetState get state => BudgetState.replay(log.readAll());

  String categoryId(String name) =>
      state.categories.firstWhere((c) => c.name == name).id;

  TransactionLine line(String payee, int cents) => state.transactions
      .firstWhere((t) => t.payee == payee && t.amount == Money(-cents))
      .lines
      .single;
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

VoidCallback? _markReviewed(WidgetTester tester) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, 'Mark reviewed'))
    .onPressed;

String _badge(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('Review-badge')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets('the hint fills the fields and only Mark reviewed reviews', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());

    // The badge matches the queue.
    expect(seed.state.reviewQueue, hasLength(2));
    expect(_badge(tester), '2');

    await _tap(tester, find.text('Review'));
    expect(find.text('Corner Bistro'), findsOneWidget);
    expect(find.text('Paper & Co.'), findsOneWidget); // Up next
    expect(_markReviewed(tester), isNull);
    expect(find.text('Pick a category to finish this line'), findsOneWidget);

    await _tap(tester, find.text('Last time: Dining out · Business (Meals)'));
    // The hint applied nothing to the budget yet.
    expect(seed.line('Corner Bistro', 4820).reviewed, isFalse);
    expect(seed.line('Corner Bistro', 4820).category, isNull);
    expect(find.text('Dining out'), findsOneWidget);
    expect(find.text('Meals: 50% deductible · \$24.10'), findsOneWidget);
    expect(_markReviewed(tester), isNotNull);

    await _tap(tester, find.text('Mark reviewed'));
    final line = seed.line('Corner Bistro', 4820);
    expect(line.reviewed, isTrue);
    expect(line.category, seed.categoryId('Dining out'));
    expect(line.business, const Business('Meals'));
    expect(_badge(tester), '1');
    expect(find.text('Paper & Co.'), findsOneWidget);
  });

  testWidgets('a gift line needs a recipient before Mark reviewed', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());
    await _tap(tester, find.text('Review'));

    await _tap(tester, find.byKey(const ValueKey('review-category')));
    await _tap(tester, find.text('Groceries').last);
    expect(
      find.text('Choose Personal or Business to finish this line'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Business'));
    expect(
      find.text('Choose a Business Tag to finish this line'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Gifts'));
    expect(
      find.text('Add who received the gift to finish this line'),
      findsOneWidget,
    );
    expect(_markReviewed(tester), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('review-recipient')),
      'Dana',
    );
    await tester.pump();
    await _tap(tester, find.text('Mark reviewed'));

    final line = seed.line('Corner Bistro', 4820);
    expect(line.reviewed, isTrue);
    expect(line.recipient, 'Dana');
  });

  testWidgets('shows All caught up when nothing is left', (tester) async {
    final seed = _Seed();
    final engine = BudgetEngine(
      log: seed.log,
      deviceId: 'test-device',
      actor: Actor.userAndroid,
    );
    for (final item in engine.state.reviewQueue) {
      engine.execute(
        ReviewLine(
          transactionId: item.transaction.id,
          lineId: item.line.id,
          category: seed.categoryId('Groceries'),
          business: const Personal(),
        ),
      );
    }
    await _pump(tester, seed.app());

    expect(find.byKey(const ValueKey('Review-badge')), findsNothing);
    await _tap(tester, find.text('Review'));
    expect(find.text('All caught up'), findsOneWidget);
  });
}
