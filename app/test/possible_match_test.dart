import 'dart:convert';

import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:flutter/material.dart';
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

/// A synthetic budget: Home, Checking at 500.00, Dining out, and a Corner
/// Bistro meal entered by hand two days ago for the same 48.20.
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
    final group =
        (engine.execute(
              const CreateCategoryGroup(name: 'Everyday'),
            ) as Accepted).events.single.payload['categoryGroupId']
            as String;
    diningOut =
        (engine.execute(
              CreateCategory(groupId: group, name: 'Dining out'),
            ) as Accepted).events.single.payload['categoryId']
            as String;
    hand =
        (engine.execute(
              CreateTransaction(
                accountId: checking,
                date: today().addDays(-2),
                amount: const Money(-4820),
                payee: 'Corner Bistro',
                memo: 'Team lunch',
                lines: [
                  LineInput(
                    amount: const Money(-4820),
                    category: diningOut,
                    business: const Personal(),
                  ),
                ],
              ),
            ) as Accepted).events.single.payload['transactionId']
            as String;
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  late final String checking;
  late final String diningOut;
  late final String hand;
}

/// A connected book with the bank account linked, so Fetch now runs without
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

Future<void> _pump(WidgetTester tester, Widget app) async {
  // The default 800 × 600 test window: the test font is much wider than
  // IBM Plex, so a phone-width Settings row would overflow on it alone.
  await tester.pumpWidget(app);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Settings → Bank sync → Fetch now, then back out to the budget.
Future<void> _fetch(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('Settings'));
  await _tap(tester, find.text('Bank sync'));
  await _tap(tester, find.byKey(const ValueKey('fetch-now')));
  await _tap(tester, find.byTooltip('Back'));
  await _tap(tester, find.byTooltip('Back'));
}

void main() {
  testWidgets('confirming a possible match links the line and says so', (
    tester,
  ) async {
    final seed = _Seed();
    final services = _services();
    await services.prefs.writeSimpleFinBook(_book(seed.checking));
    await _pump(tester, BudgetApp(engine: seed.engine, services: services));

    await _tap(tester, find.byTooltip('Settings'));
    await _tap(tester, find.text('Bank sync'));
    await _tap(tester, find.byKey(const ValueKey('fetch-now')));

    // Nothing merged: the charge is a question, and the balance counts the
    // hand-entered line once.
    expect(find.text('1 possible match.'), findsOneWidget);
    expect(seed.engine.state.proposedMatches, hasLength(1));
    expect(seed.engine.state.bankTransaction(seed.checking, 'tx-1'), isNull);
    expect(seed.engine.state.balance(seed.checking), const Money(45180));

    await _tap(tester, find.byTooltip('Back'));
    await _tap(tester, find.byTooltip('Back'));
    await _tap(tester, find.text('Review'));

    expect(find.text('1 possible bank match'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('review-possible-matches')));

    expect(find.text('Possible match'), findsOneWidget);
    expect(find.text('Bank charge'), findsOneWidget);
    expect(find.text('You entered'), findsOneWidget);
    expect(find.text('−48.20'), findsNWidgets(2));
    await _tap(tester, find.byKey(const ValueKey('confirm-match')));

    final linked = seed.engine.state.transaction(seed.hand)!;
    expect(linked.bankId, 'tx-1');
    expect(linked.pendingMatch, isNull);
    expect(linked.memo, 'Team lunch');
    expect(linked.lines.single.category, seed.diningOut);
    expect(linked.lines.single.business, const Personal());
    expect(linked.lines.single.reviewed, isTrue);
    expect(seed.engine.state.transactions, hasLength(2));
    expect(seed.engine.state.proposedMatches, isEmpty);
    expect(seed.engine.state.reviewQueue, isEmpty);
  });

  testWidgets('rejecting a possible match enters the bank charge', (
    tester,
  ) async {
    final seed = _Seed();
    final services = _services();
    await services.prefs.writeSimpleFinBook(_book(seed.checking));
    await _pump(tester, BudgetApp(engine: seed.engine, services: services));
    await _fetch(tester);
    await _tap(tester, find.text('Review'));
    await _tap(tester, find.byKey(const ValueKey('review-possible-matches')));
    await _tap(tester, find.byKey(const ValueKey('reject-match')));

    final hand = seed.engine.state.transaction(seed.hand)!;
    expect(hand.pendingMatch, isNull);
    expect(hand.bankId, isNull);
    final bank = seed.engine.state.bankTransaction(seed.checking, 'tx-1')!;
    expect(bank.amount, const Money(-4820));
    expect(seed.engine.state.reviewQueue.single.transaction.id, bank.id);
    expect(seed.engine.state.balance(seed.checking), const Money(40360));
  });
}
