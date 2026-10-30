import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _oct = CalendarMonth(2026, 10);
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

/// A budget named Home with a checking account holding [income], all of it
/// in Ready to Assign.
final class _Budget {
  _Budget({Money income = const Money(500000)}) {
    _accepted(engine.execute(const CreateBudget(name: 'Home')));
    _accepted(
      engine.execute(
        AddAccount(
          name: 'Checking',
          type: AccountType.checking,
          startingBalance: income,
          asOf: CivilDate(2026, 10, 1),
        ),
      ),
    );
    checking = state.accounts.single.id;
  }

  final log = InMemoryEventLog();
  late BudgetEngine engine = _open();
  late final String checking;

  BudgetState get state => engine.state;

  BudgetEngine _open() =>
      BudgetEngine(log: log, deviceId: 'device-a', actor: Actor.userAndroid);

  String group(String name) {
    final event = _accepted(engine.execute(CreateCategoryGroup(name: name)))
        .single;
    return event.payload['categoryGroupId'] as String;
  }

  String category(String name, {String? groupId}) {
    final event = _accepted(
      engine.execute(
        CreateCategory(groupId: groupId ?? group('Everyday'), name: name),
      ),
    ).single;
    return event.payload['categoryId'] as String;
  }

  void assign(String categoryId, CalendarMonth month, int cents) => _accepted(
    engine.execute(
      SetAssignment(categoryId: categoryId, month: month, amount: Money(cents)),
    ),
  );

  /// Spending from checking. No command records spending until ticket 03,
  /// so this writes the TransactionCreated Event a spend produces.
  void spend(String categoryId, CivilDate date, int cents) {
    log.append([
      Event(
        id: newId(),
        budgetId: state.budget!.id,
        deviceId: 'device-a',
        hlc: Hlc(engine.events.last.hlc.wallMs + 1, 0, 'device-a'),
        actor: Actor.userAndroid,
        groupId: newId(),
        type: EventType.transactionCreated,
        payload: {
          'transactionId': newId(),
          'accountId': checking,
          'date': date.toIso(),
          'payee': 'Shop',
          'amountCents': -cents,
          'lines': [
            {'lineId': newId(), 'amountCents': -cents, 'category': categoryId},
          ],
        },
      ),
    ]);
    engine = _open();
  }
}

void main() {
  group('Categories and groups', () {
    test('are listed in the order they were added', () {
      final budget = _Budget();
      final bills = budget.group(' Bills ');
      budget.group('Everyday');
      final rent = budget.category('Rent', groupId: bills);
      final electric = budget.category('Electric', groupId: bills);

      expect(budget.state.categoryGroups.map((g) => g.name), [
        'Bills',
        'Everyday',
      ]);
      expect(
        budget.state.categories
            .where((c) => c.groupId == bills)
            .map((c) => c.id),
        [rent, electric],
      );
      expect(budget.state.category(rent)?.name, 'Rent');
      expect(budget.state.category(rent)?.archived, isFalse);
    });

    test('need a name and an existing group', () {
      final budget = _Budget();
      final bills = budget.group('Bills');
      final engine = budget.engine;

      expect(
        _rejected(engine.execute(const CreateCategoryGroup(name: ' '))),
        Rejection.nameRequired,
      );
      expect(
        _rejected(engine.execute(CreateCategory(groupId: bills, name: ''))),
        Rejection.nameRequired,
      );
      expect(
        _rejected(
          engine.execute(const CreateCategory(groupId: 'missing', name: 'X')),
        ),
        Rejection.unknownCategoryGroup,
      );
    });
  });

  group('Available', () {
    test('rolls over: \$40 carried + \$300 assigned − \$280 spent = \$60', () {
      // Ticket 07, worked example 1.
      final budget = _Budget();
      final groceries = budget.category('Groceries');
      budget.assign(groceries, _oct, 4000);
      budget.assign(groceries, _nov, 30000);
      budget.spend(groceries, CivilDate(2026, 11, 3), 12748);
      budget.spend(groceries, CivilDate(2026, 11, 9), 8840);
      budget.spend(groceries, CivilDate(2026, 11, 14), 6412);
      final state = budget.state;

      expect(state.available(groceries, _oct), const Money(4000));
      expect(state.carry(groceries, _nov), const Money(4000));
      expect(state.assigned(groceries, _nov), const Money(30000));
      expect(state.activity(groceries, _nov), const Money(-28000));
      expect(state.available(groceries, _nov), const Money(6000));
      // And it carries into December.
      expect(state.carry(groceries, _dec), const Money(6000));
      expect(state.available(groceries, _dec), const Money(6000));
    });

    test('cash overspending comes out of next month\'s Ready to Assign', () {
      // Ticket 07, worked example 2.
      final budget = _Budget();
      final dining = budget.category('Dining out');
      budget.assign(dining, _nov, 2000);
      budget.spend(dining, CivilDate(2026, 11, 20), 5000);
      final state = budget.state;

      expect(state.available(dining, _nov), const Money(-3000));
      expect(state.carry(dining, _dec), Money.zero);
      expect(state.available(dining, _dec), Money.zero);
      expect(state.readyToAssign(_nov), const Money(500000 - 2000));
      expect(state.readyToAssign(_dec), const Money(500000 - 2000 - 3000));
    });

    test('is zero before a Category has any money', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      budget.assign(rent, _dec, 1000);

      expect(budget.state.available(rent, _nov), Money.zero);
      expect(budget.state.carry(rent, _dec), Money.zero);
    });
  });

  group('SetAssignment', () {
    test('records the change as a delta', () {
      final budget = _Budget();
      final groceries = budget.category('Groceries');
      budget.assign(groceries, _nov, 30000);
      final event = _accepted(
        budget.engine.execute(
          SetAssignment(
            categoryId: groceries,
            month: _nov,
            amount: const Money(25000),
          ),
        ),
      ).single;

      expect(event.type, EventType.assignmentChanged);
      expect(event.payload, {
        'category': groceries,
        'month': '2026-11',
        'deltaCents': -5000,
      });
      expect(budget.state.assigned(groceries, _nov), const Money(25000));
      expect(budget.state.readyToAssign(_nov), const Money(500000 - 25000));
    });

    test('to a future month reduces Ready to Assign immediately', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      budget.assign(rent, _dec, 165000);

      expect(budget.state.readyToAssign(_nov), const Money(500000 - 165000));
      expect(budget.state.assigned(rent, _nov), Money.zero);
      expect(budget.state.available(rent, _dec), const Money(165000));
    });

    test('shows over-assigned as a negative Ready to Assign', () {
      final budget = _Budget(income: const Money(10000));
      final rent = budget.category('Rent');
      budget.assign(rent, _nov, 15000);

      expect(budget.state.readyToAssign(_nov), const Money(-5000));
    });

    test('rejects an unchanged amount and an unknown Category', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      final engine = budget.engine;

      expect(
        _rejected(
          engine.execute(
            SetAssignment(categoryId: rent, month: _nov, amount: Money.zero),
          ),
        ),
        Rejection.noChange,
      );
      expect(
        _rejected(
          engine.execute(
            SetAssignment(
              categoryId: 'missing',
              month: _nov,
              amount: const Money(1),
            ),
          ),
        ),
        Rejection.unknownCategory,
      );
    });

    test('Assignments from two devices add up', () {
      // Ticket 06, merge rule 2: phone +$50 and Mac +$30 give +$80.
      final budget = _Budget();
      final groceries = budget.category('Groceries');
      final base = budget.engine.events.last.hlc.wallMs;
      Event delta(String device, int cents) => Event(
        id: newId(),
        budgetId: budget.state.budget!.id,
        deviceId: device,
        hlc: Hlc(base + 1, 0, device),
        actor: Actor.userAndroid,
        groupId: newId(),
        type: EventType.assignmentChanged,
        payload: {
          'category': groceries,
          'month': '2026-11',
          'deltaCents': cents,
        },
      );

      final merged = BudgetState.replay([
        ...budget.engine.events,
        delta('phone', 5000),
        delta('mac', 3000),
      ]);
      expect(merged.assigned(groceries, _nov), const Money(8000));
    });
  });

  group('MoveMoney', () {
    test('between Categories leaves Ready to Assign unchanged', () {
      final budget = _Budget();
      final groceries = budget.category('Groceries');
      final dining = budget.category('Dining out');
      budget.assign(groceries, _nov, 6000);
      budget.assign(dining, _nov, 2000);
      budget.spend(dining, CivilDate(2026, 11, 20), 5000);
      final before = budget.state.readyToAssign(_nov);

      final events = _accepted(
        budget.engine.execute(
          MoveMoney(
            fromCategoryId: groceries,
            toCategoryId: dining,
            month: _nov,
            amount: const Money(3000),
          ),
        ),
      );

      expect(events, hasLength(2));
      expect(events.map((e) => e.groupId).toSet(), hasLength(1));
      final state = budget.state;
      expect(state.available(groceries, _nov), const Money(3000));
      expect(state.available(dining, _nov), Money.zero);
      expect(state.readyToAssign(_nov), before);
      // The overspending was covered, so December loses nothing.
      expect(state.readyToAssign(_dec), before);
    });

    test('to Ready to Assign gives the money back', () {
      final budget = _Budget();
      final groceries = budget.category('Groceries');
      budget.assign(groceries, _nov, 6000);

      _accepted(
        budget.engine.execute(
          MoveMoney(
            fromCategoryId: groceries,
            toCategoryId: readyToAssignCategory,
            month: _nov,
            amount: const Money(6000),
          ),
        ),
      );

      expect(budget.state.available(groceries, _nov), Money.zero);
      expect(budget.state.readyToAssign(_nov), const Money(500000));
    });

    test('rejects zero, the same Category and unknown Categories', () {
      final budget = _Budget();
      final groceries = budget.category('Groceries');
      final dining = budget.category('Dining out');
      final before = budget.engine.events.length;
      Rejection move(String from, String to, int cents) => _rejected(
        budget.engine.execute(
          MoveMoney(
            fromCategoryId: from,
            toCategoryId: to,
            month: _nov,
            amount: Money(cents),
          ),
        ),
      );

      expect(move(groceries, dining, 0), Rejection.amountMustBePositive);
      expect(move(groceries, dining, -100), Rejection.amountMustBePositive);
      expect(move(groceries, groceries, 100), Rejection.sameCategory);
      expect(move('missing', dining, 100), Rejection.unknownCategory);
      expect(move(groceries, 'missing', 100), Rejection.unknownCategory);
      expect(budget.engine.events, hasLength(before));
    });
  });

  group('ArchiveCategory', () {
    Rejection? archive(_Budget budget, String categoryId, CalendarMonth m) {
      final result = budget.engine.execute(
        ArchiveCategory(categoryId: categoryId, month: m),
      );
      return result is Rejected ? result.reason : null;
    }

    test('is blocked while Available is not zero', () {
      // Ticket 07, worked example 8.
      final budget = _Budget();
      final groceries = budget.category('Groceries');
      final dining = budget.category('Dining out');
      budget.assign(groceries, _nov, 6000);
      budget.assign(dining, _nov, 2000);
      budget.spend(dining, CivilDate(2026, 11, 20), 5000);

      expect(archive(budget, groceries, _nov), Rejection.categoryHasBalance);
      expect(archive(budget, dining, _nov), Rejection.categoryHasBalance);
      expect(budget.state.category(groceries)?.archived, isFalse);
    });

    test('is blocked by money assigned to a later month', () {
      final budget = _Budget();
      final rent = budget.category('Rent');
      budget.assign(rent, _dec, 1000);

      expect(budget.state.available(rent, _nov), Money.zero);
      expect(archive(budget, rent, _nov), Rejection.categoryHasBalance);
    });

    test('works once the Available is moved away', () {
      final budget = _Budget();
      final groceries = budget.category('Groceries');
      budget.assign(groceries, _nov, 6000);
      _accepted(
        budget.engine.execute(
          MoveMoney(
            fromCategoryId: groceries,
            toCategoryId: readyToAssignCategory,
            month: _nov,
            amount: const Money(6000),
          ),
        ),
      );

      expect(archive(budget, groceries, _nov), isNull);
      expect(budget.state.category(groceries)?.archived, isTrue);
      expect(archive(budget, groceries, _nov), Rejection.categoryArchived);
      expect(
        _rejected(
          budget.engine.execute(
            SetAssignment(
              categoryId: groceries,
              month: _nov,
              amount: const Money(100),
            ),
          ),
        ),
        Rejection.categoryArchived,
      );
    });

    test('is allowed after last month\'s overspending was taken from '
        'Ready to Assign', () {
      final budget = _Budget();
      final dining = budget.category('Dining out');
      budget.spend(dining, CivilDate(2026, 11, 20), 5000);

      expect(archive(budget, dining, _nov), Rejection.categoryHasBalance);
      expect(archive(budget, dining, _dec), isNull);
    });
  });
}
