import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _nov1 = CivilDate(2026, 11, 1);
final _nov11 = CivilDate(2026, 11, 11);
final _nov12 = CivilDate(2026, 11, 12);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// A budget named Home with Checking starting at 500.00, and Dining out and
/// Groceries Categories. Each command runs as [actor] over the same log.
final class _Budget {
  _Budget() {
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
    diningOut = category('Dining out');
    groceries = category('Groceries');
  }

  final log = InMemoryEventLog();
  late final String checking;
  late final String diningOut;
  late final String groceries;

  BudgetEngine engine([Actor actor = Actor.userAndroid]) =>
      BudgetEngine(log: log, deviceId: 'device-a', actor: actor);

  BudgetState get state => BudgetState.replay(log.readAll());

  CommandResult execute(Command command, [Actor actor = Actor.userAndroid]) =>
      engine(actor).execute(command);

  List<Event> run(Command command, [Actor actor = Actor.userAndroid]) =>
      _accepted(execute(command, actor));

  /// Enters an outflow with one line and returns the transaction id.
  String spend(
    int cents, {
    String payee = 'Corner Bistro',
    CivilDate? date,
    String? category,
    BusinessStatus? business,
    String? recipient,
    Actor actor = Actor.userAndroid,
  }) =>
      run(
            CreateTransaction(
              accountId: checking,
              date: date ?? _nov12,
              amount: Money(-cents),
              payee: payee,
              lines: [
                LineInput(
                  amount: Money(-cents),
                  category: category,
                  business: business,
                  recipient: recipient,
                ),
              ],
            ),
            actor,
          ).single.payload['transactionId']
          as String;

  TransactionLine line(String transactionId) =>
      state.transaction(transactionId)!.lines.single;

  ReviewLine review(
    String transactionId, {
    String? category,
    BusinessStatus? business,
    String? recipient,
  }) => ReviewLine(
    transactionId: transactionId,
    lineId: line(transactionId).id,
    category: category,
    business: business,
    recipient: recipient,
  );

  /// Adds an account with no starting balance and returns its id.
  String addAccount(String name, AccountType type) =>
      run(
            AddAccount(
              name: name,
              type: type,
              startingBalance: Money.zero,
              asOf: _nov1,
            ),
          ).first.payload['accountId']
          as String;

  /// Moves [cents] from Checking to [toAccountId] as [actor] and returns
  /// the Checking side's transaction id.
  String transfer(String toAccountId, int cents, {required Actor actor}) =>
      run(
            CreateTransfer(
              fromAccountId: checking,
              toAccountId: toAccountId,
              amount: Money(cents),
              date: _nov12,
            ),
            actor,
          ).first.payload['transactionId']
          as String;
}

void main() {
  group('ReviewLine', () {
    test('a person marks a line Reviewed with a ReviewSet', () {
      final budget = _Budget();
      final id = budget.spend(4820);

      final events = budget.run(
        budget.review(
          id,
          category: budget.diningOut,
          business: const Business('Meals'),
        ),
      );

      expect(events.single.type, EventType.reviewSet);
      expect(events.single.payload, {
        'transactionId': id,
        'lineId': budget.line(id).id,
        'category': budget.diningOut,
        'business': 'business',
        'businessTag': 'Meals',
      });
      final line = budget.line(id);
      expect(line.reviewed, isTrue);
      expect(line.category, budget.diningOut);
      expect(line.business, const Business('Meals'));
      expect(budget.state.reviewQueue, isEmpty);
      // The line now counts in Dining out.
      expect(
        budget.state.activity(budget.diningOut, CalendarMonth(2026, 11)),
        const Money(-4820),
      );
    });

    test('no actor but a person can emit it (ADR 0003)', () {
      final budget = _Budget();
      final id = budget.spend(4820);

      for (final actor in const [
        Actor.fromValue('bank-sync'),
        Actor.fromValue('automation'),
        Actor.fromValue('import'),
        Actor.fromValue('mcp:Claude'),
        Actor.fromValue('revert'),
      ]) {
        expect(
          _rejected(
            budget.execute(
              budget.review(
                id,
                category: budget.diningOut,
                business: const Personal(),
              ),
              actor,
            ),
          ),
          Rejection.personRequired,
          reason: actor.value,
        );
      }
      expect(budget.line(id).reviewed, isFalse);
    });

    test('replay ignores a ReviewSet from any other actor', () {
      final budget = _Budget();
      final id = budget.spend(4820);
      final last = budget.engine().events.last.hlc;
      budget.log.append([
        Event(
          id: newId(),
          budgetId: budget.state.budget!.id,
          deviceId: 'device-b',
          hlc: Hlc(last.wallMs + 1, 0, 'device-b'),
          actor: const Actor.fromValue('mcp:Claude'),
          groupId: newId(),
          type: EventType.reviewSet,
          payload: {
            'transactionId': id,
            'lineId': budget.line(id).id,
            'category': budget.diningOut,
            'business': 'personal',
          },
        ),
      ]);

      expect(budget.line(id).reviewed, isFalse);
      expect(budget.line(id).category, isNull);
    });

    test('needs a Category, then a business status, then a tag', () {
      final budget = _Budget();
      final id = budget.spend(4820);

      expect(
        _rejected(budget.execute(budget.review(id, business: Personal()))),
        Rejection.categoryRequired,
      );
      expect(
        _rejected(
          budget.execute(budget.review(id, category: budget.diningOut)),
        ),
        Rejection.businessStatusRequired,
      );
      expect(
        _rejected(
          budget.execute(
            budget.review(
              id,
              category: budget.diningOut,
              business: const Business(' '),
            ),
          ),
        ),
        Rejection.businessTagRequired,
      );
      expect(budget.line(id).reviewed, isFalse);
    });

    test('a gift line needs a recipient', () {
      final budget = _Budget();
      final id = budget.spend(3000, payee: 'Florist');

      expect(
        _rejected(
          budget.execute(
            budget.review(
              id,
              category: budget.groceries,
              business: const Business(giftsTag),
              recipient: '  ',
            ),
          ),
        ),
        Rejection.recipientRequired,
      );

      budget.run(
        budget.review(
          id,
          category: budget.groceries,
          business: const Business(giftsTag),
          recipient: ' Dana ',
        ),
      );
      expect(budget.line(id).reviewed, isTrue);
      expect(budget.line(id).recipient, 'Dana');
    });

    test('rejects a recipient that looks like an account number', () {
      final budget = _Budget();
      final id = budget.spend(3000);

      expect(
        _rejected(
          budget.execute(
            budget.review(
              id,
              category: budget.groceries,
              business: const Business(giftsTag),
              recipient: '4111 1111 1111 1111',
            ),
          ),
        ),
        Rejection.accountNumberNotAllowed,
      );
    });

    test('transfer lines skip business status', () {
      final budget = _Budget();
      final savings = budget.addAccount('Savings', AccountType.savings);
      final id = budget.transfer(
        savings,
        10000,
        actor: const Actor.fromValue('bank-sync'),
      );
      expect(budget.line(id).reviewed, isFalse);

      // The transfer keeps its Category: it has none between two budget
      // accounts.
      budget.run(
        budget.review(
          id,
          category: budget.groceries,
          business: const Personal(),
        ),
      );

      expect(budget.line(id).reviewed, isTrue);
      expect(budget.line(id).category, isNull);
      expect(budget.line(id).business, isNull);
    });

    test('rejects an unknown line and an unchanged Reviewed line', () {
      final budget = _Budget();
      final id = budget.spend(
        4820,
        category: budget.diningOut,
        business: const Personal(),
      );

      expect(
        _rejected(
          budget.execute(
            ReviewLine(
              transactionId: id,
              lineId: 'nope',
              category: budget.diningOut,
              business: const Personal(),
            ),
          ),
        ),
        Rejection.unknownLine,
      );
      expect(
        _rejected(
          budget.execute(
            budget.review(
              id,
              category: budget.diningOut,
              business: const Personal(),
            ),
          ),
        ),
        Rejection.noChange,
      );
    });
  });

  group('the Reviewed rule on entry', () {
    test('a gift line a person enters is Reviewed only with a recipient', () {
      final budget = _Budget();
      final without = budget.spend(
        3000,
        category: budget.groceries,
        business: const Business(giftsTag),
      );
      final withRecipient = budget.spend(
        3000,
        category: budget.groceries,
        business: const Business(giftsTag),
        recipient: 'Dana',
      );

      expect(budget.line(without).reviewed, isFalse);
      expect(budget.line(withRecipient).reviewed, isTrue);
      expect(budget.line(withRecipient).recipient, 'Dana');
    });

    test('editing a gift line keeps its recipient', () {
      final budget = _Budget();
      final id = budget.spend(
        3000,
        category: budget.groceries,
        business: const Business(giftsTag),
        recipient: 'Dana',
      );

      budget.run(EditTransaction(transactionId: id, payee: 'Flower shop'));

      expect(budget.line(id).recipient, 'Dana');
      expect(budget.line(id).reviewed, isTrue);
    });

    test('a Starting Balance is Reviewed and stays out of the queue', () {
      final budget = _Budget();

      final starting = budget.state.transactions.single;
      expect(starting.payee, 'Starting Balance');
      expect(starting.lines.single.reviewed, isTrue);
      expect(budget.state.reviewQueue, isEmpty);
    });

    test('income needs a business status like any other line', () {
      final budget = _Budget();
      final id =
          budget
                  .run(
                    RecordIncome(
                      accountId: budget.checking,
                      amount: const Money(150000),
                      date: _nov12,
                      payee: 'Client',
                    ),
                  )
                  .single
                  .payload['transactionId']
              as String;

      expect(budget.state.reviewQueue.single.transaction.id, id);
      budget.run(
        budget.review(
          id,
          category: readyToAssignCategory,
          business: const Business('Self-employment income'),
        ),
      );
      expect(budget.state.reviewQueue, isEmpty);
    });
  });

  group('reviewQueue', () {
    test('lists Unreviewed lines newest first, split lines in order', () {
      final budget = _Budget();
      final older = budget.spend(275, payee: 'Metro Transit', date: _nov11);
      final reviewed = budget.spend(
        1000,
        category: budget.groceries,
        business: const Personal(),
      );
      final split =
          budget
                  .run(
                    CreateTransaction(
                      accountId: budget.checking,
                      date: _nov12,
                      amount: const Money(-8640),
                      payee: 'Paper & Co.',
                      lines: [
                        LineInput(
                          amount: const Money(-6000),
                          category: budget.groceries,
                          business: const Personal(),
                        ),
                        const LineInput(amount: Money(-2000)),
                        const LineInput(amount: Money(-640)),
                      ],
                    ),
                  )
                  .single
                  .payload['transactionId']
              as String;
      final bankSync = budget.spend(
        4820,
        category: budget.diningOut,
        business: const Personal(),
        actor: const Actor.fromValue('bank-sync'),
      );

      final queue = budget.state.reviewQueue;
      expect(queue.map((item) => item.transaction.id), [
        bankSync,
        split,
        split,
        older,
      ]);
      expect(
        queue.map((item) => item.transaction.id),
        isNot(contains(reviewed)),
      );
      expect(queue[1].line.amount, const Money(-2000));
      expect(queue[2].line.amount, const Money(-640));
    });

    test('leaves out transfer lines and tracking-account lines', () {
      final budget = _Budget();
      const bankSync = Actor.fromValue('bank-sync');
      final savings = budget.addAccount('Savings', AccountType.savings);
      final retirement = budget.addAccount('401k', AccountType.tracking);
      budget.transfer(savings, 10000, actor: bankSync);
      budget.run(
        CreateTransaction(
          accountId: retirement,
          date: _nov12,
          amount: const Money(-1500),
          payee: 'Fund fee',
          lines: [const LineInput(amount: Money(-1500))],
        ),
        bankSync,
      );
      final spend = budget.spend(4820, actor: bankSync);

      expect(budget.state.reviewQueue.map((item) => item.transaction.id), [
        spend,
      ]);
    });
  });

  group('payeeHint', () {
    test("is the payee's most recently Reviewed values", () {
      final budget = _Budget();
      budget.spend(
        3000,
        date: _nov1,
        category: budget.groceries,
        business: const Personal(),
      );
      budget.spend(
        5100,
        date: _nov11,
        category: budget.diningOut,
        business: const Business('Meals'),
      );
      // Pre-filled by bank sync, so not a person's choice.
      budget.spend(
        900,
        date: _nov12,
        category: budget.groceries,
        business: const Personal(),
        actor: const Actor.fromValue('bank-sync'),
      );
      final current = budget.spend(4820);

      final hint = budget.state.payeeHint(
        'corner bistro ',
        exceptTransactionId: current,
      )!;
      expect(hint.category, budget.diningOut);
      expect(hint.business, const Business('Meals'));
      // Showing the hint applies nothing.
      expect(budget.line(current).reviewed, isFalse);
      expect(budget.line(current).category, isNull);
    });

    test('is null for a new payee', () {
      final budget = _Budget();
      budget.spend(
        3000,
        category: budget.groceries,
        business: const Personal(),
      );

      expect(budget.state.payeeHint('Paper & Co.'), isNull);
    });
  });
}
