import 'dart:convert';

import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _accessUrl = 'https://user:pass@bridge.example/simplefin/access/xyz';
final _setupToken = base64Encode(
  utf8.encode('https://bridge.example/simplefin/claim/abc123'),
);

/// The bridge's answer: one checking account with a single charge for
/// [amount], dated now so a fresh linked-from date includes it.
String _fetchJson({String amount = '-48.20', String id = 'tx-1'}) {
  final now = DateTime.now();
  final posted = now.millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({
    'errors': <String>[],
    'accounts': [
      {
        'org': {'name': 'Sample Bank'},
        'id': 'acct-1',
        'name': 'Everyday Checking ...1234',
        'currency': 'USD',
        'balance': '1234.56',
        'available-balance': '1200.06',
        'balance-date': posted,
        'transactions': [
          {
            'id': id,
            'posted': posted,
            'amount': amount,
            'description': 'CORNER BISTRO',
            'payee': 'Corner Bistro',
            'memo': 'Lunch',
          },
        ],
      },
    ],
  });
}

/// A synthetic budget: Home, Checking at 4,210.55, and a Groceries
/// Category.
final class _Seed {
  _Seed() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(421055),
        asOf: today(),
      ),
    );
    final group =
        (engine.execute(
              const CreateCategoryGroup(name: 'Everyday'),
            ) as Accepted).events.single.payload['categoryGroupId']
            as String;
    groceries =
        (engine.execute(
              CreateCategory(groupId: group, name: 'Groceries'),
            ) as Accepted).events.single.payload['categoryId']
            as String;
    checking = engine.state.accounts.single.id;
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  late final String checking;
  late final String groceries;
}

AppServices _services(FakeSimpleFinTransport transport) => AppServices(
  keys: InMemoryBudgetKeyStore(),
  prefs: InMemoryDevicePrefs(),
  saver: InMemoryFileSaver(),
  authenticator: FakeAuthenticator(),
  simpleFin: transport,
);

FakeSimpleFinTransport _transport({String amount = '-48.20'}) =>
    FakeSimpleFinTransport(
      replies: {
        'POST /simplefin/claim/abc123': const SimpleFinReply(
          200,
          '$_accessUrl\n',
        ),
        'GET /simplefin/access/xyz/accounts': SimpleFinReply(
          200,
          _fetchJson(amount: amount),
        ),
      },
    );

/// The default 800 × 600 test window: the test font is much wider than
/// IBM Plex, so a phone-width Settings row would overflow on it alone.
Future<void> _pump(WidgetTester tester, Widget app) => tester.pumpWidget(app);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openBankSync(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('Settings'));
  await _tap(tester, find.text('Bank sync'));
}

void main() {
  testWidgets('connects, links an account and imports its transactions', (
    tester,
  ) async {
    final seed = _Seed();
    final transport = _transport();
    final services = _services(transport);
    await _pump(tester, BudgetApp(engine: seed.engine, services: services));
    await _openBankSync(tester);

    expect(find.byKey(const ValueKey('setup-token')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('setup-token')),
      _setupToken,
    );
    await _tap(tester, find.byKey(const ValueKey('connect-bank')));

    // The first fetch brings the accounts up and opens Link accounts.
    expect(find.text('Link accounts'), findsOneWidget);
    expect(find.text('Everyday Checking ...1234'), findsOneWidget);
    expect(find.text('Sample Bank · \$1,234.56'), findsOneWidget);
    expect(
      (await services.prefs.readSimpleFinBook()).access!.value,
      _accessUrl,
    );

    await _tap(tester, find.byTooltip('Choose app account'));
    await _tap(tester, find.text('Checking'));
    await _tap(tester, find.byKey(const ValueKey('save-links')));

    final linked = await services.prefs.readSimpleFinBook();
    expect(linked.links.single.accountId, seed.checking);
    expect(linked.links.single.linkedFrom, today());
    expect(linked.requests.used, 1);
    expect(find.text('19 of 20'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('fetch-now')));

    expect(find.text('Imported 1 new.'), findsOneWidget);
    expect(find.text('18 of 20'), findsOneWidget);
    final bank = seed.engine.state.bankTransaction(seed.checking, 'tx-1')!;
    expect(bank.amount, const Money(-4820));
    expect(bank.payee, 'Corner Bistro');
    expect(bank.lines.single.reviewed, isFalse);
    expect(bank.lines.single.category, isNull);
  });

  testWidgets('a reviewed line whose amount changed shows the bank note', (
    tester,
  ) async {
    final seed = _Seed();
    seed.engine.execute(
      ImportBankTransactions(
        entries: [
          BankEntry(
            accountId: seed.checking,
            bankId: 'tx-1',
            date: today(),
            amount: const Money(-4820),
            description: 'Corner Bistro',
          ),
        ],
      ),
    );
    final imported = seed.engine.state.bankTransaction(seed.checking, 'tx-1')!;
    seed.engine.execute(
      ReviewLine(
        transactionId: imported.id,
        lineId: imported.lines.single.id,
        category: seed.groceries,
        business: const Personal(),
      ),
    );
    expect(seed.engine.state.reviewQueue, isEmpty);

    final services = _services(_transport(amount: '-15.00'));
    await services.prefs.writeSimpleFinBook(
      SimpleFinBook(
        accessUrl: _accessUrl,
        links: [
          LinkedAccount(
            simpleFinId: 'acct-1',
            institution: 'Sample Bank',
            name: 'Everyday Checking ...1234',
            linkedFrom: today().addDays(-30),
            accountId: seed.checking,
          ),
        ],
      ),
    );
    await _pump(tester, BudgetApp(engine: seed.engine, services: services));
    await _openBankSync(tester);
    await _tap(tester, find.byKey(const ValueKey('fetch-now')));

    expect(find.text('Imported 1 updated.'), findsOneWidget);
    // Back out to the budget, then open Review.
    await _tap(tester, find.byTooltip('Back'));
    await _tap(tester, find.byTooltip('Back'));
    await _tap(tester, find.text('Review'));
    expect(find.text('changed by bank: −\$48.20 → −\$15.00'), findsOneWidget);
    final line = seed.engine.state
        .bankTransaction(seed.checking, 'tx-1')!
        .lines
        .single;
    expect(line.reviewed, isFalse);
    expect(line.category, seed.groceries);
  });

  testWidgets('the daily cap stops fetches after 20', (tester) async {
    final seed = _Seed();
    final transport = _transport();
    final services = _services(transport);
    await services.prefs.writeSimpleFinBook(
      SimpleFinBook(
        accessUrl: _accessUrl,
        links: [
          LinkedAccount(
            simpleFinId: 'acct-1',
            institution: 'Sample Bank',
            name: 'Everyday Checking ...1234',
            linkedFrom: today().addDays(-30),
            accountId: seed.checking,
          ),
        ],
        requests: RequestCount(day: today(), used: RequestCount.dailyLimit),
      ),
    );
    await _pump(tester, BudgetApp(engine: seed.engine, services: services));
    await _openBankSync(tester);

    expect(find.text('0 of 20'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('fetch-now')),
    );
    expect(button.onPressed, isNull);
    expect(transport.requests, isEmpty);
  });
}
