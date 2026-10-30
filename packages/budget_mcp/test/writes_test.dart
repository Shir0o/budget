import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:test/test.dart';

/// A synthetic budget with Checking, Groceries and Dining out, an
/// Unreviewed meal and a Reviewed coffee, and an MCP store in [mode].
final class _Seed {
  _Seed({McpMode mode = McpMode.readWrite}) {
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
    group = _id(
      person,
      const CreateCategoryGroup(name: 'Everyday'),
      'categoryGroupId',
    );
    groceries = _id(
      person,
      CreateCategory(groupId: group, name: 'Groceries'),
      'categoryId',
    );
    dining = _id(
      person,
      CreateCategory(groupId: group, name: 'Dining out'),
      'categoryId',
    );
    unused = _id(
      person,
      CreateCategory(groupId: group, name: 'Hobbies'),
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
    // A bank line nobody has reviewed: no Category, no business status.
    unreviewed = _id(
      person,
      CreateTransaction(
        accountId: checking,
        date: CivilDate(2026, 11, 12),
        amount: const Money(-4820),
        payee: 'Corner Bistro',
        lines: [const LineInput(amount: Money(-4820))],
      ),
      'transactionId',
    );
    // A person's complete line, so it is Reviewed.
    reviewed = _id(
      person,
      CreateTransaction(
        accountId: checking,
        date: CivilDate(2026, 11, 13),
        amount: const Money(-350),
        payee: 'Cafe',
        lines: [
          LineInput(
            amount: const Money(-350),
            category: dining,
            business: const Personal(),
          ),
        ],
      ),
      'transactionId',
    );
    store = InMemoryMcpStore([
      McpBudget(
        id: budgetId,
        name: 'Home',
        store: 'budget-home.db',
        book: McpBook(mode: mode),
        deviceId: 'test-device',
      ),
    ]);
  }

  final log = InMemoryEventLog();
  late final InMemoryMcpStore store;
  late final String checking, group, groceries, dining, unused;
  late final String unreviewed, reviewed;

  BudgetState get state => BudgetState.replay(log.readAll());

  String get budgetId => state.budget!.id;

  BudgetTools get tools {
    final events = _Log(log);
    return BudgetTools(
      store: store,
      events: events,
      writes: events,
      now: () => DateTime(2026, 11, 20, 10, 30),
    );
  }

  Map<String, Object?> args([Map<String, Object?> more = const {}]) => {
    'budgetId': budgetId,
    ...more,
  };

  /// The Events of the group [result] answered with.
  List<Event> eventsOf(ToolResult result) => [
    for (final event in log.readAll())
      if (event.groupId == result.content['groupId']) event,
  ];

  static String _id(BudgetEngine engine, Command command, String key) {
    for (final event in (engine.execute(command) as Accepted).events) {
      final value = event.payload[key];
      if (value is String) return value;
    }
    throw StateError('No $key in ${command.runtimeType}');
  }
}

/// One budget's log, read and written through the same engine path the app
/// uses, so a test sees its own writes.
final class _Log implements EventSource, BudgetWrites {
  _Log(this.log);

  final EventLog log;

  @override
  Future<List<Event>> events(McpBudget budget) async => log.readAll();

  @override
  Future<CommandResult> write(
    McpBudget budget,
    Command command,
    Actor actor,
  ) async => BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: actor,
  ).execute(command);
}

Future<ToolResult> _call(
  _Seed seed,
  String name,
  Map<String, Object?> arguments, {
  String client = 'Claude Desktop',
}) => seed.tools.call(
  ToolRequest(name, {...seed.args(), ...arguments}),
  client: McpClient(client),
);

/// Valid arguments for every write tool, so a loop can prove the shape each
/// one writes.
Map<String, Map<String, Object?>> _examples(_Seed seed) => {
  'create_transaction': {
    'accountId': seed.checking,
    'date': '2026-11-20',
    'amountCents': -1299,
    'payee': 'Corner Bistro',
    'lines': [
      {'amountCents': -1299, 'categoryId': seed.groceries},
    ],
  },
  'update_transaction': {
    'transactionId': seed.unreviewed,
    'payee': 'Bistro',
    'memo': 'lunch',
  },
  'split_transaction': {
    'transactionId': seed.unreviewed,
    'amountCents': -4820,
    'lines': [
      {'amountCents': -3000, 'categoryId': seed.groceries},
      {'amountCents': -1820, 'categoryId': seed.dining},
    ],
  },
  'assign': {
    'categoryId': seed.dining,
    'month': '2026-11',
    'amountCents': 5000,
  },
  'move_money': {
    'fromCategoryId': seed.groceries,
    'toCategoryId': seed.dining,
    'month': '2026-11',
    'amountCents': 1000,
  },
  'create_schedule': {
    'accountId': seed.checking,
    'payee': 'Rent',
    'amountCents': -150000,
    'categoryId': seed.dining,
    'every': 1,
    'interval': 'months',
    'nextDue': '2026-12-01',
  },
  'set_target': {
    'categoryId': seed.dining,
    'kind': 'keepAtLeast',
    'amountCents': 40000,
  },
  'clear_target': {'categoryId': seed.groceries},
  'create_category': {'groupId': seed.group, 'name': 'Coffee'},
  'rename_category': {'categoryId': seed.dining, 'name': 'Restaurants'},
  'archive_category': {'categoryId': seed.unused},
  'suggest_review': {
    'transactionId': seed.unreviewed,
    'lineId': seed.state.transaction(seed.unreviewed)!.lines.single.id,
    'categoryId': seed.groceries,
    'business': 'personal',
  },
};

void main() {
  group('the write tools (ticket 13)', () {
    test('every tool writes one group as mcp:<client>', () async {
      for (final name in _examples(_Seed()).keys) {
        final seed = _Seed();
        final before = seed.log.readAll().length;
        final result = await _call(seed, name, _examples(seed)[name]!);
        expect(result.isError, isFalse, reason: '$name: ${result.text}');

        final written = seed.log.readAll().skip(before).toList();
        expect(written, isNotEmpty, reason: name);
        expect(written.map((event) => event.groupId).toSet(), {
          result.content['groupId'],
        }, reason: name);
        expect(
          written.every((event) => event.actor.value == 'mcp:Claude Desktop'),
          isTrue,
          reason: name,
        );
        expect(result.content['actor'], 'mcp:Claude Desktop');
        expect(result.content['changes'], written.length);
        expect(
          (await seed.store.read()).single.book.lastUsedBy,
          'Claude Desktop',
        );
      }
    });

    test('create_transaction leaves the line Unreviewed', () async {
      final seed = _Seed();
      final result = await _call(seed, 'create_transaction', {
        'accountId': seed.checking,
        'date': '2026-11-20',
        'amountCents': -1299,
        'payee': 'Corner Bistro',
        'lines': [
          {
            'amountCents': -1299,
            'categoryId': seed.groceries,
            'business': 'business',
            'businessTag': 'Meals',
          },
        ],
      });
      expect(result.isError, isFalse);
      final transactionId =
          seed.eventsOf(result).single.payload['transactionId'] as String;
      final line = seed.state.transaction(transactionId)!.lines.single;
      expect(line.category, seed.groceries);
      expect(line.business, const Business('Meals'));
      // A person's tap is still the only thing that marks it Reviewed.
      expect(line.reviewed, isFalse);
    });

    test(
      'amountCents must be whole cents: 1250.7 is refused, 1250.0 is not',
      () async {
        final seed = _Seed();
        final before = seed.log.readAll().length;
        for (final name in ['assign', 'create_transaction']) {
          final refused = await _call(seed, name, {
            ..._examples(seed)[name]!,
            'amountCents': 1250.7,
          });
          expect(refused.isError, isTrue, reason: name);
          expect(refused.content['error'], contains('whole'), reason: name);
        }
        final lineRefused = await _call(seed, 'create_transaction', {
          ..._examples(seed)['create_transaction']!,
          'lines': [
            {'amountCents': -1299.5, 'categoryId': seed.groceries},
          ],
        });
        expect(lineRefused.isError, isTrue);
        expect(seed.log.readAll(), hasLength(before));

        final whole = await _call(seed, 'assign', {
          'categoryId': seed.dining,
          'month': '2026-11',
          'amountCents': 1250.0,
        });
        expect(whole.isError, isFalse, reason: whole.text);
        expect(
          seed.state.assigned(seed.dining, CalendarMonth(2026, 11)).cents,
          1250,
        );
      },
    );

    test(
      'MCP cannot edit a Reconciled transaction or set Reconciled',
      () async {
        final seed = _Seed();
        final person = BudgetEngine(
          log: seed.log,
          deviceId: 'test-device',
          actor: Actor.userAndroid,
        );
        expect(
          person.execute(
            EditTransaction(
              transactionId: seed.reviewed,
              cleared: ClearedStatus.reconciled,
            ),
          ),
          isA<Accepted>(),
        );
        final before = seed.log.readAll().length;
        final edit = await _call(seed, 'update_transaction', {
          'transactionId': seed.reviewed,
          'memo': 'sneaky',
          'confirmReconciled': true,
        });
        expect(edit.isError, isTrue);
        expect(edit.content['error'], contains('in the app'));

        final set = await _call(seed, 'update_transaction', {
          'transactionId': seed.unreviewed,
          'cleared': 'reconciled',
        });
        expect(set.isError, isTrue);
        expect(set.content['error'], contains('in the app'));
        expect(seed.log.readAll(), hasLength(before));
      },
    );

    test('a group survives a revert and shows in Change History', () async {
      final seed = _Seed();
      final result = await _call(seed, 'assign', {
        'categoryId': seed.dining,
        'month': '2026-11',
        'amountCents': 5000,
      });
      final groupId = result.content['groupId'] as String;
      expect(
        seed.state.assigned(seed.dining, CalendarMonth(2026, 11)).cents,
        5000,
      );
      expect(result.content['summary'], isNotNull);

      final person = BudgetEngine(
        log: seed.log,
        deviceId: 'test-device',
        actor: Actor.userAndroid,
      );
      expect(person.execute(RevertGroup(groupId: groupId)), isA<Accepted>());
      expect(
        seed.state.assigned(seed.dining, CalendarMonth(2026, 11)).cents,
        0,
      );
      expect(person.history.entry(groupId)!.revertedBy, isNotNull);
    });

    test('suggest_review fills values and never marks Reviewed', () async {
      final seed = _Seed();
      final lineId = seed.state.transaction(seed.unreviewed)!.lines.single.id;
      final result = await _call(seed, 'suggest_review', {
        'transactionId': seed.unreviewed,
        'lineId': lineId,
        'categoryId': seed.groceries,
        'business': 'personal',
      });
      expect(result.isError, isFalse);
      final line = seed.state.transaction(seed.unreviewed)!.lines.single;
      expect(line.category, seed.groceries);
      expect(line.business, const Personal());
      expect(line.reviewed, isFalse);
      expect(seed.state.reviewQueue, hasLength(1));

      // A person's ReviewLine still finishes the job.
      final person = BudgetEngine(
        log: seed.log,
        deviceId: 'test-device',
        actor: Actor.userAndroid,
      );
      person.execute(
        ReviewLine(
          transactionId: seed.unreviewed,
          lineId: lineId,
          category: line.category,
          business: line.business,
        ),
      );
      expect(
        seed.state.transaction(seed.unreviewed)!.lines.single.reviewed,
        isTrue,
      );

      // And on a Reviewed line there is nothing to suggest.
      final reviewed = seed.state.transaction(seed.reviewed)!.lines.single;
      final refused = await _call(seed, 'suggest_review', {
        'transactionId': seed.reviewed,
        'lineId': reviewed.id,
        'categoryId': seed.groceries,
      });
      expect(refused.isError, isTrue);
      expect(refused.content['error'], contains('already Reviewed'));
      expect(
        seed.state.transaction(seed.reviewed)!.lines.single.category,
        seed.dining,
      );
    });

    test('rename_category keeps the group, Assignments and lines', () async {
      final seed = _Seed();
      final result = await _call(seed, 'rename_category', {
        'categoryId': seed.groceries,
        'name': 'Food',
      });
      expect(result.isError, isFalse);
      final category = seed.state.category(seed.groceries)!;
      expect(category.name, 'Food');
      expect(category.groupId, seed.group);
      expect(
        seed.state.assigned(seed.groceries, CalendarMonth(2026, 11)).cents,
        30000,
      );
      expect(result.content['summary'], 'Set name of Groceries');
    });

    test('revert_change undoes an MCP group only', () async {
      final seed = _Seed();
      final created = await _call(seed, 'create_category', {
        'groupId': seed.group,
        'name': 'Coffee',
      });
      final groupId = created.content['groupId'] as String;
      expect(
        seed.state.categories.where((category) => category.name == 'Coffee'),
        hasLength(1),
      );

      final reverted = await _call(seed, 'revert_change', {'groupId': groupId});
      expect(reverted.isError, isFalse);
      expect(
        seed.state.categories.where((category) => category.name == 'Coffee'),
        isEmpty,
      );

      // A person's group is not MCP's to revert.
      final personGroup = seed.log
          .readAll()
          .firstWhere((event) => event.actor.isPerson)
          .groupId;
      final refused = await _call(seed, 'revert_change', {
        'groupId': personGroup,
      });
      expect(refused.isError, isTrue);
      expect(refused.content['error'], contains('only revert changes it made'));

      final unknown = await _call(seed, 'revert_change', {'groupId': 'nope'});
      expect(unknown.content['error'], 'No change with that group id.');
    });
  });

  group('card and account numbers', () {
    test('a card-like payee is refused, not stored', () async {
      final seed = _Seed();
      final before = seed.log.readAll().length;
      final result = await _call(seed, 'create_transaction', {
        'accountId': seed.checking,
        'date': '2026-11-20',
        'amountCents': -1299,
        'payee': 'Card 4111 1111 1111 1111',
        'lines': [
          {'amountCents': -1299},
        ],
      });
      expect(result.isError, isTrue);
      expect(
        result.content['error'],
        "Account or card numbers can't be stored.",
      );
      expect(seed.log.readAll(), hasLength(before));
    });

    test('a routing or long number in a line or a name is refused', () async {
      final seed = _Seed();
      final routing = await _call(seed, 'create_transaction', {
        'accountId': seed.checking,
        'date': '2026-11-20',
        'amountCents': -1299,
        'lines': [
          {'amountCents': -1299, 'memo': 'routing 123456780'},
        ],
      });
      expect(routing.content['error'], contains("can't be stored"));

      final account = await _call(seed, 'create_category', {
        'groupId': seed.group,
        'name': 'Acct 12345678',
      });
      expect(account.content['error'], contains("can't be stored"));
    });
  });

  group('the mode gate on writes', () {
    test('Read-only refuses every write tool and writes nothing', () async {
      final seed = _Seed(mode: McpMode.readOnly);
      final before = seed.log.readAll().length;
      for (final name in _examples(seed).keys) {
        final result = await _call(seed, name, _examples(seed)[name]!);
        expect(result.isError, isTrue, reason: name);
        expect(
          result.content['error'],
          'MCP is read-only for this budget.',
          reason: name,
        );
      }
      expect(seed.log.readAll(), hasLength(before));
    });

    test('Off refuses every write tool', () async {
      final seed = _Seed(mode: McpMode.off);
      final before = seed.log.readAll().length;
      for (final name in _examples(seed).keys) {
        final result = await _call(seed, name, _examples(seed)[name]!);
        expect(result.isError, isTrue, reason: name);
        expect(result.content['error'], contains('MCP is off'), reason: name);
      }
      expect(seed.log.readAll(), hasLength(before));
    });
  });

  group('never there', () {
    test('no tool deletes or marks a line Reviewed', () {
      expect(
        BudgetTools.writeToolNames.where((name) => name.startsWith('delete')),
        isEmpty,
      );
      expect(BudgetTools.writeToolNames, isNot(contains('mark_reviewed')));
      expect(
        BudgetTools.writeSpecs.map((spec) => spec.name),
        containsAll([
          'create_transaction',
          'update_transaction',
          'split_transaction',
          'assign',
          'move_money',
          'create_schedule',
          'update_schedule',
          'set_target',
          'clear_target',
          'create_category',
          'rename_category',
          'archive_category',
          'suggest_review',
          'revert_change',
        ]),
      );
      expect(BudgetTools.writeSpecs.every((spec) => spec.writes), isTrue);
      expect(BudgetTools.specs.every((spec) => !spec.writes), isTrue);
    });

    test('a delete or Review tool still refuses', () async {
      final seed = _Seed();
      for (final name in ['delete_transaction', 'mark_reviewed']) {
        final result = await _call(seed, name, const {});
        expect(result.isError, isTrue, reason: name);
        expect(result.content['error'], contains('Do it in the app'));
      }
    });
  });

  group('McpClient', () {
    test('names the Actor mcp:<client>, cleaned', () {
      expect(McpClient('Claude Desktop').actor.value, 'mcp:Claude Desktop');
      expect(McpClient('  Claude   Desktop ').name, 'Claude Desktop');
      expect(McpClient('').name, 'unknown');
      expect(McpClient('mcp:Claude').name, 'Claude');
      expect(McpClient.unknown.actor.value, 'mcp:unknown');
      expect(McpClient('x' * 100).name, hasLength(64));
    });
  });

  group('McpActivity', () {
    test('finds the newest change an AI app made', () async {
      final seed = _Seed();
      expect(McpActivity.latest(seed.log.readAll()), isNull);
      await _call(seed, 'assign', {
        'categoryId': seed.dining,
        'month': '2026-11',
        'amountCents': 5000,
      });
      final activity = McpActivity.latest(seed.log.readAll())!;
      expect(activity.client.name, 'Claude Desktop');
      expect(activity.summary, contains('Dining out'));
    });
  });
}
