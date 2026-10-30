import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _oct = CalendarMonth(2026, 10);
final _nov = CalendarMonth(2026, 11);
final _dec = CalendarMonth(2026, 12);
final _jan = CalendarMonth(2027, 1);
final _feb = CalendarMonth(2027, 2);
final _mar = CalendarMonth(2027, 3);
final _apr = CalendarMonth(2027, 4);
final _may = CalendarMonth(2027, 5);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// A budget named Home whose checking account starts with [income] in
/// Ready to Assign on Nov 1, 2026, and a Bills group. The clock reads
/// Nov 15, 2026.
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

  String category(String name, {Target? target, AutomationMode? mode}) {
    final id =
        run(CreateCategory(groupId: bills, name: name))
                .single
                .payload['categoryId']
            as String;
    if (target != null) run(SetTarget(categoryId: id, target: target));
    if (mode != null) run(SetAutomationMode(categoryId: id, mode: mode));
    return id;
  }

  void assign(String categoryId, CalendarMonth month, int cents) => run(
    SetAssignment(categoryId: categoryId, month: month, amount: Money(cents)),
  );

  void spend(String categoryId, CivilDate date, int cents) => run(
    CreateTransaction(
      accountId: checking,
      date: date,
      amount: Money(-cents),
      lines: [LineInput(amount: Money(-cents), category: categoryId)],
    ),
  );
}

RepeatingTarget _monthly(int cents, CivilDate due, {int every = 1}) =>
    RepeatingTarget(
      amount: Money(cents),
      every: every,
      interval: TargetInterval.months,
      nextDue: due,
    );

void main() {
  group('Repeating Target', () {
    // Ticket 08's example.
    final carInsurance = _monthly(60000, CivilDate(2027, 4, 1), every: 6);

    test('car insurance: \$600 every 6 months due in April needs \$100 in '
        'November', () {
      final budget = _Budget();
      final car = budget.category('Car insurance', target: carInsurance);

      expect(
        budget.state.availableBeforeAssigning(car, _nov, carInsurance),
        Money.zero,
      );
      expect(budget.state.needed(car, _nov), const Money(10000));
    });

    test('car insurance holding \$250 in February needs \$116.67, and April '
        'rounds so the total lands at \$600', () {
      final budget = _Budget();
      final car = budget.category('Car insurance', target: carInsurance);
      budget.assign(car, _jan, 25000);

      expect(budget.state.needed(car, _feb), const Money(11667));

      for (final month in [_feb, _mar, _apr]) {
        budget.assign(car, month, budget.state.needed(car, month).cents);
      }
      expect(budget.state.needed(car, _mar), const Money(11667));
      expect(budget.state.needed(car, _apr), const Money(11666));
      expect(budget.state.available(car, _apr), const Money(60000));
    });

    test('moves on to the next due date once one has passed', () {
      final budget = _Budget();
      final car = budget.category('Car insurance', target: carInsurance);

      expect(carInsurance.dueFor(_may), CivilDate(2027, 10, 1));
      expect(budget.state.needed(car, _may), const Money(10000));
    });

    test('floors at 0 when the Category already holds the amount', () {
      final budget = _Budget();
      final car = budget.category('Car insurance', target: carInsurance);
      budget.assign(car, _oct, 70000);

      expect(budget.state.needed(car, _nov), Money.zero);
    });

    test('ignores spending this month, so a paid bill stays funded', () {
      final budget = _Budget();
      final monthly = _monthly(50000, CivilDate(2026, 11, 30));
      final groceries = budget.category('Groceries', target: monthly);
      budget.assign(groceries, _nov, 50000);
      budget.spend(groceries, CivilDate(2026, 11, 3), 30000);

      // Carry alone, as YNAB's Needed for spending does.
      expect(
        budget.state.availableBeforeAssigning(groceries, _nov, monthly),
        Money.zero,
      );
      expect(budget.state.needed(groceries, _nov), const Money(50000));
      expect(budget.state.underfunded(groceries, _nov), Money.zero);
    });

    test('weekly needs the amount times the due dates in the month', () {
      final budget = _Budget();
      final lunch = budget.category(
        'Lunch',
        target: RepeatingTarget(
          amount: const Money(2500),
          every: 1,
          interval: TargetInterval.weeks,
          nextDue: CivilDate(2026, 11, 2),
        ),
      );

      // Nov 2, 9, 16, 23 and 30.
      expect(budget.state.needed(lunch, _nov), const Money(12500));
      // Dec 7, 14, 21 and 28.
      expect(budget.state.needed(lunch, _dec), const Money(10000));
      expect(budget.state.needed(lunch, _oct), Money.zero);
    });

    test('every 3 days counts each due date in the month', () {
      final target = RepeatingTarget(
        amount: const Money(100),
        every: 3,
        interval: TargetInterval.days,
        nextDue: CivilDate(2026, 10, 30),
      );
      // Nov 2, 5, …, 29.
      expect(target.dueDatesIn(_nov), 10);
      expect(target.needed(_nov, Money.zero), const Money(1000));
    });
  });

  group('One-time by date Target', () {
    final trip = ByDateTarget(
      amount: const Money(120000),
      date: CivilDate(2027, 2, 15),
    );

    test('divides what is left over the months left, including this one', () {
      final budget = _Budget();
      final travel = budget.category('Travel', target: trip);
      expect(budget.state.needed(travel, _nov), const Money(30000));

      budget.assign(travel, _nov, 50000);
      // (1,200 − 500) ÷ 3, rounded up to the cent.
      expect(budget.state.needed(travel, _dec), const Money(23334));
    });

    test('is complete after the date and does not refill', () {
      final budget = _Budget();
      final travel = budget.category('Travel', target: trip);
      budget.assign(travel, _nov, 120000);
      budget.spend(travel, CivilDate(2027, 3, 2), 30000);

      expect(trip.isCompleteIn(_mar), isTrue);
      expect(budget.state.needed(travel, _mar), Money.zero);
    });

    test('counts spending this month, since it is a balance to reach', () {
      final budget = _Budget();
      final travel = budget.category('Travel', target: trip);
      budget.spend(travel, CivilDate(2026, 11, 3), 10000);

      expect(
        budget.state.availableBeforeAssigning(travel, _nov, trip),
        const Money(-10000),
      );
      // (1,200 + 100) ÷ 4.
      expect(budget.state.needed(travel, _nov), const Money(32500));
    });
  });

  group('Keep at least Target', () {
    test('tops up to the floor from the carry, ignoring spending this '
        'month: max(0, A − Carry)', () {
      final budget = _Budget();
      const floor = KeepAtLeastTarget(amount: Money(10000));
      final transport = budget.category('Transport', target: floor);
      budget.assign(transport, _oct, 2240);
      budget.spend(transport, CivilDate(2026, 11, 4), 1000);

      expect(
        budget.state.availableBeforeAssigning(transport, _nov, floor),
        const Money(2240),
      );
      expect(budget.state.needed(transport, _nov), const Money(7760));

      budget.assign(transport, _oct, 20000);
      expect(budget.state.needed(transport, _nov), Money.zero);
    });
  });

  group('Underfunded', () {
    test('is max(0, Needed − Assigned)', () {
      final budget = _Budget();
      final rent = budget.category(
        'Rent',
        target: _monthly(160000, CivilDate(2026, 12, 1), every: 1),
      );
      // Due Dec 1: Nov and Dec share it.
      expect(budget.state.needed(rent, _nov), const Money(80000));
      budget.assign(rent, _nov, 30000);
      expect(budget.state.underfunded(rent, _nov), const Money(50000));
      budget.assign(rent, _nov, 90000);
      expect(budget.state.underfunded(rent, _nov), Money.zero);
    });

    test('is zero without a Target', () {
      final budget = _Budget();
      final misc = budget.category('Misc');
      expect(budget.state.target(misc), isNull);
      expect(budget.state.underfunded(misc, _nov), Money.zero);
    });
  });

  group('Targets', () {
    test('are set and cleared with TargetSet and TargetCleared', () {
      final budget = _Budget();
      final misc = budget.category('Misc');
      const floor = KeepAtLeastTarget(amount: Money(5000));

      final set = budget.run(SetTarget(categoryId: misc, target: floor));
      expect(set.single.type, EventType.targetSet);
      expect(set.single.payload, {
        'categoryId': misc,
        'target': {'kind': 'keepAtLeast', 'amountCents': 5000},
      });
      expect(budget.state.target(misc), isA<KeepAtLeastTarget>());

      final cleared = budget.run(ClearTarget(categoryId: misc));
      expect(cleared.single.type, EventType.targetCleared);
      expect(budget.state.target(misc), isNull);
    });

    test('round-trip through their stored form', () {
      final targets = <Target>[
        _monthly(60000, CivilDate(2027, 4, 1), every: 6),
        ByDateTarget(amount: const Money(1), date: CivilDate(2027, 1, 31)),
        const KeepAtLeastTarget(amount: Money(2)),
      ];
      for (final target in targets) {
        expect(Target.fromJson(target.toJson()).toJson(), target.toJson());
      }
    });

    test('need a positive amount and interval, and an active Category', () {
      final budget = _Budget();
      final misc = budget.category('Misc');
      final engine = budget.engine;

      expect(
        _rejected(
          engine.execute(
            SetTarget(
              categoryId: misc,
              target: const KeepAtLeastTarget(amount: Money.zero),
            ),
          ),
        ),
        Rejection.targetAmountMustBePositive,
      );
      expect(
        _rejected(
          engine.execute(
            SetTarget(
              categoryId: misc,
              target: _monthly(100, CivilDate(2027, 1, 1), every: 0),
            ),
          ),
        ),
        Rejection.intervalMustBePositive,
      );
      expect(
        _rejected(
          engine.execute(
            const SetTarget(
              categoryId: 'missing',
              target: KeepAtLeastTarget(amount: Money(1)),
            ),
          ),
        ),
        Rejection.unknownCategory,
      );
      expect(
        _rejected(engine.execute(ClearTarget(categoryId: misc))),
        Rejection.noChange,
      );
    });
  });

  group('Automation Mode', () {
    test('defaults to suggest, and to off for Card Payment Categories', () {
      final budget = _Budget();
      final misc = budget.category('Misc');
      budget.run(
        AddAccount(
          name: 'Visa',
          type: AccountType.creditCard,
          startingBalance: Money.zero,
          asOf: CivilDate(2026, 11, 1),
        ),
      );
      final visa = budget.state.accounts.last.id;
      final payment = budget.state.cardPaymentCategory(visa)!.id;

      expect(budget.state.automationMode(misc), AutomationMode.suggest);
      expect(budget.state.automationMode(payment), AutomationMode.off);
    });

    test('is set with AutomationModeSet', () {
      final budget = _Budget();
      final misc = budget.category('Misc');
      final events = budget.run(
        SetAutomationMode(categoryId: misc, mode: AutomationMode.auto),
      );
      expect(events.single.type, EventType.automationModeSet);
      expect(events.single.payload, {'categoryId': misc, 'mode': 'auto'});
      expect(budget.state.automationMode(misc), AutomationMode.auto);
      expect(
        _rejected(
          budget.engine.execute(
            SetAutomationMode(categoryId: misc, mode: AutomationMode.auto),
          ),
        ),
        Rejection.noChange,
      );
    });
  });

  group('Priority', () {
    test('is the order set, then the rest in their order on screen', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      final electric = budget.category('Electric');
      final phone = budget.category('Phone');
      final everyday =
          budget
                  .run(const CreateCategoryGroup(name: 'Everyday'))
                  .single
                  .payload['categoryGroupId']
              as String;
      final groceries =
          budget
                  .run(CreateCategory(groupId: everyday, name: 'Groceries'))
                  .single
                  .payload['categoryId']
              as String;
      ids() => [for (final c in budget.state.priority) c.id];

      expect(ids(), [rent, electric, phone, groceries]);

      final events = budget.run(SetPriority(categoryIds: [groceries, phone]));
      expect(events.single.type, EventType.prioritySet);
      expect(ids(), [groceries, phone, rent, electric]);
    });

    test('rejects unknown and repeated Categories', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      expect(
        _rejected(
          budget.engine.execute(const SetPriority(categoryIds: ['missing'])),
        ),
        Rejection.unknownCategory,
      );
      expect(
        _rejected(
          budget.engine.execute(SetPriority(categoryIds: [rent, rent])),
        ),
        Rejection.duplicateCategory,
      );
    });
  });

  group('Priority fill', () {
    test('gives each Category min(Underfunded, remaining) in priority order '
        'and stops at 0', () {
      // Ready to Assign 412.00, as on the Assign canvas.
      final budget = _Budget(income: const Money(41200));
      final rent = budget.category(
        'Rent',
        target: _monthly(160000, CivilDate(2026, 11, 30)),
      );
      final electric = budget.category(
        'Electric',
        target: _monthly(9000, CivilDate(2026, 11, 20)),
      );
      final phone = budget.category(
        'Phone',
        target: _monthly(4500, CivilDate(2026, 11, 20)),
      );
      final transport = budget.category(
        'Transport',
        target: const KeepAtLeastTarget(amount: Money(10000)),
      );
      budget.run(SetPriority(categoryIds: [electric, phone, transport, rent]));

      expect(budget.state.suggestionBatch(_nov), [
        Suggestion(categoryId: electric, amount: const Money(9000)),
        Suggestion(categoryId: phone, amount: const Money(4500)),
        Suggestion(categoryId: transport, amount: const Money(10000)),
        Suggestion(categoryId: rent, amount: const Money(17700)),
      ]);
    });

    test('never removes money, skips off, and never goes negative', () {
      final budget = _Budget(income: const Money(10000));
      final over = budget.category(
        'Overfunded',
        target: const KeepAtLeastTarget(amount: Money(1000)),
      );
      budget.assign(over, _nov, 5000);
      budget.category(
        'Off',
        target: const KeepAtLeastTarget(amount: Money(1000)),
        mode: AutomationMode.off,
      );
      final rest = budget.category(
        'Rest',
        target: const KeepAtLeastTarget(amount: Money(9000)),
      );

      // 100.00 − 50.00 assigned leaves 50.00.
      expect(budget.state.suggestionBatch(_nov), [
        Suggestion(categoryId: rest, amount: const Money(5000)),
      ]);

      budget.assign(over, _nov, 15000);
      expect(budget.state.readyToAssign(_nov).isNegative, isTrue);
      expect(budget.state.suggestionBatch(_nov), isEmpty);
    });

    test('fills only the month asked for', () {
      final budget = _Budget(income: const Money(50000));
      final electric = budget.category(
        'Electric',
        target: _monthly(9000, CivilDate(2026, 11, 20)),
        mode: AutomationMode.auto,
      );
      budget.run(RunAutomation(month: _nov));

      expect(budget.state.assigned(electric, _nov), const Money(9000));
      expect(budget.state.assigned(electric, _dec), Money.zero);
      expect(budget.state.assignmentMonths, [_nov]);
    });
  });

  group('Suggestion Batch', () {
    late _Budget budget;
    late String electric;
    late String phone;

    setUp(() {
      budget = _Budget(income: const Money(20000));
      electric = budget.category(
        'Electric',
        target: _monthly(9000, CivilDate(2026, 11, 20)),
      );
      phone = budget.category(
        'Phone',
        target: _monthly(4500, CivilDate(2026, 11, 20)),
      );
    });

    test('accepted all at once is one group as the person, with the note', () {
      final events = budget.run(
        AcceptSuggestions(month: _nov, categoryIds: [electric, phone]),
      );

      expect(events, hasLength(2));
      expect(events.map((e) => e.groupId).toSet(), hasLength(1));
      expect(events.map((e) => e.actor).toSet(), {Actor.userAndroid});
      expect(events.map((e) => e.payload['note']).toSet(), {
        'accepted automation suggestion',
      });
      expect(budget.state.assigned(electric, _nov), const Money(9000));
      expect(budget.state.assigned(phone, _nov), const Money(4500));
      expect(budget.state.suggestionBatch(_nov), isEmpty);
    });

    test('accepted line by line keeps the other lines', () {
      budget.run(AcceptSuggestions(month: _nov, categoryIds: [phone]));

      expect(budget.state.assigned(phone, _nov), const Money(4500));
      expect(budget.state.suggestionBatch(_nov), [
        Suggestion(categoryId: electric, amount: const Money(9000)),
      ]);
      expect(
        _rejected(
          budget.engine.execute(
            AcceptSuggestions(month: _nov, categoryIds: [phone]),
          ),
        ),
        Rejection.notSuggested,
      );
    });
  });

  group('Automation run', () {
    test('assigns auto Categories as one group with actor automation and '
        'leaves suggest lines', () {
      final budget = _Budget(income: const Money(20000));
      final electric = budget.category(
        'Electric',
        target: _monthly(9000, CivilDate(2026, 11, 20)),
      );
      final phone = budget.category(
        'Phone',
        target: _monthly(4500, CivilDate(2026, 11, 20)),
        mode: AutomationMode.auto,
      );
      final internet = budget.category(
        'Internet',
        target: _monthly(6000, CivilDate(2026, 11, 20)),
        mode: AutomationMode.auto,
      );
      final batch = budget.state.suggestionBatch(_nov);

      final events = budget.run(RunAutomation(month: _nov));

      expect(events, hasLength(2));
      expect(events.map((e) => e.groupId).toSet(), hasLength(1));
      expect(events.map((e) => e.actor).toSet(), {Actor.automation});
      expect(budget.state.assigned(phone, _nov), const Money(4500));
      expect(budget.state.assigned(internet, _nov), const Money(6000));
      expect(budget.state.assigned(electric, _nov), Money.zero);
      expect(budget.state.suggestionBatch(_nov), batch);
      expect(
        _rejected(budget.engine.execute(RunAutomation(month: _nov))),
        Rejection.noChange,
      );
    });

    test('starts when a person reviews an income line', () {
      final budget = _Budget(income: Money.zero);
      final phone = budget.category(
        'Phone',
        target: _monthly(4500, CivilDate(2026, 11, 20)),
        mode: AutomationMode.auto,
      );

      budget.run(
        CreateTransaction(
          accountId: budget.checking,
          date: CivilDate(2026, 11, 14),
          amount: const Money(300000),
          payee: 'Payroll',
          lines: [
            const LineInput(
              amount: Money(300000),
              category: readyToAssignCategory,
              business: Personal(),
            ),
          ],
        ),
      );

      final last = budget.engine.events.last;
      expect(last.actor, Actor.automation);
      expect(last.payload['month'], '2026-11');
      expect(budget.state.assigned(phone, _nov), const Money(4500));
    });

    test('does not start for income that is not reviewed', () {
      final budget = _Budget(income: Money.zero);
      budget.category(
        'Phone',
        target: _monthly(4500, CivilDate(2026, 11, 20)),
        mode: AutomationMode.auto,
      );

      budget.run(
        CreateTransaction(
          accountId: budget.checking,
          date: CivilDate(2026, 11, 14),
          amount: const Money(300000),
          lines: [
            const LineInput(
              amount: Money(300000),
              category: readyToAssignCategory,
            ),
          ],
        ),
      );

      expect(budget.engine.events.last.type, EventType.transactionCreated);
    });
  });

  group('Change History', () {
    test('reverts an automation run as a unit', () {
      final budget = _Budget(income: const Money(20000));
      final phone = budget.category(
        'Phone',
        target: _monthly(4500, CivilDate(2026, 11, 20)),
        mode: AutomationMode.auto,
      );
      final internet = budget.category(
        'Internet',
        target: _monthly(6000, CivilDate(2026, 11, 20)),
        mode: AutomationMode.auto,
      );
      final run = budget.run(RunAutomation(month: _nov));

      budget.run(RevertGroup(groupId: run.first.groupId));

      expect(budget.state.assigned(phone, _nov), Money.zero);
      expect(budget.state.assigned(internet, _nov), Money.zero);
    });

    test('reverts Targets, Automation Modes and the priority order', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      final phone = budget.category('Phone');
      String last() => budget.engine.events.last.groupId;

      budget.run(
        SetTarget(
          categoryId: phone,
          target: const KeepAtLeastTarget(amount: Money(4500)),
        ),
      );
      budget.run(RevertGroup(groupId: last()));
      expect(budget.state.target(phone), isNull);

      budget.run(
        SetAutomationMode(categoryId: phone, mode: AutomationMode.auto),
      );
      budget.run(RevertGroup(groupId: last()));
      expect(budget.state.automationMode(phone), AutomationMode.suggest);

      budget.run(SetPriority(categoryIds: [phone, rent]));
      budget.run(RevertGroup(groupId: last()));
      expect([for (final c in budget.state.priority) c.id], [rent, phone]);
    });
  });
}
