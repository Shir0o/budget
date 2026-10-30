import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _oct = CalendarMonth(2026, 10);
final _oct31 = CivilDate(2026, 10, 31);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// Home on Oct 31: Checking with 2,000.00, Groceries with 300.00 assigned
/// and a Corner Bistro charge. Then [nextDay] moves the clock to Nov 2.
final class _Budget {
  _Budget() {
    _accepted(engine.execute(const CreateBudget(name: 'Home')));
    checking =
        _accepted(
              engine.execute(
                AddAccount(
                  name: 'Checking',
                  type: AccountType.checking,
                  startingBalance: const Money(200000),
                  asOf: CivilDate(2026, 10, 1),
                ),
              ),
            ).first.payload['accountId']
            as String;
    group =
        _accepted(engine.execute(const CreateCategoryGroup(name: 'Everyday')))
                .single
                .payload['categoryGroupId']
            as String;
    groceries = category('Groceries');
    assign(groceries, 30000);
    bistro = spend('Corner Bistro', 4820, groceries);
  }

  var _now = DateTime(2026, 10, 31, 9).millisecondsSinceEpoch;
  late final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'device-a',
    actor: Actor.userAndroid,
    nowMs: () => _now += 1000,
  );
  late final String checking;
  late final String group;
  late final String groceries;
  late final String bistro;

  BudgetState get state => engine.state;

  void nextDay() => _now = DateTime(2026, 11, 2, 9).millisecondsSinceEpoch;

  String category(String name) =>
      _accepted(engine.execute(CreateCategory(groupId: group, name: name)))
              .single
              .payload['categoryId']
          as String;

  void assign(String categoryId, int cents) => _accepted(
    engine.execute(
      SetAssignment(categoryId: categoryId, month: _oct, amount: Money(cents)),
    ),
  );

  String spend(String payee, int cents, String? categoryId) =>
      _accepted(
            engine.execute(
              CreateTransaction(
                accountId: checking,
                date: _oct31,
                amount: Money(-cents),
                payee: payee,
                lines: [LineInput(amount: Money(-cents), category: categoryId)],
              ),
            ),
          ).single.payload['transactionId']
          as String;

  /// Several changes on Nov 2.
  void changeThingsLater() {
    nextDay();
    assign(groceries, 45000);
    final dining = category('Dining out');
    assign(dining, 10000);
    spend('Metro Transit', 275, dining);
    _accepted(
      engine.execute(
        EditTransaction(transactionId: bistro, memo: 'Client lunch'),
      ),
    );
  }
}

/// What a person sees of [state] in October.
Map<String, Object?> _view(BudgetState state) => {
  'readyToAssign': state.readyToAssign(_oct),
  'categories': {
    for (final c in state.categories)
      c.name: (state.assigned(c.id, _oct), state.available(c.id, _oct)),
  },
  'transactions': {
    for (final t in state.transactions) t.id: (t.payee, t.memo, t.amount),
  },
};

void main() {
  test('View as of a date replays only the groups before its end', () {
    final b = _Budget();
    final asOf = _view(b.state);
    b.changeThingsLater();
    final count = b.engine.events.length;

    final then = b.engine.stateAsOf(_oct31);

    expect(_view(then), asOf);
    expect(then.categories.map((c) => c.name), ['Groceries']);
    expect(then.assigned(b.groceries, _oct), const Money(30000));
    expect(b.engine.events, hasLength(count), reason: 'viewing is read-only');
    expect(b.state.categories, hasLength(2));
  });

  test('Restore to a date undoes the full difference as one group', () {
    final b = _Budget();
    final asOf = _view(b.state);
    b.changeThingsLater();

    final events = _accepted(b.engine.execute(RestoreToDate(_oct31)));

    expect(events.map((e) => e.groupId).toSet(), hasLength(1));
    expect(events.first.type, EventType.restoredToDate);
    expect(events.every((e) => e.actor == Actor.revert), isTrue);
    expect(_view(b.state), asOf);
    final entry = b.engine.history.entries().first;
    expect(entry.summary, 'Restored to Oct 31, 2026');
    expect(entry.by, Actor.userAndroid);
    expect(entry.canRevert, isTrue);
  });

  test('a restore can itself be reverted', () {
    final b = _Budget();
    b.changeThingsLater();
    final before = _view(b.state);
    final restore = _accepted(b.engine.execute(RestoreToDate(_oct31)))
        .first
        .groupId;

    _accepted(b.engine.execute(RevertGroup(groupId: restore)));

    expect(_view(b.state), before);
    expect(
      b.engine.history.entries().first.summary,
      'Undid “Restored to Oct 31, 2026”',
    );
  });

  test('a transaction deleted after the date comes back', () {
    final b = _Budget();
    b.nextDay();
    _accepted(b.engine.execute(DeleteTransaction(transactionId: b.bistro)));
    expect(b.state.transaction(b.bistro), isNull);

    _accepted(b.engine.execute(RestoreToDate(_oct31)));

    expect(b.state.transaction(b.bistro)?.payee, 'Corner Bistro');
  });

  test('a later revert of an earlier change is undone too', () {
    final b = _Budget();
    final assignment = b.engine.history.entries()[1].groupId;
    expect(b.engine.history.entry(assignment)!.summary, contains('Assigned'));
    b.nextDay();
    _accepted(b.engine.execute(RevertGroup(groupId: assignment)));
    expect(b.state.assigned(b.groceries, _oct), Money.zero);

    _accepted(b.engine.execute(RestoreToDate(_oct31)));

    expect(b.state.assigned(b.groceries, _oct), const Money(30000));
  });

  test('nothing to restore when nothing changed after the date', () {
    final b = _Budget();
    b.nextDay();

    expect(
      _rejected(b.engine.execute(RestoreToDate(_oct31))),
      Rejection.noChange,
    );
  });

  test('a date before the budget existed cannot be restored to', () {
    final b = _Budget();

    expect(
      _rejected(b.engine.execute(RestoreToDate(CivilDate(2026, 10, 30)))),
      Rejection.cannotRevert,
    );
  });
}
