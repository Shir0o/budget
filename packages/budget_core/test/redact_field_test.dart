import 'dart:convert';

import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// Home, with Sunset Checking holding 500.00, Groceries and Household in
/// Everyday, and one two-line outflow.
final class _Budget {
  _Budget() {
    _accepted(engine.execute(const CreateBudget(name: 'Home')));
    _accepted(
      engine.execute(
        AddAccount(
          name: 'Sunset Checking',
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
    groceries = category('Groceries');
    household = category('Household');
    split = spend(
      'Sunset Storage',
      memo: 'Gate code 7781',
      cents: -5000,
      lines: [
        (cents: -3000, category: groceries, memo: 'Boxes'),
        (cents: -2000, category: household, memo: 'Card 4111 on file'),
      ],
    );
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
  late final String groceries;
  late final String household;

  /// A two-line outflow whose second line memo holds a card number.
  late final String split;

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

  /// An outflow, returning its transaction id.
  String spend(
    String payee, {
    String memo = '',
    int cents = -4820,
    List<({int cents, String category, String memo})>? lines,
  }) {
    final inputs = lines ?? [(cents: cents, category: groceries, memo: '')];
    return _accepted(
          engine.execute(
            CreateTransaction(
              accountId: checking,
              date: CivilDate(2026, 11, 12),
              amount: Money(
                inputs.fold(0, (total, line) => total + line.cents),
              ),
              payee: payee,
              memo: memo,
              lines: [
                for (final line in inputs)
                  LineInput(
                    amount: Money(line.cents),
                    category: line.category,
                    memo: line.memo,
                  ),
              ],
            ),
          ),
        ).single.payload['transactionId']
        as String;
  }

  /// Redacts [targets] and returns the audit Event's group id.
  String redact(List<RedactTarget> targets) =>
      run(RedactField(targets: targets));

  RedactTarget payeeOf(String transactionId) =>
      RedactTarget(EntityRef.transaction(transactionId), 'payee');

  /// Every Event as one string, to prove a value is gone from all of them.
  String get log =>
      [for (final event in engine.events) jsonEncode(event.toJson())]
          .join('\n');
}

void main() {
  group('redacting a field (ticket 11)', () {
    test('replaces a payee in every past Event and in the projection', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro');
      b.run(EditTransaction(transactionId: id, payee: 'Corner Bistro North'));
      expect(b.log, contains('Corner Bistro'));

      b.redact([b.payeeOf(id)]);

      expect(b.state.transaction(id)!.payee, redactedValue);
      final creation = b.engine.events.firstWhere(
        (event) =>
            event.type == EventType.transactionCreated &&
            event.payload['transactionId'] == id,
      );
      expect(creation.payload['payee'], redactedValue);
      final edit = b.engine.events.firstWhere(
        (event) => event.type == EventType.transactionFieldsSet,
      );
      expect((edit.payload['fields'] as Map)['payee'], redactedValue);
      expect(b.log, isNot(contains('Corner Bistro')));
    });

    test('replaces a memo and one line memo, and leaves other lines', () {
      final b = _Budget();
      final secondLine = b.state.transaction(b.split)!.lines.last.id;

      b.redact([
        RedactTarget(EntityRef.transaction(b.split), 'memo'),
        RedactTarget(
          EntityRef.transaction(b.split),
          'lineMemo',
          lineId: secondLine,
        ),
      ]);

      final transaction = b.state.transaction(b.split)!;
      expect(transaction.memo, redactedValue);
      expect(transaction.lines.first.memo, 'Boxes');
      expect(transaction.lines.last.memo, redactedValue);
      expect(b.log, isNot(contains('Gate code 7781')));
      expect(b.log, isNot(contains('Card 4111 on file')));
      expect(b.log, contains('Boxes'));
    });

    test('a later edit that touched the field is rewritten too', () {
      final b = _Budget();
      final id = b.spend('Landlord');
      b.run(EditTransaction(transactionId: id, memo: 'Rent for 41 Sunset'));
      b.run(EditTransaction(transactionId: id, memo: 'Rent, 41 Sunset'));
      b.redact([RedactTarget(EntityRef.transaction(id), 'memo')]);

      expect(b.state.transaction(id)!.memo, redactedValue);
      expect(b.log, isNot(contains('Rent')));
      expect(b.log, isNot(contains('41 Sunset')));
    });

    test('records who, when and which Events, but never the value', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro');
      final group = b.redact([b.payeeOf(id)]);
      final audit = b.engine.events
          .where((event) => event.type == EventType.redacted)
          .single;

      expect(audit.groupId, group);
      expect(audit.actor, Actor.userAndroid);
      expect(audit.payload['by'], Actor.userAndroid.value);
      expect(audit.payload['eventIds'], hasLength(1));
      expect((audit.payload['targets'] as List).single, {
        'entity': 'transaction',
        'id': id,
        'field': 'payee',
      });
      expect(jsonEncode(audit.toJson()), isNot(contains('Corner Bistro')));
      expect(audit.hlc.wallMs, greaterThan(0));
    });

    test('cannot be reverted', () {
      final b = _Budget();
      final id = b.spend('Landlord');
      final edit = b.run(
        EditTransaction(transactionId: id, payee: 'Sunset Apartments'),
      );
      final redaction = b.redact([b.payeeOf(id)]);

      expect(
        b.history.planRevert(redaction)!.rejection,
        Rejection.cannotRevert,
      );
      expect(
        _rejected(b.engine.execute(RevertGroup(groupId: redaction))),
        Rejection.cannotRevert,
      );

      // Reverting the edit that set the value restores the Event's before,
      // which the redaction rewrote too. The value can't come back.
      _accepted(b.engine.execute(RevertGroup(groupId: edit)));
      expect(b.state.transaction(id)!.payee, redactedValue);
      expect(b.log, isNot(contains('Sunset Apartments')));
      expect(b.log, isNot(contains('Landlord')));
    });

    test('history shows what was redacted and how many Events, no value', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro');
      b.redact([b.payeeOf(id)]);

      final entry = b.history.entries().first;
      expect(entry.summary, 'Redacted the payee of $redactedValue −48.20');
      expect(entry.by, Actor.userAndroid);
      expect(entry.changes.map((change) => change.toString()), [
        'Payee: null → [redacted]',
        'Events: null → 1 Event',
      ]);
      expect(entry.changes.first.before, isNull);
      expect(entry.entity, EntityRef.transaction(id));
      expect(entry.entities, contains(EntityRef.transaction(id)));
    });

    test('per-entity history lists the redaction', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro');
      b.redact([b.payeeOf(id)]);

      final entries = b.history.entries(
        filter: HistoryFilter(entity: EntityRef.transaction(id)),
      );
      expect(entries.first.summary, startsWith('Redacted'));
    });

    test('replaces an account name and a Scheduled Transaction payee', () {
      final b = _Budget();
      b.engine.execute(
        CreateSchedule(
          accountId: b.checking,
          payee: 'Gym Card 1111',
          amount: const Money(-1500),
          category: b.groceries,
          every: 1,
          interval: TargetInterval.months,
          nextDue: CivilDate(2026, 12, 1),
          memo: 'Renewal',
        ),
      );
      final schedule = b.state.schedules.single;

      b.redact([
        RedactTarget(EntityRef.account(b.checking), 'name'),
        RedactTarget(EntityRef.schedule(schedule.id), 'payee'),
      ]);

      expect(b.state.account(b.checking)!.name, redactedValue);
      expect(b.state.schedules.single.payee, redactedValue);
      expect(b.log, isNot(contains('Gym Card 1111')));
      expect(b.log, isNot(contains('Sunset Checking')));
    });

    test('offers the fields that hold a value, and none after redaction', () {
      final b = _Budget();
      final candidates = redactCandidates(
        b.state,
        EntityRef.transaction(b.split),
      );
      expect(candidates.map((candidate) => candidate.label), [
        'Payee',
        'Memo',
        'Line memo',
        'Line memo',
      ]);
      expect(candidates.first.value, 'Sunset Storage');

      b.redact([for (final candidate in candidates) candidate.target]);
      expect(
        redactCandidates(b.state, EntityRef.transaction(b.split)),
        isEmpty,
      );
    });

    test('only a person may redact', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro');
      final log = InMemoryEventLog()..append(b.engine.events);
      final bank = BudgetEngine(
        log: log,
        deviceId: 'device-a',
        actor: Actor.bankSync,
        nowMs: () => 1793000000000,
      );

      expect(
        _rejected(bank.execute(RedactField(targets: [b.payeeOf(id)]))),
        Rejection.personRequired,
      );
      expect(bank.state.transaction(id)!.payee, 'Corner Bistro');
    });

    test('a field this version cannot redact, and nothing to do', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro');

      expect(
        _rejected(
          b.engine.execute(
            RedactField(
              targets: [RedactTarget(EntityRef.transaction(id), 'date')],
            ),
          ),
        ),
        Rejection.cannotRedact,
      );
      expect(
        _rejected(b.engine.execute(const RedactField(targets: []))),
        Rejection.cannotRedact,
      );
      expect(
        _rejected(
          b.engine.execute(
            RedactField(
              targets: [RedactTarget(EntityRef.transaction(id), 'lineMemo')],
            ),
          ),
        ),
        Rejection.cannotRedact,
      );

      // A field with nothing in it is not a change.
      expect(
        _rejected(
          b.engine.execute(
            RedactField(
              targets: [RedactTarget(EntityRef.transaction(id), 'memo')],
            ),
          ),
        ),
        Rejection.noChange,
      );
    });

    test('redacting the same field twice changes nothing the second time', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro');
      b.redact([b.payeeOf(id)]);
      expect(
        _rejected(b.engine.execute(RedactField(targets: [b.payeeOf(id)]))),
        Rejection.noChange,
      );
      expect(
        b.engine.events.where((event) => event.type == EventType.redacted),
        hasLength(1),
      );
    });

    test('a Redacted Event from anything but a person is not applied', () {
      final b = _Budget();
      final id = b.spend('Corner Bistro');
      final creation = b.engine.events.last;

      b.engine.merge([
        Event(
          id: 'forged',
          budgetId: b.state.budget!.id,
          deviceId: 'device-b',
          hlc: const Hlc(1793000009999, 0, 'device-b'),
          actor: Actor.bankSync,
          groupId: 'forged',
          type: EventType.redacted,
          payload: {
            'targets': [b.payeeOf(id).toJson()],
            'eventIds': [creation.id],
            'by': Actor.bankSync.value,
          },
        ),
      ]);

      expect(b.state.transaction(id)!.payee, 'Corner Bistro');
    });
  });
}
