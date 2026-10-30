import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:test/test.dart';

/// A synthetic budget with:
/// - Checking and Savings (the Savings name carries a full number);
/// - Groceries and Dining out, an Assignment and a Target;
/// - a Reviewed Corner Bistro meal carrying a card number in its memo;
/// - 205 Shop lines, for the page boundary;
/// - an Unreviewed bank line;
/// - a Rent schedule.
final class _Seed {
  _Seed() {
    final person = BudgetEngine(
      log: log,
      deviceId: 'test-device',
      actor: Actor.userAndroid,
    );
    person.execute(const CreateBudget(name: 'Home'));
    checking = _id(
      person,
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(421055),
        asOf: CivilDate(2026, 11, 1),
      ),
      'accountId',
    );
    _id(
      person,
      AddAccount(
        name: 'Savings 000123456789',
        type: AccountType.savings,
        startingBalance: const Money(100000),
        asOf: CivilDate(2026, 11, 1),
      ),
      'accountId',
    );
    final group = _id(
      person,
      const CreateCategoryGroup(name: 'Everyday'),
      'categoryGroupId',
    );
    groceries = _id(
      person,
      CreateCategory(groupId: group, name: 'Groceries'),
      'categoryId',
    );
    final dining = _id(
      person,
      CreateCategory(groupId: group, name: 'Dining out'),
      'categoryId',
    );
    person.execute(
      SetAssignment(
        categoryId: groceries,
        month: CalendarMonth(2026, 11),
        amount: const Money(30000),
      ),
    );
    person.execute(
      SetTarget(
        categoryId: groceries,
        target: const KeepAtLeastTarget(amount: Money(40000)),
      ),
    );
    bistro = _id(
      person,
      CreateTransaction(
        accountId: checking,
        date: CivilDate(2026, 11, 12),
        amount: const Money(-4820),
        payee: 'Corner Bistro',
        memo: 'lunch',
        lines: [
          LineInput(
            amount: const Money(-4820),
            category: dining,
            business: const Business('Meals'),
          ),
        ],
      ),
      'transactionId',
    );
    person.execute(
      ReviewLine(
        transactionId: bistro,
        lineId: state.transaction(bistro)!.lines.single.id,
        category: dining,
        business: const Business('Meals'),
      ),
    );
    for (var i = 1; i <= 205; i++) {
      _id(
        person,
        CreateTransaction(
          accountId: checking,
          date: CivilDate(2026, 11, 13),
          amount: const Money(-100),
          payee: 'Shop $i',
          lines: [const LineInput(amount: Money(-100), category: null)],
        ),
        'transactionId',
      );
    }
    _id(
      person,
      CreateSchedule(
        accountId: checking,
        payee: 'Rent',
        amount: const Money(-150000),
        category: dining,
        every: 1,
        interval: TargetInterval.months,
        nextDue: CivilDate(2026, 11, 15),
      ),
      'scheduleId',
    );

    // Bank sync's own Unreviewed transaction.
    final bank = BudgetEngine(
      log: log,
      deviceId: 'test-device',
      actor: Actor.bankSync,
    );
    _id(
      bank,
      CreateTransaction(
        accountId: checking,
        date: CivilDate(2026, 11, 14),
        amount: const Money(-8640),
        payee: 'Paper & Co.',
        lines: [const LineInput(amount: Money(-8640))],
      ),
      'transactionId',
    );

    // Every write path refuses a stored card number (ticket 09), so a raw
    // Event stands in for one that reached the log another way. The server
    // must still redact it (ticket 13).
    final clock = HlcClock(
      'test-device',
      nowMs: () => 1763700000000,
      last: log.readAll().last.hlc,
    );
    leaked = newId();
    log.append([
      Event(
        id: newId(),
        budgetId: budgetId,
        deviceId: 'test-device',
        hlc: clock.tick(),
        actor: const Actor.fromValue('import'),
        groupId: newId(),
        type: EventType.transactionCreated,
        payload: {
          'transactionId': leaked,
          'accountId': checking,
          'date': '2026-11-15',
          'payee': 'Wire 4111 1111 1111 1111',
          'memo': 'routing 123456780 acct 12345678',
          'cleared': 'uncleared',
          'amountCents': -1234,
          'lines': [
            {
              'lineId': newId(),
              'amountCents': -1234,
              'category': null,
              'memo': '',
              'reviewed': false,
            },
          ],
        },
      ),
    ]);
  }

  final log = InMemoryEventLog();
  late final String checking, groceries, bistro, leaked;

  BudgetState get state => BudgetState.replay(log.readAll());

  String get budgetId => state.budget!.id;

  static String _id(BudgetEngine engine, Command command, String key) {
    // One command may write more than one Event, such as AddAccount's
    // starting balance.
    for (final event in (engine.execute(command) as Accepted).events) {
      final value = event.payload[key];
      if (value is String) return value;
    }
    throw StateError('No $key in ${command.runtimeType}');
  }
}

/// [seed]'s tools, with the budget in [mode].
BudgetTools _tools(
  _Seed seed, {
  McpMode mode = McpMode.readOnly,
  McpStore? store,
}) => BudgetTools(
  store:
      store ??
      InMemoryMcpStore([
        McpBudget(
          id: seed.budgetId,
          name: 'Home',
          store: 'budget-${seed.budgetId}.db',
          book: McpBook(mode: mode),
        ),
      ]),
  events: InMemoryEventSource({seed.budgetId: seed.log.readAll()}),
  writes: InMemoryBudgetWrites({seed.budgetId: seed.log}),
  now: () => DateTime(2026, 11, 20, 10, 30),
);

Future<ToolResult> _call(
  BudgetTools tools,
  String name,
  Map<String, Object?> arguments,
) => tools.call(
  ToolRequest(name, arguments),
  client: McpClient('Claude Desktop'),
);

Map<String, Object?> _arguments(_Seed seed) => {'budgetId': seed.budgetId};

void main() {
  group('the read tools (ticket 13)', () {
    test('list_budgets shows budgets that are not Off', () async {
      final seed = _Seed();
      final store = InMemoryMcpStore([
        McpBudget(
          id: seed.budgetId,
          name: 'Home',
          store: 'budget-db',
          book: const McpBook(mode: McpMode.readOnly),
        ),
        const McpBudget(id: 'off', name: 'Old', store: 'old.db'),
      ]);
      final result = await _call(
        _tools(seed, store: store),
        'list_budgets',
        const {},
      );
      expect(result.content['budgets'], [
        {'id': seed.budgetId, 'name': 'Home', 'mode': 'Read-only'},
      ]);
    });

    test('get_month gives Ready to Assign and each Category', () async {
      final seed = _Seed();
      final result = await _call(_tools(seed), 'get_month', {
        ..._arguments(seed),
        'month': '2026-11',
      });
      expect(result.isError, isFalse);
      expect(result.content['month'], '2026-11');
      expect(
        result.content['readyToAssignCents'],
        seed.state.readyToAssign(CalendarMonth(2026, 11)).cents,
      );
      final groceries = (result.content['categories'] as List)
          .cast<Map>()
          .singleWhere((row) => row['id'] == seed.groceries);
      expect(groceries['assignedCents'], 30000);
      expect(groceries['targetNeededCents'], 40000);
      expect(groceries['group'], 'Everyday');
    });

    test('list_categories lists groups and Categories', () async {
      final seed = _Seed();
      final result = await _call(
        _tools(seed),
        'list_categories',
        _arguments(seed),
      );
      expect(result.isError, isFalse);
      expect(
        (result.content['groups'] as List).single,
        containsPair('name', 'Everyday'),
      );
      expect(
        (result.content['categories'] as List).map(
          (row) => (row as Map)['name'],
        ),
        containsAll(['Groceries', 'Dining out']),
      );
    });

    test('list_accounts cuts a name to a last-4 suffix', () async {
      final seed = _Seed();
      final result = await _call(
        _tools(seed),
        'list_accounts',
        _arguments(seed),
      );
      final accounts = (result.content['accounts'] as List).cast<Map>();
      expect(
        accounts.map((account) => account['name']),
        containsAll(['Checking', 'Savings [number ••6789]']),
      );
      expect(result.content['netWorthCents'], seed.state.netWorth.cents);
    });

    test('search_transactions filters and redacts', () async {
      final seed = _Seed();
      final result = await _call(_tools(seed), 'search_transactions', {
        ..._arguments(seed),
        'payee': 'bistro',
      });
      final transactions = (result.content['transactions'] as List).cast<Map>();
      expect(transactions, hasLength(1));
      expect(transactions.single['payee'], 'Corner Bistro');
      expect(transactions.single['memo'], 'lunch');
      expect(transactions.single['lines'], hasLength(1));
    });

    test('search_transactions returns at most 200 per page', () async {
      final seed = _Seed();
      final tools = _tools(seed);
      final first = await _call(tools, 'search_transactions', {
        ..._arguments(seed),
        'page': 1,
        'limit': 500,
      });
      final firstPage = (first.content['transactions'] as List);
      expect(firstPage, hasLength(maxPageSize));
      expect(first.content['pageSize'], maxPageSize);
      expect(first.content['hasMore'], isTrue);

      final second = await _call(tools, 'search_transactions', {
        ..._arguments(seed),
        'page': 2,
        'limit': 500,
      });
      final secondPage = (second.content['transactions'] as List);
      expect(secondPage, isNotEmpty);
      expect(secondPage.length, lessThanOrEqualTo(maxPageSize));
      expect(second.content['hasMore'], isFalse);
      // The two pages don't overlap.
      final ids = {
        for (final transaction in [...firstPage, ...secondPage])
          (transaction as Map)['id'],
      };
      expect(ids, hasLength(firstPage.length + secondPage.length));
    });

    test('get_transaction gives one transaction in full', () async {
      final seed = _Seed();
      final result = await _call(_tools(seed), 'get_transaction', {
        ..._arguments(seed),
        'transactionId': seed.bistro,
      });
      final transaction = result.content['transaction'] as Map;
      expect(transaction['payee'], 'Corner Bistro');
      expect(transaction['account'], 'Checking');
      expect(
        (transaction['lines'] as List).single,
        containsPair('reviewed', true),
      );
    });

    test(
      'list_unreviewed says what each line needs and reviews nothing',
      () async {
        final seed = _Seed();
        final before = seed.state.reviewQueue.length;
        final result = await _call(
          _tools(seed, mode: McpMode.readWrite),
          'list_unreviewed',
          _arguments(seed),
        );
        final lines = (result.content['lines'] as List).cast<Map>();
        expect(result.content['total'], before);
        expect(lines, hasLength(defaultPageSize));
        expect(lines.first['needs'], isNotNull);
        expect(seed.state.reviewQueue, hasLength(before));
      },
    );

    test('list_targets gives the Target and what it needs', () async {
      final seed = _Seed();
      final result = await _call(
        _tools(seed),
        'list_targets',
        _arguments(seed),
      );
      final target = (result.content['targets'] as List).cast<Map>().single;
      expect(target['categoryId'], seed.groceries);
      expect(target['kind'], 'keepAtLeast');
      expect(target['amountCents'], 40000);
      expect(target['automationMode'], 'suggest');
    });

    test('get_forecast expands the next 12 months', () async {
      final seed = _Seed();
      final result = await _call(
        _tools(seed),
        'get_forecast',
        _arguments(seed),
      );
      final months = (result.content['months'] as List).cast<Map>();
      expect(months, hasLength(12));
      expect(months.first['month'], '2026-11');
      expect(months.first['outflowCents'], 150000);
    });

    test('get_business_report applies the 50% meals rule', () async {
      final seed = _Seed();
      final result = await _call(_tools(seed), 'get_business_report', {
        ..._arguments(seed),
        'year': 2026,
      });
      final meals = (result.content['rows'] as List).cast<Map>().singleWhere(
        (row) => row['tag'] == 'Meals',
      );
      expect(meals['grossCents'], 4820);
      expect(meals['deductibleCents'], 2410);
      expect(result.content['deductibleExpensesCents'], 2410);
      expect(
        (result.content['lines'] as List).single,
        containsPair('payee', 'Corner Bistro'),
      );
    });

    test('get_change_history filters by Actor', () async {
      final seed = _Seed();
      final result = await _call(_tools(seed), 'get_change_history', {
        ..._arguments(seed),
        'actor': 'bankSync',
      });
      final entries = (result.content['entries'] as List).cast<Map>();
      expect(entries, hasLength(1));
      expect(entries.single['actor'], 'bank-sync');
      expect(entries.single['summary'], contains('Paper & Co.'));
    });
  });

  group('redaction', () {
    test('every string in a result is redacted', () async {
      final seed = _Seed();
      final result = await _call(_tools(seed), 'search_transactions', {
        ..._arguments(seed),
        'payee': 'wire',
      });
      final transaction =
          (result.content['transactions'] as List).single as Map;
      expect(transaction['payee'], 'Wire [card ••1111]');
      expect(transaction['memo'], 'routing [routing] acct [number ••5678]');
      expect(result.text, isNot(contains('4111111111111111')));
      expect(result.text, isNot(contains('123456780')));
      expect(result.text, isNot(contains('12345678')));
      // Ids are opaque: the client can send them straight back.
      final byId = await _call(_tools(seed), 'get_transaction', {
        ..._arguments(seed),
        'transactionId': transaction['id'],
      });
      expect(
        byId.content['transaction'],
        containsPair('payee', 'Wire [card ••1111]'),
      );
    });
  });

  group('the mode gate', () {
    test('Off hides the budget and refuses every read', () async {
      final seed = _Seed();
      final tools = _tools(seed, mode: McpMode.off);
      final listed = await _call(tools, 'list_budgets', const {});
      expect(listed.content['budgets'], isEmpty);
      for (final tool in BudgetTools.specs) {
        if (tool.name == 'list_budgets') continue;
        final result = await _call(tools, tool.name, {
          ..._arguments(seed),
          'transactionId': seed.bistro,
        });
        expect(result.isError, isTrue, reason: tool.name);
        expect(result.content['error'], contains('MCP is off'));
      }
    });

    test('Read-only refuses writes and Review marking', () async {
      final seed = _Seed();
      final tools = _tools(seed);
      final write = await _call(tools, 'create_transaction', _arguments(seed));
      expect(write.isError, isTrue);
      expect(write.content['error'], 'MCP is read-only for this budget.');

      final review = await _call(tools, 'mark_reviewed', _arguments(seed));
      expect(review.isError, isTrue);
      expect(review.content['error'], contains('Reviewed'));

      final delete = await _call(tools, 'delete_transaction', _arguments(seed));
      expect(delete.isError, isTrue);
    });

    test('Read-write writes, and Review marking is still refused', () async {
      final seed = _Seed();
      final tools = _tools(seed, mode: McpMode.readWrite);
      final write = await _call(tools, 'create_transaction', {
        ..._arguments(seed),
        'accountId': seed.checking,
        'date': '2026-11-20',
        'amountCents': -1299,
        'lines': [
          {'amountCents': -1299},
        ],
      });
      expect(write.isError, isFalse);
      expect(write.content['actor'], 'mcp:Claude Desktop');
      final review = await _call(tools, 'mark_reviewed', _arguments(seed));
      expect(review.isError, isTrue);
    });
  });

  group('arguments and audit', () {
    test(
      'a missing budgetId, an unknown budget and an unknown tool are errors',
      () async {
        final seed = _Seed();
        final tools = _tools(seed);
        expect((await _call(tools, 'get_month', const {})).isError, isTrue);
        final unknown = await _call(tools, 'get_month', {'budgetId': 'nope'});
        expect(unknown.content['error'], 'No budget with that id.');
        final missing = await _call(tools, 'nope', const {});
        expect(missing.content['error'], 'No tool named “nope”.');
      },
    );

    test('a read records the client and time for Settings', () async {
      final seed = _Seed();
      final store = InMemoryMcpStore([
        McpBudget(
          id: seed.budgetId,
          name: 'Home',
          store: 'budget-db',
          book: const McpBook(mode: McpMode.readOnly),
        ),
      ]);
      await _call(_tools(seed, store: store), 'get_month', _arguments(seed));
      final budget = (await store.read()).single;
      expect(budget.book.lastUsedBy, 'Claude Desktop');
      expect(budget.book.lastUsedAt, DateTime(2026, 11, 20, 10, 30));
    });
  });
}
