import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _nov = CalendarMonth(2026, 11);
final _dec = CalendarMonth(2026, 12);
final _jan = CalendarMonth(2027, 1);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// A budget named Home whose checking account starts with $1,000 in Ready to
/// Assign on Nov 1, 2026, with a Bills group. The clock reads Nov 15, 2026.
final class _Budget {
  _Budget({Money income = const Money(100000)}) {
    run(const CreateBudget(name: 'Home'));
    run(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: income,
        asOf: CivilDate(2026, 11, 1),
      ),
    );
    checking = state.accounts.single.id;
    bills =
        run(const CreateCategoryGroup(name: 'Bills'))
                .single
                .payload['categoryGroupId']
            as String;
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'device-a',
    actor: Actor.userAndroid,
    nowMs: () => DateTime(2026, 11, 15, 9).millisecondsSinceEpoch,
  );
  late final String checking;
  late final String bills;

  BudgetState get state => engine.state;

  List<Event> run(Command command) => _accepted(engine.execute(command));

  String category(String name) =>
      run(CreateCategory(groupId: bills, name: name))
              .single
              .payload['categoryId']
          as String;

  /// Adds a Scheduled Transaction and answers its id.
  String schedule({
    required Money amount,
    required String payee,
    required CivilDate nextDue,
    String? accountId,
    String? categoryId,
    int every = 1,
    TargetInterval interval = TargetInterval.months,
  }) =>
      run(
            CreateSchedule(
              accountId: accountId ?? checking,
              payee: payee,
              amount: amount,
              category: categoryId ?? readyToAssignCategory,
              every: every,
              interval: interval,
              nextDue: nextDue,
            ),
          ).single.payload['scheduleId']
          as String;

  void assign(String categoryId, CalendarMonth month, int cents) => run(
    SetAssignment(categoryId: categoryId, month: month, amount: Money(cents)),
  );

  void spend(
    String categoryId,
    CivilDate date,
    int cents, {
    String payee = '',
  }) => run(
    CreateTransaction(
      accountId: checking,
      date: date,
      payee: payee,
      amount: Money(-cents),
      lines: [LineInput(amount: Money(-cents), category: categoryId)],
    ),
  );
}

void main() {
  group('Scheduled Transactions never count until they happen', () {
    test('a schedule leaves the balance, Available and Ready to Assign '
        'alone', () {
      final budget = _Budget();
      final car = budget.category('Car insurance');
      final id = budget.schedule(
        payee: 'Gecko',
        amount: const Money(-50000),
        categoryId: car,
        nextDue: CivilDate(2026, 11, 20),
      );

      final state = budget.state;
      expect(state.schedule(id)!.payee, 'Gecko');
      // Only the account's Starting Balance is a Transaction.
      expect(state.transactions.map((t) => t.payee), ['Starting Balance']);
      expect(state.balance(budget.checking), const Money(100000));
      expect(state.available(car, _nov), Money.zero);
      expect(state.readyToAssign(_nov), const Money(100000));
    });

    test('EnterSchedule enters it Unreviewed on its due date and moves it on '
        'by one interval', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      final id = budget.schedule(
        payee: 'Landlord',
        amount: const Money(-100000),
        categoryId: rent,
        nextDue: CivilDate(2026, 11, 20),
      );

      final events = budget.run(EnterSchedule(scheduleId: id));

      // The Transaction and the new due date are one group.
      expect(events.map((e) => e.type), [
        EventType.transactionCreated,
        EventType.scheduleFieldsSet,
      ]);
      expect(events.map((e) => e.groupId).toSet(), hasLength(1));

      final transaction = budget.state.transactions.last;
      expect(transaction.date, CivilDate(2026, 11, 20));
      expect(transaction.payee, 'Landlord');
      expect(transaction.amount, const Money(-100000));
      expect(transaction.lines.single.category, rent);
      // A person still chooses its business status in Review (ADR 0003).
      expect(transaction.lines.single.reviewed, isFalse);
      expect(budget.state.reviewQueue, hasLength(1));

      expect(budget.state.available(rent, _nov), const Money(-100000));
      expect(budget.state.schedule(id)!.nextDue, CivilDate(2026, 12, 20));
    });

    test('following rolls a monthly 31st onto the shorter month', () {
      final schedule = Schedule(
        id: 's',
        accountId: 'a',
        payee: 'Rent',
        amount: const Money(-100000),
        category: 'rent',
        every: 1,
        interval: TargetInterval.months,
        nextDue: CivilDate(2027, 1, 31),
      );

      expect(schedule.following, CivilDate(2027, 2, 28));
      expect(
        Schedule(
          id: 's',
          accountId: 'a',
          payee: 'Gym',
          amount: const Money(-2000),
          category: 'gym',
          every: 2,
          interval: TargetInterval.weeks,
          nextDue: CivilDate(2026, 11, 3),
        ).following,
        CivilDate(2026, 11, 17),
      );
    });

    test('a schedule is validated like any other command', () {
      final budget = _Budget();
      final rent = budget.category('Rent');

      // Income goes to Ready to Assign; an outflow needs a Category.
      expect(
        _rejected(
          budget.engine.execute(
            CreateSchedule(
              accountId: budget.checking,
              payee: 'Salary',
              amount: const Money(150000),
              category: rent,
              every: 1,
              interval: TargetInterval.months,
              nextDue: CivilDate(2026, 11, 1),
            ),
          ),
        ),
        Rejection.scheduleCategoryRequired,
      );
      expect(
        _rejected(
          budget.engine.execute(
            CreateSchedule(
              accountId: budget.checking,
              payee: 'Rent',
              amount: const Money(-100000),
              category: readyToAssignCategory,
              every: 1,
              interval: TargetInterval.months,
              nextDue: CivilDate(2026, 11, 1),
            ),
          ),
        ),
        Rejection.scheduleCategoryRequired,
      );
      expect(
        _rejected(
          budget.engine.execute(
            CreateSchedule(
              accountId: budget.checking,
              payee: 'Rent',
              amount: const Money(-100000),
              category: rent,
              every: 0,
              interval: TargetInterval.months,
              nextDue: CivilDate(2026, 11, 1),
            ),
          ),
        ),
        Rejection.intervalMustBePositive,
      );
      expect(
        _rejected(
          budget.engine.execute(
            CreateSchedule(
              accountId: 'nope',
              payee: 'Rent',
              amount: const Money(-100000),
              category: rent,
              every: 1,
              interval: TargetInterval.months,
              nextDue: CivilDate(2026, 11, 1),
            ),
          ),
        ),
        Rejection.unknownAccount,
      );

      final id = budget.schedule(
        payee: 'Rent',
        amount: const Money(-100000),
        categoryId: rent,
        nextDue: CivilDate(2026, 11, 20),
      );
      expect(
        _rejected(budget.engine.execute(EditSchedule(scheduleId: id))),
        Rejection.noChange,
      );
      budget.run(
        EditSchedule(
          scheduleId: id,
          payee: 'Landlord',
          nextDue: CivilDate(2026, 11, 25),
        ),
      );
      expect(budget.state.schedule(id)!.payee, 'Landlord');
      expect(budget.state.schedule(id)!.nextDue, CivilDate(2026, 11, 25));
      expect(budget.state.schedule(id)!.amount, const Money(-100000));

      budget.run(DeleteSchedule(scheduleId: id));
      expect(budget.state.schedule(id), isNull);
      expect(
        _rejected(budget.engine.execute(EnterSchedule(scheduleId: id))),
        Rejection.unknownSchedule,
      );
    });

    test('a schedule reverts like any other entity', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      final created = budget
          .run(
            CreateSchedule(
              accountId: budget.checking,
              payee: 'Landlord',
              amount: const Money(-100000),
              category: rent,
              every: 1,
              interval: TargetInterval.months,
              nextDue: CivilDate(2026, 11, 20),
            ),
          )
          .single;
      final id = created.payload['scheduleId'] as String;

      expect(budget.engine.history.entry(created.groupId)!.canRevert, isTrue);
      budget.run(RevertGroup(groupId: created.groupId));
      expect(budget.state.schedule(id), isNull);

      // Undoing the undo brings it back, payee and all.
      final revert = budget.log.readAll().last.groupId;
      budget.run(RevertGroup(groupId: revert));
      expect(budget.state.schedule(id)!.payee, 'Landlord');
      expect(budget.state.schedule(id)!.nextDue, CivilDate(2026, 11, 20));
    });
  });

  group('Driven-by-schedule Target', () {
    test('sums the implied Repeating targets of the Category', () {
      final budget = _Budget();
      final car = budget.category('Car insurance');
      // Ticket 08's example: $600 every 6 months, due in April.
      budget.schedule(
        payee: 'Gecko',
        amount: const Money(-60000),
        categoryId: car,
        every: 6,
        nextDue: CivilDate(2027, 4, 1),
      );
      budget.schedule(
        payee: 'Roadside',
        amount: const Money(-5000),
        categoryId: car,
        nextDue: CivilDate(2026, 11, 20),
      );

      budget.run(
        SetTarget(categoryId: car, target: const DrivenByScheduleTarget()),
      );

      // 600 ÷ 6 months (Nov–Apr) + 50 due in November.
      expect(budget.state.needed(car, _nov), const Money(15000));

      // In December the car insurance has 5 months left: 600 ÷ 5 + 50.
      expect(budget.state.needed(car, _dec), const Money(17000));
    });

    test('counts the carry once across its schedules', () {
      final budget = _Budget();
      final car = budget.category('Car insurance');
      budget.schedule(
        payee: 'Gecko',
        amount: const Money(-60000),
        categoryId: car,
        every: 6,
        nextDue: CivilDate(2027, 4, 1),
      );
      budget.schedule(
        payee: 'Roadside',
        amount: const Money(-5000),
        categoryId: car,
        nextDue: CivilDate(2026, 11, 20),
      );
      budget.run(
        SetTarget(categoryId: car, target: const DrivenByScheduleTarget()),
      );
      budget.assign(car, _nov, 15000);
      budget.spend(car, CivilDate(2026, 11, 20), 5000);

      // December carries $100, saved toward the insurance: (600 − 100) ÷ 5,
      // plus Roadside's 50.
      expect(budget.state.carry(car, _dec), const Money(10000));
      expect(budget.state.needed(car, _dec), const Money(15000));

      // Paying Roadside in December doesn't reopen it.
      budget.spend(car, CivilDate(2026, 12, 20), 5000);
      expect(budget.state.needed(car, _dec), const Money(15000));
    });

    test('a negative balance adds nothing to what its schedules need', () {
      final budget = _Budget();
      final car = budget.category('Car insurance');
      budget.schedule(
        payee: 'Gecko',
        amount: const Money(-60000),
        categoryId: car,
        every: 6,
        nextDue: CivilDate(2027, 4, 1),
      );
      budget.schedule(
        payee: 'Roadside',
        amount: const Money(-5000),
        categoryId: car,
        nextDue: CivilDate(2026, 11, 20),
      );
      budget.run(
        SetTarget(categoryId: car, target: const DrivenByScheduleTarget()),
      );
      // November is overspent by $50, so December carries nothing.
      budget.assign(car, _nov, 15000);
      budget.spend(car, CivilDate(2026, 11, 20), 20000);
      budget.spend(car, CivilDate(2026, 12, 2), 5000);

      expect(budget.state.available(car, _dec), const Money(-5000));
      // 600 ÷ 5 + 50, as with nothing in the Category.
      expect(budget.state.needed(car, _dec), const Money(17000));
    });

    test('counts every due date of a weekly schedule', () {
      final budget = _Budget();
      final gym = budget.category('Gym');
      budget.schedule(
        payee: 'Gym',
        amount: const Money(-2000),
        categoryId: gym,
        every: 1,
        interval: TargetInterval.weeks,
        nextDue: CivilDate(2026, 11, 3),
      );
      budget.run(
        SetTarget(categoryId: gym, target: const DrivenByScheduleTarget()),
      );

      // Nov 3, 10, 17 and 24.
      expect(budget.state.needed(gym, _nov), const Money(8000));
      expect(budget.state.underfunded(gym, _nov), const Money(8000));
    });

    test('needs nothing without a schedule, and ignores income', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      budget.schedule(
        payee: 'Salary',
        amount: const Money(150000),
        nextDue: CivilDate(2026, 11, 1),
      );
      budget.run(
        SetTarget(categoryId: rent, target: const DrivenByScheduleTarget()),
      );

      expect(budget.state.needed(rent, _nov), Money.zero);
      expect(budget.state.target(rent), isA<DrivenByScheduleTarget>());
      // It survives a replay of its stored form.
      expect(
        Target.fromJson(budget.state.target(rent)!.toJson()),
        isA<DrivenByScheduleTarget>(),
      );
    });

    test('an automation run fills it like any other Target', () {
      final budget = _Budget(income: const Money(41200));
      final rent = budget.category('Rent');
      budget.schedule(
        payee: 'Landlord',
        amount: const Money(-100000),
        categoryId: rent,
        nextDue: CivilDate(2026, 11, 20),
      );
      budget.run(
        SetTarget(categoryId: rent, target: const DrivenByScheduleTarget()),
      );

      expect(budget.state.underfunded(rent, _nov), const Money(100000));
      expect(
        budget.state.suggestionBatch(_nov).single.amount,
        const Money(41200),
      );
      budget.run(AcceptSuggestions(month: _nov, categoryIds: [rent]));
      expect(budget.state.assigned(rent, _nov), const Money(41200));
    });
  });

  group('Forecast', () {
    test('shows 12 months of scheduled spending, income and balances, and '
        'flags the months that cannot be covered', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      final insurance = budget.category('Insurance');
      budget.schedule(
        payee: 'Salary',
        amount: const Money(150000),
        nextDue: CivilDate(2026, 11, 1),
      );
      budget.schedule(
        payee: 'Landlord',
        amount: const Money(-100000),
        categoryId: rent,
        nextDue: CivilDate(2026, 11, 5),
      );
      // A yearly bill of $3,000 in January.
      budget.schedule(
        payee: 'Insurer',
        amount: const Money(-300000),
        categoryId: insurance,
        interval: TargetInterval.years,
        nextDue: CivilDate(2027, 1, 15),
      );

      final forecast = Forecast.of(budget.state, start: _nov);

      expect(forecast.months, hasLength(12));
      expect(forecast.months.first.month, _nov);
      expect(forecast.months.last.month, CalendarMonth(2027, 10));
      expect(forecast.startingBalance, const Money(100000));

      expect(forecast.months.first.inflow, const Money(150000));
      expect(forecast.months.first.outflow, const Money(100000));
      expect(forecast.months.first.outflowByCategory, {rent: Money(100000)});
      expect(forecast.months.first.balance, const Money(150000));

      // Nov, Dec, then January's $3,000 bill.
      expect(forecast.months[1].balance, const Money(200000));
      expect(forecast.months[2].outflow, const Money(400000));
      expect(forecast.months[2].balance, const Money(-50000));
      expect(forecast.months[2].isUnderfunded, isTrue);
      expect(forecast.months[3].balance, Money.zero);

      expect([for (final month in forecast.underfunded) month.month], [_jan]);
    });

    test('counts each due date of a short interval in its month', () {
      final budget = _Budget();
      final gym = budget.category('Gym');
      budget.schedule(
        payee: 'Gym',
        amount: const Money(-2000),
        categoryId: gym,
        every: 1,
        interval: TargetInterval.weeks,
        nextDue: CivilDate(2026, 11, 3),
      );

      final forecast = Forecast.of(budget.state, start: _nov, months: 2);

      expect(forecast.months.first.outflow, const Money(8000));
      expect(forecast.months.first.balance, const Money(92000));
      // December's 5 due dates (1, 8, 15, 22, 29).
      expect(forecast.months[1].outflow, const Money(10000));
    });

    test(
      'a scheduled transaction still counts in nothing but the forecast',
      () {
        final budget = _Budget();
        final rent = budget.category('Rent');
        budget.schedule(
          payee: 'Landlord',
          amount: const Money(-100000),
          categoryId: rent,
          nextDue: CivilDate(2026, 11, 20),
        );

        expect(
          Forecast.of(budget.state, start: _nov).months.first.outflow,
          const Money(100000),
        );
        expect(budget.state.transactions.map((t) => t.payee), [
          'Starting Balance',
        ]);
        expect(budget.state.available(rent, _nov), Money.zero);
      },
    );

    test('an older log with an Event type it does not know still replays', () {
      final budget = _Budget();
      final events = [
        ...budget.log.readAll(),
        Event(
          id: 'unknown',
          budgetId: budget.state.budget!.id,
          deviceId: 'device-b',
          hlc: Hlc(DateTime(2026, 11, 16).millisecondsSinceEpoch, 0, 'b'),
          actor: Actor.userAndroid,
          groupId: 'unknown-group',
          type: 'FromALaterVersion',
          payload: const {},
        ),
      ];

      final state = BudgetState.replay(events);
      expect(state.budget!.name, 'Home');
      expect(state.transactions, hasLength(1));
    });
  });

  group('Recurring charges are only suggested', () {
    /// [count] monthly charges to [payee] from July 10, 2026, and a Rent
    /// Category to file them under.
    _Recurring seed(_Budget budget, {int count = 3, int cents = 1599}) {
      final streaming = budget.category('Streaming');
      for (var i = 0; i < count; i++) {
        budget.spend(
          streaming,
          CivilDate(2026, 7 + i, 10),
          cents,
          payee: 'Netflix',
        );
      }
      return _Recurring(budget, streaming);
    }

    test('3 charges a month apart suggest a monthly schedule', () {
      final budget = _Budget();
      final seeded = seed(budget);

      final suggestion = budget.state.recurringSuggestions().single;
      expect(suggestion.payee, 'Netflix');
      expect(suggestion.amount, const Money(-1599));
      expect(suggestion.category, seeded.category);
      expect(suggestion.accountId, budget.checking);
      expect(suggestion.every, 1);
      expect(suggestion.interval, TargetInterval.months);
      expect(suggestion.nextDue, CivilDate(2026, 10, 10));
      expect(suggestion.count, 3);

      // Only a suggestion: no Scheduled Transaction was written.
      expect(budget.state.schedules, isEmpty);
      expect(budget.state.recurringSuggestions(), hasLength(1));
    });

    test('two charges, an irregular gap or a 10% swing suggest nothing', () {
      final budget = _Budget();
      final two = seed(budget, count: 2);
      expect(budget.state.recurringSuggestions(), isEmpty);

      final irregular = _Budget();
      final dining = irregular.category('Dining out');
      for (final day in [1, 4, 20]) {
        irregular.spend(
          dining,
          CivilDate(2026, 8, day),
          1500,
          payee: 'Corner Bistro',
        );
      }
      expect(irregular.state.recurringSuggestions(), isEmpty);

      final swing = _Budget();
      final shopping = swing.category('Shopping');
      for (final (month, cents) in [(7, 1000), (8, 1200), (9, 1000)]) {
        swing.spend(
          shopping,
          CivilDate(2026, month, 10),
          cents,
          payee: 'Market',
        );
      }
      expect(swing.state.recurringSuggestions(), isEmpty);
      expect(two.budget.state.schedules, isEmpty);
    });

    test('a payee already scheduled is not suggested again', () {
      final budget = _Budget();
      final seeded = seed(budget);
      final suggestion = budget.state.recurringSuggestions().single;
      budget.run(
        CreateSchedule(
          accountId: suggestion.accountId,
          payee: suggestion.payee,
          amount: suggestion.amount,
          category: suggestion.category,
          every: suggestion.every,
          interval: suggestion.interval,
          nextDue: suggestion.nextDue,
        ),
      );
      expect(budget.state.recurringSuggestions(), isEmpty);
      expect(budget.state.schedules.single.payee, 'Netflix');
      expect(seeded.category, isNotEmpty);
    });
  });
}

/// What [seed] built: its budget and the Category the charges went to.
final class _Recurring {
  const _Recurring(this.budget, this.category);

  final _Budget budget;
  final String category;
}
