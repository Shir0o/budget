import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:test/test.dart';

final _today = CivilDate(2026, 11, 12);

LinkedAccount _link({
  String simpleFinId = 'acct-1',
  String? accountId = 'app-1',
  CivilDate? linkedFrom,
  String name = 'Everyday Checking ...1234',
}) => LinkedAccount(
  simpleFinId: simpleFinId,
  institution: 'Sample Bank',
  name: name,
  linkedFrom: linkedFrom ?? _today,
  accountId: accountId,
);

ClaimedAccount _claimed({
  String id = 'acct-1',
  List<ClaimedTransaction> transactions = const [],
}) => ClaimedAccount(
  id: id,
  institution: 'Sample Bank',
  name: 'Everyday Checking ...1234',
  balance: const Money(100000),
  balanceDate: _today,
  transactions: transactions,
);

ClaimedTransaction _transaction({
  String id = 'tx-1',
  CivilDate? date,
  int cents = -4820,
  bool pending = false,
}) => ClaimedTransaction(
  id: id,
  date: date ?? _today,
  amount: Money(cents),
  description: 'Corner Bistro',
  memo: '',
  pending: pending,
);

void main() {
  group('RequestCount', () {
    test('caps a day at 20 requests', () {
      var count = const RequestCount();
      expect(count.remaining(_today), 20);
      for (var i = 0; i < 20; i++) {
        expect(count.canFetch(_today), isTrue);
        count = count.afterFetch(_today);
      }

      expect(count.used, 20);
      expect(count.remaining(_today), 0);
      expect(count.canFetch(_today), isFalse);
      // A fetch beyond the cap never pushes the day over it.
      expect(count.afterFetch(_today).used, 20);
    });

    test('starts afresh the next day', () {
      final count = RequestCount(day: _today, used: 20);

      expect(count.remaining(CivilDate(2026, 11, 13)), 20);
      expect(count.afterFetch(CivilDate(2026, 11, 13)).used, 1);
    });
  });

  group('FetchWindow', () {
    test('is the last 90 days when nothing is linked yet', () {
      final window = const SimpleFinBook().window(_today);

      expect(window.start, CivilDate(2026, 8, 14));
      expect(window.end, _today);
    });

    test('starts at the earliest linked-from date', () {
      final book = SimpleFinBook(
        links: [
          _link(linkedFrom: CivilDate(2026, 11, 10)),
          _link(simpleFinId: 'acct-2', linkedFrom: CivilDate(2026, 11, 1)),
        ],
      );

      expect(book.window(_today).start, CivilDate(2026, 11, 1));
    });

    test('never asks for more than 90 days', () {
      final book = SimpleFinBook(
        links: [_link(linkedFrom: CivilDate(2026, 1, 1))],
      );

      expect(book.window(_today).start, CivilDate(2026, 8, 14));
    });

    test('re-reads the 10 days before the last successful fetch', () {
      final book = SimpleFinBook(
        links: [_link(linkedFrom: CivilDate(2026, 11, 1))],
        lastFetch: _today,
      );

      expect(book.window(_today).start, CivilDate(2026, 11, 2));
    });
  });

  group('SimpleFinBook', () {
    test('round-trips through JSON, and keeps the access URL out of text', () {
      final book = SimpleFinBook(
        accessUrl: 'https://user:pass@bridge.example/simplefin/access/xyz',
        links: [_link(linkedFrom: CivilDate(2026, 11, 1))],
        requests: RequestCount(day: _today, used: 3),
        lastFetch: _today,
      );

      final restored = SimpleFinBook.fromJson(book.toJson());

      expect(restored.connected, isTrue);
      expect(
        restored.access!.value,
        'https://user:pass@bridge.example/simplefin/access/xyz',
      );
      expect(restored.links.single.accountId, 'app-1');
      expect(restored.links.single.linkedFrom, CivilDate(2026, 11, 1));
      expect(restored.requests.used, 3);
      expect(restored.lastFetch, _today);
      expect(book.toString(), isNot(contains('pass')));
    });

    test('a link replaces the one for the same SimpleFIN account', () {
      final book = const SimpleFinBook()
          .link(_link())
          .link(_link(accountId: 'app-2', linkedFrom: CivilDate(2026, 11, 5)));

      expect(book.links, hasLength(1));
      expect(book.linkFor('acct-1')!.accountId, 'app-2');
    });

    test('an ignored account keeps its record with no app account', () {
      final book = const SimpleFinBook().link(_link(accountId: null));

      expect(book.linkFor('acct-1')!.ignored, isTrue);
      expect(book.linkedAccounts, isEmpty);
    });
  });

  group('bankEntries', () {
    test('keeps linked accounts and drops bank history before linked-from', () {
      final book = SimpleFinBook(
        links: [
          _link(linkedFrom: CivilDate(2026, 11, 10)),
          _link(simpleFinId: 'acct-2', accountId: null),
        ],
      );
      final result = FetchResult(
        accounts: [
          _claimed(
            transactions: [
              _transaction(id: 'before', date: CivilDate(2026, 11, 9)),
              _transaction(id: 'after', date: CivilDate(2026, 11, 10)),
            ],
          ),
          _claimed(
            id: 'acct-2',
            transactions: [_transaction(id: 'ignored')],
          ),
        ],
        errors: const [],
      );

      final entries = bankEntries(book, result);

      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.accountId, 'app-1');
      expect(entry.bankId, 'after');
      expect(entry.amount, const Money(-4820));
      expect(entry.date, CivilDate(2026, 11, 10));
      expect(entry.description, 'Corner Bistro');
      expect(entry.pending, isFalse);
    });

    test('has nothing for an account that was never linked', () {
      final result = FetchResult(
        accounts: [
          _claimed(transactions: [_transaction()]),
        ],
        errors: const [],
      );

      expect(bankEntries(const SimpleFinBook(), result), isEmpty);
    });
  });

  group('defaultLinkedFrom', () {
    BudgetState budget({CivilDate? newest}) {
      final log = InMemoryEventLog();
      final engine = BudgetEngine(
        log: log,
        deviceId: 'device-a',
        actor: Actor.userAndroid,
      );
      engine.execute(const CreateBudget(name: 'Home'));
      engine.execute(
        AddAccount(
          name: 'Checking',
          type: AccountType.checking,
          startingBalance: const Money(50000),
          asOf: CivilDate(2026, 11, 1),
        ),
      );
      final accountId = engine.state.accounts.single.id;
      if (newest != null) {
        engine.execute(
          CreateTransaction(
            accountId: accountId,
            date: newest,
            amount: const Money(-1000),
            payee: 'Hand entered',
            lines: const [LineInput(amount: Money(-1000))],
          ),
        );
      }
      return engine.state;
    }

    test('is the day after the newest transaction', () {
      final state = budget(newest: CivilDate(2026, 11, 10));

      expect(
        defaultLinkedFrom(state, state.accounts.single.id, _today),
        CivilDate(2026, 11, 11),
      );
    });

    test('is today when the account has no transactions yet', () {
      final state = BudgetState.replay(const []);

      expect(defaultLinkedFrom(state, 'app-1', _today), _today);
    });

    test('never goes past today', () {
      final state = budget(newest: CivilDate(2026, 11, 20));

      expect(
        defaultLinkedFrom(state, state.accounts.single.id, _today),
        _today,
      );
    });
  });
}
