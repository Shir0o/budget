import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _nov = CalendarMonth(2026, 11);
final _nov1 = CivilDate(2026, 11, 1);
final _nov12 = CivilDate(2026, 11, 12);
final _nov13 = CivilDate(2026, 11, 13);

/// A checking account at 500.00 (cleared, from its Starting Balance) with a
/// 20.00 cleared purchase and a 5.00 uncleared one.
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
    checking = engine.state.accounts.single.id;
    cleared = purchase(-2000, ClearedStatus.cleared);
    uncleared = purchase(-500, ClearedStatus.uncleared);
  }

  final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'device-a',
    actor: Actor.userAndroid,
  );
  late final String checking;
  late final String cleared;
  late final String uncleared;

  BudgetState get state => engine.state;

  CommandResult run(Command command) => engine.execute(command);

  String purchase(int cents, ClearedStatus status) {
    final created = run(
      CreateTransaction(
        accountId: checking,
        date: _nov12,
        amount: Money(cents),
        lines: [LineInput(amount: Money(cents))],
      ),
    ) as Accepted;
    final id = created.events.single.payload['transactionId'] as String;
    run(EditTransaction(transactionId: id, cleared: status));
    return id;
  }

  CommandResult reconcile(int bankCents, {bool adjust = false}) => run(
    Reconcile(
      accountId: checking,
      date: _nov13,
      bankBalance: Money(bankCents),
      addAdjustment: adjust,
    ),
  );
}

void main() {
  test('a matching balance reconciles the cleared transactions only', () {
    final budget = _Budget();
    expect(budget.state.clearedBalance(budget.checking), const Money(48000));

    expect(budget.reconcile(48000), isA<Accepted>());

    expect(
      budget.state.transaction(budget.cleared)!.cleared,
      ClearedStatus.reconciled,
    );
    expect(
      budget.state.transaction(budget.uncleared)!.cleared,
      ClearedStatus.uncleared,
    );
    expect(budget.state.clearedBalance(budget.checking), const Money(48000));
  });

  test('a mismatch is rejected and changes nothing', () {
    final budget = _Budget();
    final before = budget.engine.events.length;

    final result = budget.reconcile(47500);

    expect((result as Rejected).reason, Rejection.reconcileMismatch);
    expect(budget.engine.events, hasLength(before));
    expect(
      budget.state.transaction(budget.cleared)!.cleared,
      ClearedStatus.cleared,
    );
  });

  test('an adjustment is Unreviewed, goes to Ready to Assign, reconciles', () {
    final budget = _Budget();
    final rtaBefore = budget.state.readyToAssign(_nov);

    // The bank shows 5.00 less than the app's cleared 480.00.
    expect(budget.reconcile(47500, adjust: true), isA<Accepted>());

    final adjustment = budget.state
        .register(budget.checking)
        .firstWhere((t) => t.payee == 'Reconciliation Adjustment');
    expect(adjustment.amount, const Money(-500));
    expect(adjustment.cleared, ClearedStatus.reconciled);
    expect(adjustment.lines.single.category, readyToAssignCategory);
    expect(adjustment.lines.single.reviewed, isFalse);
    expect(budget.state.clearedBalance(budget.checking), const Money(47500));
    expect(budget.state.readyToAssign(_nov), rtaBefore - const Money(500));
  });

  test('no adjustment is added when the balance already matches', () {
    final budget = _Budget();
    final result = budget.reconcile(48000, adjust: true) as Accepted;
    expect(result.events.map((e) => e.type), [EventType.reconciled]);
  });

  test('editing a reconciled transaction needs confirmation', () {
    final budget = _Budget();
    budget.reconcile(48000);
    final before = budget.engine.events.length;

    final refused = budget.run(
      EditTransaction(transactionId: budget.cleared, payee: 'Cafe'),
    );
    expect((refused as Rejected).reason, Rejection.reconciledNeedsConfirmation);
    expect(budget.engine.events, hasLength(before));

    final confirmed = budget.run(
      EditTransaction(
        transactionId: budget.cleared,
        payee: 'Cafe',
        confirmReconciled: true,
      ),
    );
    expect(confirmed, isA<Accepted>());
    expect(budget.state.transaction(budget.cleared)!.payee, 'Cafe');
  });

  test('an unknown account is rejected', () {
    final budget = _Budget();
    final result = budget.run(
      Reconcile(accountId: 'nope', date: _nov13, bankBalance: const Money(0)),
    );
    expect((result as Rejected).reason, Rejection.unknownAccount);
  });
}
