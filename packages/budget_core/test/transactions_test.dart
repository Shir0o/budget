import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _nov = CalendarMonth(2026, 11);
final _nov1 = CivilDate(2026, 11, 1);
final _nov12 = CivilDate(2026, 11, 12);
final _nov13 = CivilDate(2026, 11, 13);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// A budget named Home with a checking account starting at 500.00, and
/// Groceries and Household Categories.
final class _Budget {
  _Budget({this.actor = Actor.userAndroid}) {
    run(const CreateBudget(name: 'Home'));
    run(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
        asOf: _nov1,
      ),
    );
    checking = state.accounts.single.id;
    final group =
        run(const CreateCategoryGroup(name: 'Everyday'))
                .single
                .payload['categoryGroupId']
            as String;
    String category(String name) =>
        run(CreateCategory(groupId: group, name: name))
                .single
                .payload['categoryId']
            as String;
    groceries = category('Groceries');
    household = category('Household');
  }

  final Actor actor;
  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'device-a',
    actor: actor,
  );
  late final String checking;
  late final String groceries;
  late final String household;

  BudgetState get state => engine.state;

  List<Event> run(Command command) => _accepted(engine.execute(command));

  /// Enters a transaction and returns its id.
  String enter(
    int cents,
    List<LineInput> lines, {
    String payee = 'Target',
    CivilDate? date,
  }) =>
      run(
            CreateTransaction(
              accountId: checking,
              date: date ?? _nov12,
              amount: Money(cents),
              lines: lines,
              payee: payee,
            ),
          ).single.payload['transactionId']
          as String;

  void assign(String categoryId, int cents) => run(
    SetAssignment(categoryId: categoryId, month: _nov, amount: Money(cents)),
  );
}

void main() {
  group('CreateTransaction', () {
    test('ticket 07 example 7: each split line applies on its own', () {
      // A $120 Target purchase split into $80 Groceries and $40 Household.
      final budget = _Budget();
      budget.assign(budget.groceries, 10000);
      budget.assign(budget.household, 5000);
      final rtaBefore = budget.state.readyToAssign(_nov);

      final id = budget.enter(-12000, [
        LineInput(amount: const Money(-8000), category: budget.groceries),
        LineInput(amount: const Money(-4000), category: budget.household),
      ]);

      final state = budget.state;
      expect(state.transaction(id)!.amount, const Money(-12000));
      expect(state.transaction(id)!.isSplit, isTrue);
      expect(state.activity(budget.groceries, _nov), const Money(-8000));
      expect(state.activity(budget.household, _nov), const Money(-4000));
      expect(state.available(budget.groceries, _nov), const Money(2000));
      expect(state.available(budget.household, _nov), const Money(1000));
      expect(state.readyToAssign(_nov), rtaBefore);
      expect(state.balance(budget.checking), const Money(38000));
    });

    test('split lines must sum to the amount', () {
      final budget = _Budget();
      final before = budget.log.readAll().length;

      expect(
        _rejected(
          budget.engine.execute(
            CreateTransaction(
              accountId: budget.checking,
              date: _nov12,
              amount: const Money(-12000),
              lines: [
                LineInput(
                  amount: const Money(-8000),
                  category: budget.groceries,
                ),
                LineInput(
                  amount: const Money(-3000),
                  category: budget.household,
                ),
              ],
            ),
          ),
        ),
        Rejection.splitDoesNotSum,
      );
      expect(budget.log.readAll(), hasLength(before));
    });

    test('rejects no lines, 0.00 and an unknown account or Category', () {
      final budget = _Budget();
      CommandResult create(
        int cents,
        List<LineInput> lines, {
        String? accountId,
      }) => budget.engine.execute(
        CreateTransaction(
          accountId: accountId ?? budget.checking,
          date: _nov12,
          amount: Money(cents),
          lines: lines,
        ),
      );

      expect(_rejected(create(-100, const [])), Rejection.noLines);
      expect(
        _rejected(create(0, const [LineInput(amount: Money.zero)])),
        Rejection.zeroAmount,
      );
      expect(
        _rejected(
          create(-100, const [
            LineInput(amount: Money(-100)),
          ], accountId: 'nope'),
        ),
        Rejection.unknownAccount,
      );
      expect(
        _rejected(
          create(-100, const [LineInput(amount: Money(-100), category: 'x')]),
        ),
        Rejection.unknownCategory,
      );
      expect(
        _rejected(
          create(-100, const [
            LineInput(amount: Money(-100), business: Business(' ')),
          ]),
        ),
        Rejection.businessTagRequired,
      );
    });

    test('each line keeps its own Category, business status and memo', () {
      final budget = _Budget();
      final id = budget.enter(-8640, [
        LineInput(
          amount: const Money(-6440),
          category: budget.groceries,
          business: const Business('Supplies'),
          memo: ' printer paper, toner ',
        ),
        LineInput(
          amount: const Money(-2200),
          category: budget.household,
          business: const Personal(),
        ),
      ], payee: 'Paper & Co.');

      final lines = budget.state.transaction(id)!.lines;
      expect(lines.map((l) => l.category), [
        budget.groceries,
        budget.household,
      ]);
      expect(lines.map((l) => l.business), [
        const Business('Supplies'),
        const Personal(),
      ]);
      expect(lines.map((l) => l.memo), ['printer paper, toner', '']);
    });

    test('a line a person sets both fields on is Reviewed', () {
      final budget = _Budget();
      final id = budget.enter(-3000, [
        LineInput(
          amount: const Money(-1000),
          category: budget.groceries,
          business: const Personal(),
        ),
        LineInput(amount: const Money(-1000), category: budget.groceries),
        const LineInput(amount: Money(-1000), business: Personal()),
      ]);

      expect(budget.state.transaction(id)!.lines.map((l) => l.reviewed), [
        true,
        false,
        false,
      ]);
    });

    test('only a person marks a line Reviewed (ADR 0003)', () {
      final budget = _Budget(actor: const Actor.fromValue('bank-sync'));
      final id = budget.enter(-1000, [
        LineInput(
          amount: const Money(-1000),
          category: budget.groceries,
          business: const Personal(),
        ),
      ]);

      expect(budget.state.transaction(id)!.lines.single.reviewed, isFalse);
    });

    test('starts uncleared and counts toward the cleared balance once '
        'cleared', () {
      final budget = _Budget();
      final id = budget.enter(-1250, [
        LineInput(amount: const Money(-1250), category: budget.groceries),
      ]);

      expect(budget.state.transaction(id)!.cleared, ClearedStatus.uncleared);
      // The Starting Balance is cleared.
      expect(budget.state.clearedBalance(budget.checking), const Money(50000));
      expect(budget.state.balance(budget.checking), const Money(48750));

      budget.run(
        EditTransaction(transactionId: id, cleared: ClearedStatus.cleared),
      );
      expect(budget.state.clearedBalance(budget.checking), const Money(48750));
    });
  });

  group('Ready to Assign (ticket 07, 09)', () {
    test('income to Ready to Assign raises it', () {
      final budget = _Budget();
      budget.enter(300000, [
        const LineInput(amount: Money(300000), category: readyToAssignCategory),
      ], payee: 'Payroll');

      expect(budget.state.readyToAssign(_nov), const Money(350000));
    });

    test('an inflow to a Category is a refund, not income', () {
      final budget = _Budget();
      budget.enter(2000, [
        LineInput(amount: const Money(2000), category: budget.groceries),
      ]);

      expect(budget.state.readyToAssign(_nov), const Money(50000));
      expect(budget.state.available(budget.groceries, _nov), const Money(2000));
    });

    test('an uncategorized outflow reduces it until categorized', () {
      final budget = _Budget();
      budget.assign(budget.groceries, 10000);
      final id = budget.enter(-975, const [LineInput(amount: Money(-975))]);

      expect(budget.state.readyToAssign(_nov), const Money(40000 - 975));
      expect(
        budget.state.available(budget.groceries, _nov),
        const Money(10000),
      );

      final line = budget.state.transaction(id)!.lines.single;
      budget.run(
        EditTransaction(
          transactionId: id,
          lines: [
            LineInput(
              id: line.id,
              amount: line.amount,
              category: budget.groceries,
            ),
          ],
        ),
      );

      expect(budget.state.readyToAssign(_nov), const Money(40000));
      expect(budget.state.available(budget.groceries, _nov), const Money(9025));
      expect(budget.state.transaction(id)!.lines.single.id, line.id);
    });

    test('an uncategorized inflow doesn’t count until categorized', () {
      final budget = _Budget();
      budget.enter(1000, const [LineInput(amount: Money(1000))]);

      expect(budget.state.readyToAssign(_nov), const Money(50000));
    });
  });

  group('Blocked content (ticket 09)', () {
    test('payee and memos reject card and account numbers', () {
      final budget = _Budget();
      final before = budget.log.readAll().length;
      CommandResult create({
        String payee = '',
        String memo = '',
        String lineMemo = '',
      }) => budget.engine.execute(
        CreateTransaction(
          accountId: budget.checking,
          date: _nov12,
          amount: const Money(-100),
          payee: payee,
          memo: memo,
          lines: [LineInput(amount: const Money(-100), memo: lineMemo)],
        ),
      );

      expect(
        _rejected(create(payee: 'Card 4111 1111 1111 1111')),
        Rejection.accountNumberNotAllowed,
      );
      expect(
        _rejected(create(memo: 'routing 123456780')),
        Rejection.accountNumberNotAllowed,
      );
      expect(
        _rejected(create(lineMemo: 'acct 12345678')),
        Rejection.accountNumberNotAllowed,
      );
      expect(budget.log.readAll(), hasLength(before));

      expect(
        _rejected(
          budget.engine.execute(
            RecordIncome(
              accountId: budget.checking,
              amount: const Money(100),
              date: _nov12,
              payee: '4111-1111-1111-1111',
            ),
          ),
        ),
        Rejection.accountNumberNotAllowed,
      );
    });

    test('edits reject them too', () {
      final budget = _Budget();
      final id = budget.enter(-100, const [LineInput(amount: Money(-100))]);

      expect(
        _rejected(
          budget.engine.execute(
            EditTransaction(transactionId: id, payee: '12345678'),
          ),
        ),
        Rejection.accountNumberNotAllowed,
      );
      expect(
        _rejected(
          budget.engine.execute(
            EditTransaction(
              transactionId: id,
              lines: const [LineInput(amount: Money(-100), memo: '12345678')],
            ),
          ),
        ),
        Rejection.accountNumberNotAllowed,
      );
    });
  });

  group('EditTransaction', () {
    test('sets only the fields that changed, as one group', () {
      final budget = _Budget();
      final id = budget.enter(-1250, [
        LineInput(amount: const Money(-1250), category: budget.groceries),
      ], payee: 'Farmers market');

      final events = budget.run(
        EditTransaction(
          transactionId: id,
          payee: 'Farmers market',
          memo: 'Store pickup',
          date: _nov13,
        ),
      );

      expect(events.single.type, EventType.transactionFieldsSet);
      expect(events.single.payload['fields'], {
        'memo': 'Store pickup',
        'date': '2026-11-13',
      });
      final transaction = budget.state.transaction(id)!;
      expect(transaction.memo, 'Store pickup');
      expect(transaction.date, _nov13);
      expect(transaction.payee, 'Farmers market');
    });

    test('replaces the whole line set, and the lines must sum', () {
      final budget = _Budget();
      final id = budget.enter(-8640, [
        LineInput(amount: const Money(-8640), category: budget.groceries),
      ]);

      expect(
        _rejected(
          budget.engine.execute(
            EditTransaction(
              transactionId: id,
              lines: [
                LineInput(
                  amount: const Money(-6440),
                  category: budget.groceries,
                ),
              ],
            ),
          ),
        ),
        Rejection.splitDoesNotSum,
      );

      final events = budget.run(
        EditTransaction(
          transactionId: id,
          payee: 'Paper & Co.',
          lines: [
            LineInput(amount: const Money(-6440), category: budget.groceries),
            LineInput(amount: const Money(-2200), category: budget.household),
          ],
        ),
      );

      expect(events.map((e) => e.type), [
        EventType.transactionFieldsSet,
        EventType.transactionSplitSet,
      ]);
      expect(events.map((e) => e.groupId).toSet(), hasLength(1));
      expect(budget.state.activity(budget.household, _nov), const Money(-2200));
      expect(budget.state.activity(budget.groceries, _nov), const Money(-6440));
    });

    test('changes the amount together with its lines', () {
      final budget = _Budget();
      final id = budget.enter(-1250, [
        LineInput(amount: const Money(-1250), category: budget.groceries),
      ]);

      expect(
        _rejected(
          budget.engine.execute(
            EditTransaction(transactionId: id, amount: const Money(-1500)),
          ),
        ),
        Rejection.splitDoesNotSum,
      );
      budget.run(
        EditTransaction(
          transactionId: id,
          amount: const Money(-1500),
          lines: [
            LineInput(amount: const Money(-1500), category: budget.groceries),
          ],
        ),
      );
      expect(budget.state.transaction(id)!.amount, const Money(-1500));
      expect(budget.state.balance(budget.checking), const Money(48500));
    });

    test('with nothing new is refused', () {
      final budget = _Budget();
      final id = budget.enter(-1250, [
        LineInput(amount: const Money(-1250), category: budget.groceries),
      ], payee: 'Farmers market');
      final line = budget.state.transaction(id)!.lines.single;

      expect(
        _rejected(
          budget.engine.execute(
            EditTransaction(
              transactionId: id,
              payee: 'Farmers market',
              cleared: ClearedStatus.uncleared,
              lines: [
                LineInput(
                  id: line.id,
                  amount: line.amount,
                  category: line.category,
                ),
              ],
            ),
          ),
        ),
        Rejection.noChange,
      );
    });

    test('of a missing transaction is refused', () {
      final budget = _Budget();
      expect(
        _rejected(
          budget.engine.execute(
            const EditTransaction(transactionId: 'nope', payee: 'x'),
          ),
        ),
        Rejection.unknownTransaction,
      );
    });
  });

  group('DeleteTransaction', () {
    test('removes it from the register and the budget math', () {
      final budget = _Budget();
      final id = budget.enter(-975, const [LineInput(amount: Money(-975))]);

      budget.run(DeleteTransaction(transactionId: id));

      expect(budget.state.transaction(id), isNull);
      expect(budget.state.register(budget.checking), hasLength(1));
      expect(budget.state.readyToAssign(_nov), const Money(50000));
      expect(
        _rejected(
          budget.engine.execute(EditTransaction(transactionId: id, memo: 'x')),
        ),
        Rejection.unknownTransaction,
      );
    });
  });

  group('register', () {
    test('lists an account’s transactions, newest first', () {
      final budget = _Budget();
      budget.enter(-100, const [
        LineInput(amount: Money(-100)),
      ], payee: 'Corner Store');
      budget.enter(
        -200,
        const [LineInput(amount: Money(-200))],
        payee: 'City Power',
        date: _nov13,
      );
      budget.enter(-300, const [
        LineInput(amount: Money(-300)),
      ], payee: 'Paper & Co.');

      expect(budget.state.register(budget.checking).map((t) => t.payee), [
        'City Power',
        'Paper & Co.',
        'Corner Store',
        'Starting Balance',
      ]);
    });
  });

  group('Merging two devices (ticket 06)', () {
    /// The budget's log copied to a second device, with each device's
    /// clock set so that device B's edits come after device A's.
    (BudgetEngine, BudgetEngine) twoDevices(_Budget budget) {
      final base = budget.engine.events.last.hlc.wallMs;
      final logB = InMemoryEventLog()..append(budget.log.readAll());
      return (
        BudgetEngine(
          log: budget.log,
          deviceId: 'device-a',
          actor: Actor.userAndroid,
          nowMs: () => base + 10,
        ),
        BudgetEngine(
          log: logB,
          deviceId: 'device-b',
          actor: const Actor.fromValue('user@mac'),
          nowMs: () => base + 20,
        ),
      );
    }

    BudgetState merged(BudgetEngine a, BudgetEngine b) =>
        BudgetState.replay({...a.events, ...b.events});

    test('each field is last writer wins on its own', () {
      final budget = _Budget();
      final id = budget.enter(-1250, [
        LineInput(amount: const Money(-1250), category: budget.groceries),
      ], payee: 'Farmers market');
      final (a, b) = twoDevices(budget);

      _accepted(
        a.execute(
          EditTransaction(transactionId: id, payee: 'Market', memo: 'eggs'),
        ),
      );
      _accepted(b.execute(EditTransaction(transactionId: id, payee: 'Farm')));

      final transaction = merged(a, b).transaction(id)!;
      expect(transaction.payee, 'Farm');
      expect(transaction.memo, 'eggs');
    });

    test('split lines are replaced as a whole', () {
      final budget = _Budget();
      final id = budget.enter(-12000, [
        LineInput(amount: const Money(-12000), category: budget.groceries),
      ]);
      final (a, b) = twoDevices(budget);

      _accepted(
        a.execute(
          EditTransaction(
            transactionId: id,
            lines: [
              LineInput(amount: const Money(-8000), category: budget.groceries),
              LineInput(amount: const Money(-4000), category: budget.household),
            ],
          ),
        ),
      );
      _accepted(
        b.execute(
          EditTransaction(
            transactionId: id,
            lines: [
              LineInput(
                amount: const Money(-12000),
                category: budget.household,
              ),
            ],
          ),
        ),
      );

      final lines = merged(a, b).transaction(id)!.lines;
      expect(lines.map((l) => (l.category, l.amount)), [
        (budget.household, const Money(-12000)),
      ]);
    });

    test('a delete beats a later edit', () {
      final budget = _Budget();
      final id = budget.enter(-1250, const [LineInput(amount: Money(-1250))]);
      final (a, b) = twoDevices(budget);

      _accepted(a.execute(DeleteTransaction(transactionId: id)));
      _accepted(b.execute(EditTransaction(transactionId: id, memo: 'eggs')));

      final state = merged(a, b);
      expect(state.transaction(id), isNull);
      expect(state.balance(budget.checking), const Money(50000));
    });
  });
}
