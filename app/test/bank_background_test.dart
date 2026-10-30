import 'dart:convert';

import 'package:budget/bank_sync.dart';
import 'package:budget/services.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:flutter_test/flutter_test.dart';

const _accessUrl = 'https://user:pass@bridge.example/simplefin/access/xyz';
final _day = CivilDate(2026, 11, 12);
final _morning = DateTime(2026, 11, 12, 8);

/// The bridge's answer: one checking account with a single charge dated
/// [_day], plus [errors] when the bridge has something to say.
String _fetchJson({List<String> errors = const []}) {
  final posted = DateTime.utc(2026, 11, 12, 12).millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({
    'errors': errors,
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
            'id': 'tx-1',
            'posted': posted,
            'amount': '-48.20',
            'description': 'CORNER BISTRO',
            'payee': 'Corner Bistro',
            'memo': 'Lunch',
          },
        ],
      },
    ],
  });
}

/// A synthetic budget with Checking, linked through SimpleFIN.
final class _Seed {
  _Seed() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(421055),
        asOf: _day.addDays(-30),
      ),
    );
    checking = engine.state.accounts.single.id;
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  late final String checking;

  SimpleFinBook book({RequestCount requests = const RequestCount()}) =>
      SimpleFinBook(
        accessUrl: _accessUrl,
        requests: requests,
        links: [
          LinkedAccount(
            simpleFinId: 'acct-1',
            institution: 'Sample Bank',
            name: 'Everyday Checking ...1234',
            linkedFrom: _day.addDays(-30),
            accountId: checking,
          ),
        ],
      );
}

FakeSimpleFinTransport _transport() => FakeSimpleFinTransport(
  replies: {
    'GET /simplefin/access/xyz/accounts': SimpleFinReply(200, _fetchJson()),
  },
);

Future<BankSyncOutcome> _fetch(
  _Seed seed,
  FakeSimpleFinTransport transport,
  SimpleFinBook book,
  DateTime now,
) => fetchAutomatically(
  engine: seed.engine,
  client: SimpleFinClient(transport),
  book: book,
  now: now,
  save: (_) async {},
);

void main() {
  test('automatic fetches wait 6 hours and stop at the daily cap', () async {
    final seed = _Seed();
    final transport = _transport();
    final book = seed.book();

    final first = await _fetch(seed, transport, book, _morning);
    expect(transport.requests, hasLength(1));
    expect(first.book.requests.used, 1);
    expect(first.book.schedule.lastAttempt, _morning.toUtc());
    expect(first.message, 'Imported 1 new.');

    final early = await _fetch(
      seed,
      transport,
      first.book,
      _morning.add(const Duration(hours: 5, minutes: 59)),
    );
    expect(transport.requests, hasLength(1));
    expect(early.book.requests.used, 1);

    final due = await _fetch(
      seed,
      transport,
      first.book,
      _morning.add(const Duration(hours: 6)),
    );
    expect(transport.requests, hasLength(2));
    expect(due.book.requests.used, 2);

    // 19 requests are already spent by hand, so only one automatic fetch
    // fits before the cap: the next 6-hourly run sends nothing.
    final nearlySpent = seed.book(
      requests: RequestCount(day: _day, used: RequestCount.dailyLimit - 1),
    );
    final last = await _fetch(seed, transport, nearlySpent, _morning);
    expect(transport.requests, hasLength(3));
    expect(last.book.requests.used, RequestCount.dailyLimit);

    final capped = await _fetch(
      seed,
      transport,
      last.book,
      _morning.add(FetchSchedule.interval),
    );
    expect(transport.requests, hasLength(3));
    expect(capped.book.requests.used, RequestCount.dailyLimit);
  });

  test('an auth failure pauses automatic fetches until a re-link', () async {
    final seed = _Seed();
    final transport = _transport();
    transport.replies['GET /simplefin/access/xyz/accounts'] =
        const SimpleFinReply(403, '');
    final saved = <SimpleFinBook>[];

    final failed = await fetchAutomatically(
      engine: seed.engine,
      client: SimpleFinClient(transport),
      book: seed.book(),
      now: _morning,
      save: (book) async => saved.add(book),
    );

    expect(failed.book.auth, AuthState.needsRelink);
    expect(failed.book.automaticPaused, isTrue);
    expect(failed.errors, [
      'SimpleFIN refused the access URL. Re-link your bank.',
    ]);
    expect(failed.message, isNull);
    // The pause and its message are persisted, not just shown once.
    expect(saved.last.auth, AuthState.needsRelink);
    expect(saved.last.errors.single.auth, isTrue);

    final skipped = await _fetch(
      seed,
      transport,
      failed.book,
      _morning.add(FetchSchedule.interval),
    );
    expect(transport.requests, hasLength(1));
    expect(skipped.book.auth, AuthState.needsRelink);

    // Re-linking clears the pause and the message, and the next 6-hourly
    // run goes out again.
    final relinked = failed.book.withAccess(_accessUrl);
    expect(relinked.automaticPaused, isFalse);
    expect(relinked.errors, isEmpty);
    transport.replies['GET /simplefin/access/xyz/accounts'] = SimpleFinReply(
      200,
      _fetchJson(),
    );

    final resumed = await _fetch(
      seed,
      transport,
      relinked,
      _morning.add(const Duration(hours: 6)),
    );
    expect(transport.requests, hasLength(2));
    expect(resumed.book.auth, AuthState.linked);
    expect(resumed.errors, isEmpty);
  });

  test('the bridge’s errors are kept for the banner', () async {
    final seed = _Seed();
    final transport = _transport();
    final saved = <SimpleFinBook>[];
    transport.replies['GET /simplefin/access/xyz/accounts'] = SimpleFinReply(
      200,
      _fetchJson(errors: ['Re-authenticate with your bank.']),
    );

    final outcome = await fetchAutomatically(
      engine: seed.engine,
      client: SimpleFinClient(transport),
      book: seed.book(),
      now: _morning,
      save: (book) async => saved.add(book),
    );

    expect(outcome.errors, ['Re-authenticate with your bank.']);
    expect(saved.last.errors.single.message, 'Re-authenticate with your bank.');
    expect(saved.last.errors.single.day, _day);
    expect(saved.last.errors.single.auth, isFalse);
  });

  test('the platform fetch follows the book', () async {
    final seed = _Seed();
    final scheduler = FakeBankSyncScheduler();

    await syncBankSchedule(scheduler, seed.book());
    expect(scheduler.scheduled, 1);
    expect(scheduler.cancelled, 0);

    await syncBankSchedule(scheduler, seed.book().needsRelink());
    expect(scheduler.scheduled, 1);
    expect(scheduler.cancelled, 1);

    await syncBankSchedule(scheduler, const SimpleFinBook());
    expect(scheduler.cancelled, 2);
  });
}
