import 'dart:convert';

import 'package:budget/app.dart';
import 'package:budget/bank_sync.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _accessUrl = 'https://user:pass@bridge.example/simplefin/access/xyz';

/// The bridge's answer: one checking account with a posted Corner Bistro
/// charge for 48.20, dated now so a fresh linked-from date includes it.
String _fetchJson() {
  final posted = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({
    'errors': <String>[],
    'accounts': [
      {
        'org': {'name': 'Sample Bank'},
        'id': 'acct-1',
        'name': 'Everyday Checking ...1234',
        'currency': 'USD',
        'balance': '500.00',
        'available-balance': '500.00',
        'balance-date': posted,
        'transactions': [
          {
            'id': 'tx-1',
            'posted': posted,
            'amount': '-48.20',
            'description': 'CORNER BISTRO',
            'payee': 'Corner Bistro',
          },
        ],
      },
    ],
  });
}

/// A connected book with the bank account linked, so a fetch runs without
/// the claim and link steps.
SimpleFinBook _book(String accountId) => SimpleFinBook(
  accessUrl: _accessUrl,
  links: [
    LinkedAccount(
      simpleFinId: 'acct-1',
      institution: 'Sample Bank',
      name: 'Everyday Checking ...1234',
      linkedFrom: today().addDays(-30),
      accountId: accountId,
    ),
  ],
);

AppServices _services() => AppServices(
  keys: InMemoryBudgetKeyStore(),
  prefs: InMemoryDevicePrefs(),
  saver: InMemoryFileSaver(),
  authenticator: FakeAuthenticator(),
  simpleFin: FakeSimpleFinTransport(
    replies: {
      'GET /simplefin/access/xyz/accounts': SimpleFinReply(200, _fetchJson()),
    },
  ),
);

/// A synthetic budget: Checking, Groceries and Dining out, a Reviewed
/// Green Grocer line, and two lines bank sync left to Review. Paper & Co.
/// already carries a Category that a bank import filled in.
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
    checking = person.state.accounts.single.id;
    final group = _id(
      person.execute(const CreateCategoryGroup(name: 'Everyday')),
      'categoryGroupId',
    );
    groceries = _id(
      person.execute(CreateCategory(groupId: group, name: 'Groceries')),
      'categoryId',
    );
    dining = _id(
      person.execute(CreateCategory(groupId: group, name: 'Dining out')),
      'categoryId',
    );
    person.execute(
      CreateTransaction(
        accountId: checking,
        date: today(),
        amount: const Money(-2500),
        payee: 'Green Grocer',
        lines: [
          LineInput(
            amount: const Money(-2500),
            category: groceries,
            business: const Personal(),
          ),
        ],
      ),
    );
    final bank = _engine(const Actor.fromValue('bank-sync'));
    paper = _add(bank, 'Paper & Co.', 8640, category: groceries);
    cafe = _add(bank, 'Cafe', 1200);
  }

  final log = InMemoryEventLog();
  late final String checking;
  late final String groceries;
  late final String dining;
  late final String paper;
  late final String cafe;

  BudgetEngine _engine(Actor actor) =>
      BudgetEngine(log: log, deviceId: 'test-device', actor: actor);

  String _add(
    BudgetEngine engine,
    String payee,
    int cents, {
    String? category,
  }) => _id(
    engine.execute(
      CreateTransaction(
        accountId: checking,
        date: today(),
        amount: Money(-cents),
        payee: payee,
        lines: [LineInput(amount: Money(-cents), category: category)],
      ),
    ),
    'transactionId',
  );

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine(Actor.userAndroid));

  BudgetState get state => BudgetState.replay(log.readAll());
}

/// A synthetic budget with one hand-entered Corner Bistro meal that a bank
/// charge will look like.
final class _MatchSeed {
  _MatchSeed() {
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
    final group = _id(
      engine.execute(const CreateCategoryGroup(name: 'Everyday')),
      'categoryGroupId',
    );
    final dining = _id(
      engine.execute(CreateCategory(groupId: group, name: 'Dining out')),
      'categoryId',
    );
    hand = _id(
      engine.execute(
        CreateTransaction(
          accountId: checking,
          date: today().addDays(-2),
          amount: const Money(-4820),
          payee: 'Corner Bistro',
          memo: 'Team lunch',
          lines: [
            LineInput(
              amount: const Money(-4820),
              category: dining,
              business: const Personal(),
            ),
          ],
        ),
      ),
      'transactionId',
    );
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  late final String checking;
  late final String hand;
}

/// A synthetic budget where a later transaction depends on a Category that
/// was added earlier, so reverting the Category needs the conflict sheet.
final class _RevertSeed {
  _RevertSeed() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
        asOf: today(),
      ),
    );
    final group = _id(
      engine.execute(const CreateCategoryGroup(name: 'Everyday')),
      'categoryGroupId',
    );
    dining = _id(
      engine.execute(CreateCategory(groupId: group, name: 'Dining out')),
      'categoryId',
    );
    spend = _id(
      engine.execute(
        CreateTransaction(
          accountId: engine.state.accounts.single.id,
          date: today(),
          amount: const Money(-4820),
          payee: 'Corner Bistro',
          lines: [LineInput(amount: const Money(-4820), category: dining)],
        ),
      ),
      'transactionId',
    );
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  late final String dining;
  late final String spend;

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

Future<void> _pumpDesktop(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1280, 820);
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

Future<void> _openReview(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('section-review')));
}

final _list = find.byKey(const ValueKey('review-list'));
final _detail = find.byKey(const ValueKey('review-detail'));
final _sheet = find.byKey(const ValueKey('flow-sheet'));

Finder _inList(String text) =>
    find.descendant(of: _list, matching: find.text(text));

Finder _inDetail(String text) =>
    find.descendant(of: _detail, matching: find.text(text));

Finder _row(String transactionId, String lineId) =>
    find.byKey(ValueKey('review-row-$transactionId/$lineId'));

/// The [label] button on the history card that reads [summary].
Finder _historyButton(String summary, String label) => find.descendant(
  of: find
      .ancestor(of: find.text(summary), matching: find.byType(Container))
      .first,
  matching: find.widgetWithText(OutlinedButton, label),
);

void main() {
  testWidgets('Review lists the lines and starts the panel empty', (
    tester,
  ) async {
    final seed = _Seed();
    await _pumpDesktop(tester, seed.app());
    await _openReview(tester);

    expect(_list, findsOneWidget);
    expect(_detail, findsOneWidget);
    expect(_inList('Cafe'), findsOneWidget);
    expect(_inList('Paper & Co.'), findsOneWidget);
    // The reviewed line is not in To review.
    expect(_inList('Green Grocer'), findsNothing);
    // The first line in the queue is selected, and its panel is empty.
    expect(_inDetail('Cafe'), findsOneWidget);
    expect(_inDetail('Choose a category'), findsOneWidget);

    // Paper & Co. was imported with a Category, but the panel never shows a
    // Category the person did not set.
    final paper = seed.state.transaction(seed.paper)!;
    await _tap(tester, _row(paper.id, paper.lines.single.id));
    expect(_inDetail('Paper & Co.'), findsOneWidget);
    expect(_inDetail('Choose a category'), findsOneWidget);
    expect(_inDetail('Groceries'), findsNothing);

    // All looks back at the reviewed line.
    await _tap(tester, find.text('All'));
    expect(_inList('Green Grocer'), findsOneWidget);
    await _tap(tester, find.text('To review'));
    expect(_inList('Green Grocer'), findsNothing);
  });

  testWidgets('Cmd+Return marks the line Reviewed and selects the next', (
    tester,
  ) async {
    final seed = _Seed();
    await _pumpDesktop(tester, seed.app());
    await _openReview(tester);

    expect(_inDetail('Cafe'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('review-category')));
    await _tap(tester, find.byKey(ValueKey('pick-${seed.groceries}')));
    await _tap(tester, find.text('Personal'));

    final mark = tester.widget<FilledButton>(
      find.byKey(const ValueKey('review-mark')),
    );
    expect(mark.onPressed, isNotNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    final line = seed.state.transaction(seed.cafe)!.lines.single;
    expect(line.reviewed, isTrue);
    expect(line.category, seed.groceries);
    expect(line.business, const Personal());

    // The next line is selected and its panel is empty again.
    final paper = seed.state.transaction(seed.paper)!;
    expect(_inDetail('Paper & Co.'), findsOneWidget);
    expect(_inDetail('Choose a category'), findsOneWidget);
    expect(_row(paper.id, paper.lines.single.id), findsOneWidget);
  });

  testWidgets('Mark reviewed marks the line and selects the next', (
    tester,
  ) async {
    final seed = _Seed();
    await _pumpDesktop(tester, seed.app());
    await _openReview(tester);

    await _tap(tester, find.byKey(const ValueKey('review-category')));
    await _tap(tester, find.byKey(ValueKey('pick-${seed.groceries}')));
    await _tap(tester, find.text('Personal'));
    await _tap(tester, find.byKey(const ValueKey('review-mark')));

    expect(seed.state.transaction(seed.cafe)!.lines.single.reviewed, isTrue);
    expect(_inDetail('Paper & Co.'), findsOneWidget);
  });

  testWidgets('Skip leaves the line and selects the next', (tester) async {
    final seed = _Seed();
    await _pumpDesktop(tester, seed.app());
    await _openReview(tester);

    await _tap(tester, find.byKey(const ValueKey('review-skip')));

    expect(seed.state.transaction(seed.cafe)!.lines.single.reviewed, isFalse);
    expect(_inDetail('Paper & Co.'), findsOneWidget);
  });

  testWidgets('Split opens the Split sheet and changes nothing on Cancel', (
    tester,
  ) async {
    final seed = _Seed();
    await _pumpDesktop(tester, seed.app());
    await _openReview(tester);

    await _tap(tester, find.byKey(const ValueKey('review-split')));
    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.text('Split')),
      findsOneWidget,
    );
    expect(find.textContaining('Left to split'), findsOneWidget);

    await _tap(
      tester,
      find.descendant(of: _sheet, matching: find.text('Cancel')),
    );
    expect(_sheet, findsNothing);
    expect(seed.state.transaction(seed.cafe)!.lines, hasLength(1));
  });

  testWidgets('Fetch from bank pulls a new line into Review', (tester) async {
    final seed = _Seed();
    final services = _services();
    await services.prefs.writeSimpleFinBook(_book(seed.checking));
    await _pumpDesktop(
      tester,
      BudgetApp(engine: seed._engine(Actor.userAndroid), services: services),
    );
    await _openReview(tester);

    await _tap(tester, find.byKey(const ValueKey('review-fetch')));

    expect(_inList('Corner Bistro'), findsOneWidget);
    expect(
      seed.state.reviewQueue.any(
        (item) => item.transaction.payee == 'Corner Bistro',
      ),
      isTrue,
    );
  });

  testWidgets('Compare opens the Possible match sheet; Merge leaves one', (
    tester,
  ) async {
    final seed = _MatchSeed();
    final services = _services();
    await services.prefs.writeSimpleFinBook(_book(seed.checking));
    await fetchByHand(
      engine: seed.engine,
      client: services.simpleFin,
      book: await services.prefs.readSimpleFinBook(),
      today: today(),
      save: services.prefs.writeSimpleFinBook,
    );
    expect(seed.engine.state.proposedMatches, hasLength(1));

    await _pumpDesktop(
      tester,
      BudgetApp(engine: seed.engine, services: services),
    );
    await _openReview(tester);

    expect(_inList('Corner Bistro'), findsOneWidget);
    expect(_inDetail('Possible match'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('review-compare')));

    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.text('Bank charge')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _sheet, matching: find.text('You entered')),
      findsOneWidget,
    );

    await _tap(
      tester,
      find.descendant(of: _sheet, matching: find.text('Merge into one')),
    );

    expect(_sheet, findsNothing);
    expect(seed.engine.state.proposedMatches, isEmpty);
    expect(
      seed.engine.state.transactions.where(
        (transaction) => transaction.payee == 'Corner Bistro',
      ),
      hasLength(1),
    );
    expect(seed.engine.state.transaction(seed.hand)!.bankId, 'tx-1');
  });

  testWidgets('Reverting a change others depend on opens the Revert sheet', (
    tester,
  ) async {
    final seed = _RevertSeed();
    await _pumpDesktop(tester, seed.app());
    await _tap(tester, find.byKey(const ValueKey('section-history')));

    await _tap(tester, _historyButton('Added category Dining out', 'Revert'));

    expect(_sheet, findsOneWidget);
    expect(find.text('Depends on what this created'), findsOneWidget);

    await _tap(tester, find.text('Revert these too'));

    expect(seed.state.category(seed.dining), isNull);
    expect(seed.state.transaction(seed.spend), isNull);
  });
}
