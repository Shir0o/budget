import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _nov = CalendarMonth(2026, 11);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// Home, with Checking holding 500.00 and Dining out and Groceries in
/// Everyday.
final class _Budget {
  _Budget() {
    _accepted(engine.execute(const CreateBudget(name: 'Home')));
    _accepted(
      engine.execute(
        AddAccount(
          name: 'Checking',
          type: AccountType.checking,
          startingBalance: const Money(50000),
          asOf: CivilDate(2026, 11, 1),
        ),
      ),
    );
    checking = state.accounts.single.id;
    group =
        _accepted(engine.execute(const CreateCategoryGroup(name: 'Everyday')))
                .single
                .payload['categoryGroupId']
            as String;
    dining = category('Dining out');
    groceries = category('Groceries');
  }

  var _now = 1793000000000;
  late final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'device-a',
    actor: Actor.userAndroid,
    nowMs: () => _now += 1000,
  );
  late final String checking;
  late final String group;
  late final String dining;
  late final String groceries;

  BudgetState get state => engine.state;
  ChangeHistory get history => engine.history;

  String category(String name) =>
      _accepted(engine.execute(CreateCategory(groupId: group, name: name)))
              .single
              .payload['categoryId']
          as String;

  /// Runs [command] and returns its group id.
  String run(Command command) =>
      _accepted(engine.execute(command)).first.groupId;

  String assign(String categoryId, int cents) => run(
    SetAssignment(categoryId: categoryId, month: _nov, amount: Money(cents)),
  );

  /// An outflow, returning its transaction id.
  String spend(String payee, int cents, {String? categoryId}) =>
      _accepted(
            engine.execute(
              CreateTransaction(
                accountId: checking,
                date: CivilDate(2026, 11, 12),
                amount: Money(-cents),
                payee: payee,
                lines: [LineInput(amount: Money(-cents), category: categoryId)],
              ),
            ),
          ).single.payload['transactionId']
          as String;

  CommandResult revert(
    String groupId, {
    Set<FieldRef> skip = const {},
    bool includeDependents = false,
  }) => engine.execute(
    RevertGroup(
      groupId: groupId,
      skipFields: skip,
      includeDependents: includeDependents,
    ),
  );

  HistoryEntry get latest => history.entries().first;
}

void main() {
  group('summaries', () {
    test('a move between Categories, with before and after values', () {
      final b = _Budget();
      b.assign(b.dining, 10000);
      b.run(
        MoveMoney(
          fromCategoryId: b.dining,
          toCategoryId: b.groceries,
          month: _nov,
          amount: const Money(4000),
        ),
      );
      expect(b.latest.summary, 'Moved \$40.00 Dining out → Groceries');
      expect(b.latest.changes.map((c) => c.toString()), [
        'Dining out · Nov 2026: 100.00 → 60.00',
        'Groceries · Nov 2026: 0.00 → 40.00',
      ]);
    });

    test('an Assignment', () {
      final b = _Budget();
      b.assign(b.groceries, 10000);
      expect(b.latest.summary, 'Assigned \$100.00 to Groceries');
    });

    test('a memo set on a transaction', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro', 4820, categoryId: b.dining);
      b.run(EditTransaction(transactionId: id, memo: 'Client lunch'));
      expect(b.latest.summary, 'Set memo of Corner Bistro −48.20');
      expect(
        b.latest.changes.single.toString(),
        'Memo: empty → “Client lunch”',
      );
    });

    test('a category set on a line', () {
      final b = _Budget();
      final id = b.spend('Starbucks', 640);
      b.run(
        EditTransaction(
          transactionId: id,
          lines: [LineInput(amount: const Money(-640), category: b.dining)],
        ),
      );
      expect(b.latest.summary, 'Set category of Starbucks −6.40 to Dining out');
    });

    test('creating things', () {
      final b = _Budget();
      final summaries = [for (final e in b.history.entries()) e.summary];
      expect(summaries.reversed, [
        'Added budget Home',
        'Added account Checking',
        'Added category group Everyday',
        'Added category Dining out',
        'Added category Groceries',
      ]);
    });
  });

  group('revert', () {
    test('appends a negated Assignment delta with actor revert', () {
      final b = _Budget();
      final assigned = b.assign(b.dining, 10000);
      final before = b.engine.events.length;

      final events = _accepted(b.revert(assigned));

      expect(b.engine.events.length, before + 2); // Nothing is erased.
      expect(events.map((e) => e.actor), everyElement(Actor.revert));
      expect(events.map((e) => e.groupId).toSet().single, isNot(assigned));
      expect(events.first.type, EventType.groupReverted);
      expect(events.first.payload, {
        'groupIds': [assigned],
        'by': 'user@android',
      });
      expect(events.last.payload['deltaCents'], -10000);
      expect(b.state.assigned(b.dining, _nov), Money.zero);
      expect(b.history.entry(assigned)!.revertedBy, events.first.groupId);
      expect(b.latest.summary, 'Undid “Assigned \$100.00 to Dining out”');
      expect(b.latest.by, Actor.userAndroid);
    });

    test('reverting a revert is a redo', () {
      final b = _Budget();
      final assigned = b.assign(b.dining, 10000);
      final undo = _accepted(b.revert(assigned)).first.groupId;
      expect(_rejected(b.revert(assigned)), Rejection.alreadyReverted);

      _accepted(b.revert(undo));

      expect(b.state.assigned(b.dining, _nov), const Money(10000));
      expect(b.latest.summary, 'Redid “Assigned \$100.00 to Dining out”');
      expect(b.latest.isRedo, isTrue);
      expect(b.history.entry(assigned)!.revertedBy, isNull);
      expect(b.history.entry(undo)!.revertedBy, b.latest.groupId);

      // The original change can be reverted again.
      _accepted(b.revert(assigned));
      expect(b.state.assigned(b.dining, _nov), Money.zero);
    });

    test('a move restores both Categories', () {
      final b = _Budget();
      b.assign(b.dining, 10000);
      final move = b.run(
        MoveMoney(
          fromCategoryId: b.dining,
          toCategoryId: b.groceries,
          month: _nov,
          amount: const Money(4000),
        ),
      );
      expect(b.history.planRevert(move)!.appliesRightAway, isTrue);
      _accepted(b.revert(move));
      expect(b.state.available(b.dining, _nov), const Money(10000));
      expect(b.state.available(b.groceries, _nov), Money.zero);
    });

    test('transaction fields and lines go back', () {
      final b = _Budget();
      final id = b.spend('Metro Transit', 250, categoryId: b.groceries);
      final edit = b.run(
        EditTransaction(
          transactionId: id,
          payee: 'Metro',
          amount: const Money(-275),
          lines: [LineInput(amount: const Money(-275), category: b.dining)],
        ),
      );
      expect(b.latest.summary, 'Edited Metro Transit −2.50');

      _accepted(b.revert(edit));

      final t = b.state.transaction(id)!;
      expect(t.payee, 'Metro Transit');
      expect(t.amount, const Money(-250));
      expect(t.lines.single.category, b.groceries);
    });

    test('a deleted transaction comes back', () {
      final b = _Budget();
      final id = b.spend('Corner Store', 975, categoryId: b.groceries);
      final delete = b.run(DeleteTransaction(transactionId: id));
      expect(b.latest.summary, 'Deleted Corner Store −9.75');

      _accepted(b.revert(delete));

      expect(b.state.transaction(id)!.amount, const Money(-975));
      expect(b.state.activity(b.groceries, _nov), const Money(-975));
    });

    test('an archived Category is unarchived', () {
      final b = _Budget();
      final archive = b.run(
        ArchiveCategory(categoryId: b.groceries, month: _nov),
      );
      _accepted(b.revert(archive));
      expect(b.state.category(b.groceries)!.archived, isFalse);
      expect(b.latest.changes, isEmpty);
    });

    test('an added account goes with its starting balance', () {
      final b = _Budget();
      final add = b.history.entries().last.groupId;
      final accountGroup = b.history
          .entries()
          .firstWhere((e) => e.summary == 'Added account Checking')
          .groupId;
      expect(b.history.entry(add)!.canRevert, isFalse); // the budget itself
      expect(_rejected(b.revert(add)), Rejection.cannotRevert);

      _accepted(b.revert(accountGroup));

      expect(b.state.accounts, isEmpty);
      expect(b.state.transactions, isEmpty);
      expect(b.state.readyToAssign(_nov), Money.zero);
    });

    test('a card goes with its Card Payment Category, and comes back', () {
      final b = _Budget();
      final card = b.run(
        AddAccount(
          name: 'Visa',
          type: AccountType.creditCard,
          startingBalance: Money.zero,
          asOf: CivilDate(2026, 11, 1),
        ),
      );
      final cardId = b.state.accounts.last.id;
      final undo = _accepted(b.revert(card)).first.groupId;
      expect(b.state.account(cardId), isNull);
      expect(b.state.cardPaymentCategory(cardId), isNull);

      _accepted(b.revert(undo));
      expect(b.state.account(cardId)!.name, 'Visa');
      expect(b.state.cardPaymentCategory(cardId), isNotNull);
    });

    test('an unknown group is rejected', () {
      final b = _Budget();
      expect(_rejected(b.revert('nope')), Rejection.unknownGroup);
      expect(b.history.planRevert('nope'), isNull);
    });
  });

  group('field changed again later', () {
    late _Budget b;
    late String id;
    late String first;
    late FieldConflict conflict;

    setUp(() {
      b = _Budget();
      id = b.spend('Corner Bistro', 4820);
      first = b.run(
        EditTransaction(transactionId: id, payee: 'Bistro', memo: 'Lunch'),
      );
      b.run(EditTransaction(transactionId: id, memo: 'Client lunch'));
      final plan = b.history.planRevert(first)!;
      expect(plan.appliesRightAway, isFalse);
      expect(plan.dependents, isEmpty);
      conflict = plan.fieldConflicts.single;
    });

    test('says who changed it and what Revert anyway restores', () {
      expect(conflict.ref, (entity: EntityRef.transaction(id), field: 'memo'));
      expect(conflict.description, 'Memo of Corner Bistro −48.20');
      expect(conflict.laterChange.summary, 'Set memo of Bistro −48.20');
      expect(conflict.laterChange.actor, Actor.userAndroid);
      expect(conflict.laterBefore, '“Lunch”');
      expect(conflict.laterAfter, '“Client lunch”');
      expect(conflict.restores, 'empty');
    });

    test('Skip this field keeps the later value', () {
      _accepted(b.revert(first, skip: {conflict.ref}));
      final t = b.state.transaction(id)!;
      expect(t.payee, 'Corner Bistro');
      expect(t.memo, 'Client lunch');
    });

    test('Revert anyway restores the old value', () {
      _accepted(b.revert(first));
      final t = b.state.transaction(id)!;
      expect(t.payee, 'Corner Bistro');
      expect(t.memo, '');
    });

    test('a later change that was itself reverted is no conflict', () {
      _accepted(b.revert(b.latest.groupId));
      expect(b.history.planRevert(first)!.appliesRightAway, isTrue);
    });
  });

  group('depends on what the group created', () {
    test('Revert these too undoes the dependents; Cancel leaves all', () {
      final b = _Budget();
      final created = b.history
          .entries()
          .firstWhere((e) => e.summary == 'Added category Groceries')
          .groupId;
      final id = b.spend('Farmers market', 1250, categoryId: b.groceries);
      final spent = b.latest.groupId;
      b.assign(b.dining, 10000);
      final move = b.run(
        MoveMoney(
          fromCategoryId: b.dining,
          toCategoryId: b.groceries,
          month: _nov,
          amount: const Money(4000),
        ),
      );

      final plan = b.history.planRevert(created)!;
      expect(plan.dependents.map((d) => d.groupId), [spent, move]);
      expect(plan.dependents.map((d) => d.summary), [
        'Added Farmers market −12.50',
        'Moved \$40.00 Dining out → Groceries',
      ]);

      // Cancel: without the dependents nothing is written.
      final before = b.engine.events.length;
      expect(_rejected(b.revert(created)), Rejection.hasDependents);
      expect(b.engine.events.length, before);

      final marker = _accepted(b.revert(created, includeDependents: true))
          .first;
      expect(marker.payload['groupIds'], [created, spent, move]);
      expect(b.state.category(b.groceries), isNull);
      expect(b.state.transaction(id), isNull);
      expect(b.state.available(b.dining, _nov), const Money(10000));
      expect(
        b.latest.summary,
        'Undid “Added category Groceries” and 2 later '
        'changes',
      );

      // Redo brings all three back.
      _accepted(b.revert(marker.groupId));
      expect(b.state.category(b.groceries)!.name, 'Groceries');
      expect(b.state.transaction(id)!.lines.single.category, b.groceries);
      expect(b.state.available(b.groceries, _nov), const Money(2750));
    });

    test('a dependent already reverted is left out', () {
      final b = _Budget();
      final created = b.history
          .entries()
          .firstWhere((e) => e.summary == 'Added category Groceries')
          .groupId;
      final assigned = b.assign(b.groceries, 1000);
      _accepted(b.revert(assigned));
      expect(b.history.planRevert(created)!.appliesRightAway, isTrue);
    });
  });

  group('filters', () {
    test('by entity, Actor, type and date', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro', 4820, categoryId: b.dining);
      b.run(EditTransaction(transactionId: id, memo: 'Client lunch'));
      final assigned = b.assign(b.groceries, 1000);
      _accepted(b.revert(assigned));

      List<String> summaries(HistoryFilter filter) => [
        for (final e in b.history.entries(filter: filter)) e.summary,
      ];

      expect(summaries(HistoryFilter(entity: EntityRef.transaction(id))), [
        'Set memo of Corner Bistro −48.20',
        'Added Corner Bistro −48.20',
      ]);
      // An account's history includes its transactions' changes.
      expect(
        summaries(HistoryFilter(entity: EntityRef.account(b.checking))),
        contains('Set memo of Corner Bistro −48.20'),
      );
      expect(summaries(HistoryFilter(entity: EntityRef.category(b.dining))), [
        'Set memo of Corner Bistro −48.20',
        'Added Corner Bistro −48.20',
        'Added category Dining out',
      ]);
      expect(summaries(const HistoryFilter(actors: {ActorKind.revert})), [
        'Undid “Assigned \$10.00 to Groceries”',
      ]);
      expect(
        summaries(const HistoryFilter(actors: {ActorKind.bankSync})),
        isEmpty,
      );
      // A revert counts for the person who asked for it.
      expect(
        summaries(const HistoryFilter(actors: {ActorKind.person})).first,
        'Undid “Assigned \$10.00 to Groceries”',
      );
      expect(
        summaries(const HistoryFilter(types: {EventType.transactionFieldsSet})),
        ['Set memo of Corner Bistro −48.20'],
      );
      final memoTime = b.history.entries()[2].time;
      expect(summaries(HistoryFilter(from: memoTime)), hasLength(3));
      expect(
        summaries(HistoryFilter(until: memoTime)),
        isNot(contains('Set memo of Corner Bistro −48.20')),
      );
    });

    test('device platform comes from the person who used it', () {
      final b = _Budget();
      expect(b.history.devicePlatform('device-a'), 'android');
      expect(b.history.devicePlatform('other'), isNull);
    });
  });
}
