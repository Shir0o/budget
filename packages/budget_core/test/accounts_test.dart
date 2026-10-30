import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _nov = CalendarMonth(2026, 11);
final _dec = CalendarMonth(2026, 12);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// A synthetic budget: Checking with $1,000.00 in Ready to Assign, and
/// Groceries and Dining out in Everyday.
final class _Budget {
  _Budget() {
    _accepted(engine.execute(const CreateBudget(name: 'Home')));
    checking = account('Checking', AccountType.checking, 100000);
    final group =
        _accepted(engine.execute(const CreateCategoryGroup(name: 'Everyday')))
                .single
                .payload['categoryGroupId']
            as String;
    groceries = _category(group, 'Groceries');
    dining = _category(group, 'Dining out');
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'device-a',
    actor: Actor.userAndroid,
  );
  late final String checking;
  late final String groceries;
  late final String dining;

  BudgetState get state => engine.state;

  String _category(String group, String name) =>
      _accepted(engine.execute(CreateCategory(groupId: group, name: name)))
              .single
              .payload['categoryId']
          as String;

  String account(String name, AccountType type, int cents) {
    final events = _accepted(
      engine.execute(
        AddAccount(
          name: name,
          type: type,
          startingBalance: Money(cents),
          asOf: CivilDate(2026, 11, 1),
        ),
      ),
    );
    return events.first.payload['accountId'] as String;
  }

  void assign(String categoryId, int cents, {CalendarMonth? month}) =>
      _accepted(
        engine.execute(
          SetAssignment(
            categoryId: categoryId,
            month: month ?? _nov,
            amount: Money(cents),
          ),
        ),
      );

  String spend(String accountId, String? categoryId, int cents, {int day = 5}) {
    final events = _accepted(
      engine.execute(
        CreateTransaction(
          accountId: accountId,
          date: CivilDate(2026, 11, day),
          amount: Money(-cents),
          lines: [LineInput(amount: Money(-cents), category: categoryId)],
        ),
      ),
    );
    return events.single.payload['transactionId'] as String;
  }

  List<Event> transfer(
    String from,
    String to,
    int cents, {
    String? category,
    int day = 20,
  }) => _accepted(
    engine.execute(
      CreateTransfer(
        fromAccountId: from,
        toAccountId: to,
        amount: Money(cents),
        date: CivilDate(2026, 11, day),
        category: category,
      ),
    ),
  );

  Money available(String categoryId, [CalendarMonth? month]) =>
      state.available(categoryId, month ?? _nov);

  String payment(String card) => state.cardPaymentCategory(card)!.id;
}

void main() {
  group('Credit card accounts', () {
    test('each card gets a Card Payment Category in one group', () {
      final budget = _Budget();
      final visa = budget.account('Visa', AccountType.creditCard, 0);
      final amex = budget.account('Amex', AccountType.creditCard, 0);
      final state = budget.state;

      final visaPayment = state.cardPaymentCategory(visa)!;
      final amexPayment = state.cardPaymentCategory(amex)!;
      expect(visaPayment.name, 'Visa Payment');
      expect(visaPayment.cardAccountId, visa);
      expect(amexPayment.name, 'Amex Payment');
      expect(amexPayment.groupId, visaPayment.groupId);
      expect(
        state.categoryGroup(visaPayment.groupId)?.name,
        'Credit Card Payments',
      );
      expect(state.cardPaymentCategory(budget.checking), isNull);
    });

    test('ticket 07 example 6: existing card debt starts unfunded', () {
      final budget = _Budget();
      final visa = budget.account('Visa', AccountType.creditCard, -64218);
      final state = budget.state;

      expect(state.balance(visa), const Money(-64218));
      expect(budget.available(budget.payment(visa)), Money.zero);
      expect(state.unfundedDebt(visa, _nov), const Money(64218));
      // Ready to Assign is unchanged.
      expect(state.readyToAssign(_nov), const Money(100000));
      expect(state.readyToAssign(_dec), const Money(100000));
      final opening = state.register(visa).single;
      expect(opening.payee, 'Starting Balance');
      expect(opening.lines.single.category, isNull);
      expect(opening.lines.single.reviewed, isTrue);
    });

    test('ticket 07 example 3: funded card spending, then a payment', () {
      final budget = _Budget();
      final visa = budget.account('Visa', AccountType.creditCard, 0);
      budget.assign(budget.groceries, 10000);

      budget.spend(visa, budget.groceries, 6000);
      expect(budget.available(budget.groceries), const Money(4000));
      expect(budget.available(budget.payment(visa)), const Money(6000));
      expect(
        budget.state.activity(budget.payment(visa), _nov),
        const Money(6000),
      );
      expect(budget.state.unfundedDebt(visa, _nov), Money.zero);

      final events = budget.transfer(budget.checking, visa, 6000);
      expect(events, hasLength(2));
      final state = budget.state;
      expect(budget.available(budget.payment(visa)), Money.zero);
      expect(state.balance(visa), Money.zero);
      expect(state.balance(budget.checking), const Money(94000));
      expect(budget.available(budget.groceries), const Money(4000));
      // A transfer between budget accounts leaves Ready to Assign alone.
      expect(state.readyToAssign(_nov), const Money(90000));
      expect(state.readyToAssign(_dec), const Money(90000));
    });

    test('ticket 07 example 4: credit overspending becomes card debt', () {
      final budget = _Budget();
      final visa = budget.account('Visa', AccountType.creditCard, 0);
      budget.assign(budget.groceries, 10000);

      budget.spend(visa, budget.groceries, 15000);
      var state = budget.state;
      expect(budget.available(budget.payment(visa)), const Money(10000));
      expect(budget.available(budget.groceries), const Money(-5000));
      expect(
        state.creditOverspending(budget.groceries, _nov),
        const Money(5000),
      );
      expect(state.cashOverspending(budget.groceries, _nov), Money.zero);

      // Next month Groceries carries 0 and Ready to Assign is unchanged.
      expect(state.carry(budget.groceries, _dec), Money.zero);
      expect(state.readyToAssign(_dec), const Money(90000));
      expect(state.unfundedDebt(visa, _dec), const Money(5000));

      budget.assign(budget.payment(visa), 5000, month: _dec);
      state = budget.state;
      expect(state.unfundedDebt(visa, _dec), Money.zero);
      expect(state.readyToAssign(_dec), const Money(85000));
    });

    test('ticket 07 example 2: cash overspending reduces next month', () {
      final budget = _Budget();
      budget.assign(budget.dining, 2000);

      budget.spend(budget.checking, budget.dining, 5000);
      final state = budget.state;
      expect(budget.available(budget.dining), const Money(-3000));
      expect(state.cashOverspending(budget.dining, _nov), const Money(3000));
      expect(state.creditOverspending(budget.dining, _nov), Money.zero);
      expect(state.carry(budget.dining, _dec), Money.zero);
      expect(state.readyToAssign(_nov), const Money(98000));
      expect(state.readyToAssign(_dec), const Money(95000));
    });

    test(
      'cash spending first, then card spending, splits the overspending',
      () {
        final budget = _Budget();
        final visa = budget.account('Visa', AccountType.creditCard, 0);
        budget.assign(budget.dining, 2000);

        budget.spend(budget.checking, budget.dining, 5000, day: 3);
        budget.spend(visa, budget.dining, 1000, day: 4);
        final state = budget.state;
        expect(budget.available(budget.dining), const Money(-4000));
        expect(state.cashOverspending(budget.dining, _nov), const Money(3000));
        expect(
          state.creditOverspending(budget.dining, _nov),
          const Money(1000),
        );
        expect(state.readyToAssign(_dec), const Money(95000));
        expect(state.unfundedDebt(visa, _nov), const Money(1000));
      },
    );

    test('ticket 07 example 5: a card refund moves back', () {
      final budget = _Budget();
      final visa = budget.account('Visa', AccountType.creditCard, 0);
      budget.assign(budget.groceries, 10000);
      budget.spend(visa, budget.groceries, 6000);

      _accepted(
        budget.engine.execute(
          CreateTransaction(
            accountId: visa,
            date: CivilDate(2026, 11, 9),
            amount: const Money(2000),
            lines: [
              LineInput(amount: const Money(2000), category: budget.groceries),
            ],
          ),
        ),
      );
      expect(budget.available(budget.groceries), const Money(6000));
      expect(budget.available(budget.payment(visa)), const Money(4000));
    });

    test('uncategorized card spending is funded from Ready to Assign', () {
      final budget = _Budget();
      final visa = budget.account('Visa', AccountType.creditCard, 0);

      budget.spend(visa, null, 2500);
      final state = budget.state;
      expect(state.readyToAssign(_nov), const Money(97500));
      expect(budget.available(budget.payment(visa)), const Money(2500));
      expect(state.unfundedDebt(visa, _nov), Money.zero);
    });

    test('a cash advance is unfunded debt and new Ready to Assign', () {
      final budget = _Budget();
      final visa = budget.account('Visa', AccountType.creditCard, 0);

      // As in YNAB: the cash lands in Ready to Assign ("Inflow from Debt
      // Account") and Visa Payment doesn't move, so the debt is unfunded.
      budget.transfer(visa, budget.checking, 10000);
      var state = budget.state;
      expect(state.balance(budget.checking), const Money(110000));
      expect(state.balance(visa), const Money(-10000));
      expect(budget.available(budget.payment(visa)), Money.zero);
      expect(state.unfundedDebt(visa, _nov), const Money(10000));
      expect(state.readyToAssign(_nov), const Money(110000));
      expect(state.netWorth, const Money(100000));

      // Funding the debt, then paying it off, leaves the budget whole.
      budget.assign(budget.payment(visa), 10000);
      budget.transfer(budget.checking, visa, 10000, day: 25);
      state = budget.state;
      expect(budget.available(budget.payment(visa)), Money.zero);
      expect(state.unfundedDebt(visa, _nov), Money.zero);
      expect(state.readyToAssign(_nov), const Money(100000));
      expect(state.readyToAssign(_dec), const Money(100000));
    });
  });

  group('Ready to Assign', () {
    test('counts each transaction from the month of its date', () {
      final budget = _Budget();
      void enter(int cents, String? category, CivilDate date) => _accepted(
        budget.engine.execute(
          CreateTransaction(
            accountId: budget.checking,
            date: date,
            amount: Money(cents),
            lines: [LineInput(amount: Money(cents), category: category)],
          ),
        ),
      );

      enter(300000, readyToAssignCategory, CivilDate(2026, 12, 15));
      enter(-2000, null, CivilDate(2026, 12, 16));
      final state = budget.state;
      expect(state.readyToAssign(_nov), const Money(100000));
      expect(state.readyToAssign(_dec), const Money(398000));
    });
  });

  group('Tracking accounts', () {
    test('count toward net worth only', () {
      final budget = _Budget();
      final retirement = budget.account(
        'Retirement 401k',
        AccountType.tracking,
        4830000,
      );
      budget.spend(retirement, null, 10000);
      final state = budget.state;

      expect(state.account(retirement)!.type.onBudget, isFalse);
      expect(state.balance(retirement), const Money(4820000));
      expect(state.netWorth, const Money(4920000));
      expect(state.readyToAssign(_nov), const Money(100000));
      expect(state.readyToAssign(_dec), const Money(100000));
    });

    test('a transfer out of the budget needs a Category', () {
      final budget = _Budget();
      final retirement = budget.account('401k', AccountType.tracking, 0);
      final savings = budget.account('Savings', AccountType.savings, 0);
      final engine = budget.engine;
      CreateTransfer transfer(String from, String to, {String? category}) =>
          CreateTransfer(
            fromAccountId: from,
            toAccountId: to,
            amount: const Money(50000),
            date: CivilDate(2026, 11, 15),
            category: category,
          );

      expect(
        _rejected(engine.execute(transfer(budget.checking, retirement))),
        Rejection.transferCategoryRequired,
      );
      expect(
        _rejected(
          engine.execute(
            transfer(
              budget.checking,
              retirement,
              category: readyToAssignCategory,
            ),
          ),
        ),
        Rejection.transferCategoryRequired,
      );
      expect(
        _rejected(
          engine.execute(
            transfer(budget.checking, savings, category: budget.groceries),
          ),
        ),
        Rejection.transferHasNoCategory,
      );
      expect(
        _rejected(engine.execute(transfer(budget.checking, budget.checking))),
        Rejection.sameAccount,
      );

      budget.assign(budget.groceries, 50000);
      budget.transfer(
        budget.checking,
        retirement,
        50000,
        category: budget.groceries,
      );
      final state = budget.state;
      expect(budget.available(budget.groceries), Money.zero);
      expect(state.balance(retirement), const Money(50000));
      expect(state.netWorth, const Money(100000));

      // Coming back in, it can go to Ready to Assign.
      budget.transfer(
        retirement,
        budget.checking,
        20000,
        category: readyToAssignCategory,
      );
      expect(budget.state.readyToAssign(_nov), const Money(70000));
    });
  });

  group('Transfers', () {
    test('both sides are linked and Reviewed, and delete together', () {
      final budget = _Budget();
      final savings = budget.account('Savings', AccountType.savings, 0);
      final events = budget.transfer(budget.checking, savings, 30000);
      final fromId = events[0].payload['transactionId'] as String;
      final toId = events[1].payload['transactionId'] as String;
      var state = budget.state;

      final from = state.transaction(fromId)!;
      final to = state.transaction(toId)!;
      expect(from.amount, const Money(-30000));
      expect(from.transferAccountId, savings);
      expect(from.transferTransactionId, toId);
      expect(to.amount, const Money(30000));
      expect(to.transferAccountId, budget.checking);
      expect(from.lines.single.reviewed && to.lines.single.reviewed, isTrue);
      expect(state.readyToAssign(_nov), const Money(100000));

      _accepted(budget.engine.execute(DeleteTransaction(transactionId: toId)));
      state = budget.state;
      expect(state.transaction(fromId), isNull);
      expect(state.transaction(toId), isNull);
    });

    test('a new date or amount on one side is copied to the other', () {
      final budget = _Budget();
      final savings = budget.account('Savings', AccountType.savings, 0);
      final events = budget.transfer(budget.checking, savings, 30000);
      final fromId = events[0].payload['transactionId'] as String;
      final toId = events[1].payload['transactionId'] as String;
      final from = budget.state.transaction(fromId)!;

      _accepted(
        budget.engine.execute(
          EditTransaction(
            transactionId: fromId,
            date: CivilDate(2026, 11, 22),
            amount: const Money(-25000),
            lines: [
              LineInput(id: from.lines.single.id, amount: const Money(-25000)),
            ],
          ),
        ),
      );
      final to = budget.state.transaction(toId)!;
      expect(to.date, CivilDate(2026, 11, 22));
      expect(to.amount, const Money(25000));
      expect(to.lines.single.amount, const Money(25000));
      expect(budget.state.balance(savings), const Money(25000));

      expect(
        _rejected(
          budget.engine.execute(
            EditTransaction(
              transactionId: fromId,
              amount: const Money(-25000),
              lines: const [
                LineInput(amount: Money(-20000)),
                LineInput(amount: Money(-5000)),
              ],
            ),
          ),
        ),
        Rejection.transferCannotSplit,
      );
    });
  });
}
