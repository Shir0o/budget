import 'dart:convert';

import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _nov1 = CivilDate(2026, 11, 1);

BudgetEngine _engine({EventLog? log, int Function()? nowMs}) => BudgetEngine(
  log: log ?? InMemoryEventLog(),
  deviceId: 'device-a',
  actor: Actor.userAndroid,
  nowMs: nowMs,
);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// A budget named Home with one checking account.
String _withChecking(BudgetEngine engine, {Money balance = Money.zero}) {
  _accepted(engine.execute(const CreateBudget(name: 'Home')));
  _accepted(
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: balance,
        asOf: _nov1,
      ),
    ),
  );
  return engine.state.accounts.single.id;
}

void main() {
  group('CreateBudget', () {
    test('creates the budget with Ready to Assign at zero', () {
      final engine = _engine();
      final events = _accepted(
        engine.execute(const CreateBudget(name: ' Home ')),
      );

      expect(events.single.type, EventType.budgetCreated);
      expect(engine.state.budget?.name, 'Home');
      expect(engine.state.budget?.id, events.single.budgetId);
      expect(engine.state.readyToAssign, Money.zero);
    });

    test('rejects a blank name and a second budget', () {
      final engine = _engine();
      expect(
        _rejected(engine.execute(const CreateBudget(name: '  '))),
        Rejection.nameRequired,
      );
      engine.execute(const CreateBudget(name: 'Home'));
      expect(
        _rejected(engine.execute(const CreateBudget(name: 'Other'))),
        Rejection.budgetAlreadyExists,
      );
    });
  });

  group('AddAccount', () {
    test('records the starting balance as income to Ready to Assign', () {
      final engine = _engine();
      engine.execute(const CreateBudget(name: 'Home'));
      final events = _accepted(
        engine.execute(
          AddAccount(
            name: 'Checking',
            type: AccountType.checking,
            startingBalance: const Money(421055),
            asOf: _nov1,
          ),
        ),
      );

      expect(events.map((e) => e.type), [
        EventType.accountCreated,
        EventType.transactionCreated,
      ]);
      expect(events.map((e) => e.groupId).toSet(), hasLength(1));

      final account = engine.state.accounts.single;
      expect(account.name, 'Checking');
      expect(account.type, AccountType.checking);

      final starting = engine.state.transactions.single;
      expect(starting.accountId, account.id);
      expect(starting.payee, 'Starting Balance');
      expect(starting.date, _nov1);
      expect(starting.amount, const Money(421055));
      expect(engine.state.readyToAssign, const Money(421055));
    });

    test('an overdrawn starting balance lowers Ready to Assign', () {
      final engine = _engine();
      _withChecking(engine, balance: const Money(-2500));
      expect(engine.state.readyToAssign, const Money(-2500));
    });

    test('is rejected before a budget exists or without a name', () {
      final engine = _engine();
      final command = AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: Money.zero,
        asOf: _nov1,
      );
      expect(_rejected(engine.execute(command)), Rejection.noBudget);

      engine.execute(const CreateBudget(name: 'Home'));
      expect(
        _rejected(
          engine.execute(
            AddAccount(
              name: ' ',
              type: AccountType.cash,
              startingBalance: Money.zero,
              asOf: _nov1,
            ),
          ),
        ),
        Rejection.nameRequired,
      );
      expect(engine.state.accounts, isEmpty);
    });
  });

  group('RecordIncome', () {
    test('a \$3,000 paycheck raises Ready to Assign by \$3,000', () {
      // Ticket 07, worked example 9.
      final engine = _engine();
      final checking = _withChecking(engine, balance: const Money(41200));

      _accepted(
        engine.execute(
          RecordIncome(
            accountId: checking,
            amount: const Money(300000),
            date: CivilDate(2026, 11, 14),
            payee: 'Employer',
          ),
        ),
      );

      expect(engine.state.readyToAssign, const Money(341200));
      final paycheck = engine.state.transactions.last;
      expect(paycheck.payee, 'Employer');
      expect(paycheck.lines.single.category, readyToAssignCategory);
    });

    test('rejects zero, negative and unknown-account income', () {
      final engine = _engine();
      final checking = _withChecking(engine);
      final before = engine.events.length;

      expect(
        _rejected(
          engine.execute(
            RecordIncome(accountId: checking, amount: Money.zero, date: _nov1),
          ),
        ),
        Rejection.incomeMustBePositive,
      );
      expect(
        _rejected(
          engine.execute(
            RecordIncome(
              accountId: checking,
              amount: const Money(-100),
              date: _nov1,
            ),
          ),
        ),
        Rejection.incomeMustBePositive,
      );
      expect(
        _rejected(
          engine.execute(
            RecordIncome(
              accountId: 'missing',
              amount: const Money(100),
              date: _nov1,
            ),
          ),
        ),
        Rejection.unknownAccount,
      );
      expect(engine.events, hasLength(before));
    });
  });

  group('Event envelope', () {
    test('carries id, budgetId, deviceId, HLC, actor, groupId, type and '
        'payload', () {
      final engine = _engine();
      _withChecking(engine, balance: const Money(100));
      final events = engine.events;
      final uuidV7 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );

      for (final event in events) {
        expect(event.id, matches(uuidV7));
        expect(event.groupId, matches(uuidV7));
        expect(event.budgetId, engine.state.budget!.id);
        expect(event.deviceId, 'device-a');
        expect(event.hlc.deviceId, 'device-a');
        expect(event.actor, Actor.userAndroid);
        expect(event.payload, isNotEmpty);
      }
      expect(events.map((e) => e.id).toSet(), hasLength(events.length));
      // One group per command.
      expect(events.map((e) => e.groupId).toSet(), hasLength(2));
    });

    test('HLCs keep increasing when the wall clock steps back', () {
      var now = 2000;
      final log = InMemoryEventLog();
      final engine = _engine(log: log, nowMs: () => now);
      engine.execute(const CreateBudget(name: 'Home'));
      now = 1000;
      final checking = _withCheckingAfterBudget(engine);
      engine.execute(
        RecordIncome(accountId: checking, amount: const Money(1), date: _nov1),
      );

      final hlcs = engine.events.map((e) => e.hlc).toList();
      for (var i = 1; i < hlcs.length; i++) {
        expect(hlcs[i].compareTo(hlcs[i - 1]), greaterThan(0));
        expect(
          hlcs[i].toString().compareTo(hlcs[i - 1].toString()),
          greaterThan(0),
        );
      }

      // A restarted engine continues after the latest HLC in the log.
      final restarted = _engine(log: log, nowMs: () => 500);
      final next = _accepted(
        restarted.execute(
          RecordIncome(
            accountId: checking,
            amount: const Money(1),
            date: _nov1,
          ),
        ),
      ).single;
      expect(next.hlc.compareTo(hlcs.last), greaterThan(0));
    });

    test('round-trips through JSON', () {
      final engine = _engine();
      _withChecking(engine, balance: const Money(4200));
      for (final event in engine.events) {
        final json = jsonDecode(jsonEncode(event.toJson()));
        final copy = Event.fromJson(json as Map<String, Object?>);
        expect(jsonEncode(copy.toJson()), jsonEncode(event.toJson()));
        expect(copy.hlc, event.hlc);
      }
    });
  });

  test('replay orders Events by HLC, whatever order they arrive in', () {
    final engine = _engine();
    final checking = _withChecking(engine, balance: const Money(5000));
    engine.execute(
      RecordIncome(accountId: checking, amount: const Money(700), date: _nov1),
    );

    final shuffled = engine.events.reversed.toList();
    final replayed = BudgetState.replay(shuffled);
    expect(replayed.budget, engine.state.budget);
    expect(replayed.accounts, engine.state.accounts);
    expect(replayed.readyToAssign, const Money(5700));
  });
}

String _withCheckingAfterBudget(BudgetEngine engine) {
  _accepted(
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: Money.zero,
        asOf: _nov1,
      ),
    ),
  );
  return engine.state.accounts.single.id;
}
