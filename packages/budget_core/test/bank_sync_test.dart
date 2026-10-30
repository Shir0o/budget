import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _nov1 = CivilDate(2026, 11, 1);
final _nov12 = CivilDate(2026, 11, 12);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// A budget named Home with Checking, and a Dining out Category. Each
/// command runs as [actor] over the same log.
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
    diningOut =
        run(CreateCategory(groupId: group, name: 'Dining out'))
                .single
                .payload['categoryId']
            as String;
  }

  final log = InMemoryEventLog();
  late final String checking;
  late final String diningOut;

  BudgetEngine engine([Actor actor = Actor.userAndroid]) =>
      BudgetEngine(log: log, deviceId: 'device-a', actor: actor);

  BudgetState get state => BudgetState.replay(log.readAll());

  CommandResult execute(Command command, [Actor actor = Actor.userAndroid]) =>
      engine(actor).execute(command);

  List<Event> run(Command command, [Actor actor = Actor.userAndroid]) =>
      _accepted(execute(command, actor));

  /// One fetch, as the app runs it after a hand pull.
  CommandResult fetch(List<BankEntry> entries) =>
      execute(ImportBankTransactions(entries: entries));

  BankEntry entry({
    String bankId = 'sf-1',
    int cents = -4820,
    String payee = 'Corner Bistro',
    String memo = '',
    CivilDate? date,
    bool pending = false,
    String? accountId,
  }) => BankEntry(
    accountId: accountId ?? checking,
    bankId: bankId,
    date: date ?? _nov12,
    amount: Money(cents),
    description: payee,
    memo: memo,
    pending: pending,
  );

  /// The transactions a fetch imported, without the Starting Balance.
  List<Transaction> get bankTransactions => [
    for (final transaction in state.transactions)
      if (transaction.bankId != null) transaction,
  ];

  Transaction transaction(String bankId) =>
      state.bankTransaction(checking, bankId)!;

  TransactionLine line(String bankId) => transaction(bankId).lines.single;

  /// Reconciles Checking at its cleared balance, so its cleared
  /// transactions become Reconciled.
  void reconcile() => run(
    Reconcile(
      accountId: checking,
      date: _nov12,
      bankBalance: state.clearedBalance(checking),
    ),
  );

  CommandResult review(String bankId) => execute(
    ReviewLine(
      transactionId: transaction(bankId).id,
      lineId: line(bankId).id,
      category: diningOut,
      business: const Personal(),
    ),
  );
}

void main() {
  group('ImportBankTransactions', () {
    test('creates Unreviewed lines as one bank-sync group', () {
      final budget = _Budget();
      final result = budget.fetch([
        budget.entry(),
        budget.entry(bankId: 'sf-2', cents: -1500, payee: 'Cafe'),
      ]);

      final events = _accepted(result);
      expect(
        events.map((event) => event.type),
        everyElement(EventType.transactionCreated),
      );
      expect(events.map((event) => event.actor).toSet(), {Actor.bankSync});
      expect(events.map((event) => event.groupId).toSet(), hasLength(1));

      final transaction = budget.transaction('sf-1');
      expect(transaction.bankId, 'sf-1');
      expect(transaction.accountId, budget.checking);
      expect(transaction.date, _nov12);
      expect(transaction.payee, 'Corner Bistro');
      expect(transaction.amount, const Money(-4820));
      expect(transaction.cleared, ClearedStatus.cleared);
      final line = transaction.lines.single;
      expect(line.amount, const Money(-4820));
      expect(line.category, isNull);
      expect(line.business, isNull);
      expect(line.reviewed, isFalse);
      expect(line.note, isNull);
      // Nothing was categorized for the person (ADR 0003).
      expect(budget.state.reviewQueue, hasLength(2));
    });

    test('keeps a pending transaction uncleared with its memo', () {
      final budget = _Budget();
      budget.fetch([
        budget.entry(cents: -1200, memo: 'Card hold', pending: true),
      ]);

      final transaction = budget.transaction('sf-1');
      expect(transaction.cleared, ClearedStatus.uncleared);
      expect(transaction.memo, 'Card hold');
      expect(transaction.amount, const Money(-1200));
    });

    test('updates a same id in place, with the bank’s date and payee', () {
      final budget = _Budget();
      budget.fetch([budget.entry()]);
      final id = budget.transaction('sf-1').id;

      budget.fetch([
        budget.entry(payee: 'Cafe Bistro', date: _nov1, cents: -4820),
      ]);

      expect(budget.bankTransactions, hasLength(1));
      final transaction = budget.state.transaction(id)!;
      expect(transaction.payee, 'Cafe Bistro');
      expect(transaction.date, _nov1);
      expect(transaction.amount, const Money(-4820));
      expect(budget.state.reviewQueue, hasLength(1));
    });

    test(
      'a reviewed line whose amount changed returns to Review with a note',
      () {
        final budget = _Budget();
        budget.fetch([budget.entry(cents: -4820)]);
        _accepted(budget.review('sf-1'));
        expect(budget.line('sf-1').reviewed, isTrue);

        budget.fetch([budget.entry(cents: -1500)]);

        final line = budget.line('sf-1');
        expect(line.reviewed, isFalse);
        expect(line.amount, const Money(-1500));
        // The person's Category stays, so Review only asks to confirm again.
        expect(line.category, budget.diningOut);
        expect(line.business, const Personal());
        expect(line.note, 'changed by bank: −\$48.20 → −\$15.00');
        expect(budget.state.reviewQueue.single.line.note, line.note);
      },
    );

    test('a reviewed line whose amount is unchanged stays reviewed', () {
      final budget = _Budget();
      budget.fetch([budget.entry()]);
      _accepted(budget.review('sf-1'));

      budget.fetch([budget.entry(payee: 'Corner Bistro #2')]);

      final line = budget.line('sf-1');
      expect(line.reviewed, isTrue);
      expect(line.note, isNull);
      expect(budget.state.reviewQueue, isEmpty);
    });

    test('a fetch that changed nothing writes no group', () {
      final budget = _Budget();
      budget.fetch([budget.entry()]);
      final events = budget.log.readAll().length;

      expect(_rejected(budget.fetch([budget.entry()])), Rejection.noChange);
      expect(budget.log.readAll(), hasLength(events));
    });

    test('rejects a bank entry for an account that does not exist', () {
      final budget = _Budget();

      expect(
        _rejected(budget.fetch([budget.entry(accountId: 'nope')])),
        Rejection.unknownAccount,
      );
      expect(budget.bankTransactions, isEmpty);
    });

    test('a split takes the new amount with the difference in Review', () {
      final budget = _Budget();
      budget.fetch([budget.entry(cents: -1000)]);
      final id = budget.transaction('sf-1').id;
      budget.run(
        EditTransaction(
          transactionId: id,
          amount: const Money(-1000),
          lines: [
            LineInput(
              amount: const Money(-600),
              category: budget.diningOut,
              business: const Personal(),
            ),
            LineInput(
              amount: const Money(-400),
              category: budget.diningOut,
              business: const Personal(),
            ),
          ],
        ),
      );
      expect(budget.state.reviewQueue, isEmpty);

      budget.fetch([budget.entry(cents: -1500)]);

      final transaction = budget.state.transaction(id)!;
      expect(transaction.amount, const Money(-1500));
      // The person's lines stay as they split them, and the difference waits
      // in its own Unreviewed line, so the split still adds up.
      expect(transaction.lines.map((line) => line.amount), [
        const Money(-600),
        const Money(-400),
        const Money(-500),
      ]);
      expect(transaction.lines.take(2).map((line) => line.reviewed), [
        isTrue,
        isTrue,
      ]);
      final difference = transaction.lines.last;
      expect(difference.category, isNull);
      expect(difference.reviewed, isFalse);
      expect(difference.note, 'changed by bank: −\$10.00 → −\$15.00');
      expect(budget.state.reviewQueue.single.line.id, difference.id);

      expect(
        _rejected(budget.fetch([budget.entry(cents: -1500)])),
        Rejection.noChange,
      );
    });

    test('a re-fetch keeps the memo the person wrote', () {
      final budget = _Budget();
      budget.fetch([budget.entry(memo: 'Card hold')]);
      final id = budget.transaction('sf-1').id;
      budget.run(EditTransaction(transactionId: id, memo: 'Team lunch'));

      budget.fetch([budget.entry(memo: 'Card hold')]);

      expect(budget.state.transaction(id)!.memo, 'Team lunch');
    });

    test('a re-fetch never sends a cleared line back to pending', () {
      final budget = _Budget();
      budget.fetch([budget.entry()]);

      expect(
        _rejected(budget.fetch([budget.entry(pending: true)])),
        Rejection.noChange,
      );
      expect(budget.transaction('sf-1').cleared, ClearedStatus.cleared);
    });

    test('a re-fetch leaves a Reconciled transaction Reconciled', () {
      final budget = _Budget();
      budget.fetch([budget.entry()]);
      budget.reconcile();

      expect(
        _rejected(budget.fetch([budget.entry(payee: 'Corner Bistro #2')])),
        Rejection.noChange,
      );
      final transaction = budget.transaction('sf-1');
      expect(transaction.cleared, ClearedStatus.reconciled);
      expect(transaction.payee, 'Corner Bistro');
    });

    test('a new bank amount on a Reconciled transaction waits for a '
        'person', () {
      final budget = _Budget();
      budget.fetch([budget.entry(cents: -4820)]);
      _accepted(budget.review('sf-1'));
      budget.reconcile();

      budget.fetch([budget.entry(cents: -1500)]);

      // Editing a Reconciled transaction needs the person's confirmation
      // (ticket 09), so the amount stays and Review shows the bank's.
      final transaction = budget.transaction('sf-1');
      expect(transaction.cleared, ClearedStatus.reconciled);
      expect(transaction.amount, const Money(-4820));
      final line = transaction.lines.single;
      expect(line.amount, const Money(-4820));
      expect(line.category, budget.diningOut);
      expect(line.reviewed, isFalse);
      expect(line.note, 'bank shows −\$15.00, Reconciled at −\$48.20');
      expect(budget.state.reviewQueue.single.line.id, line.id);

      expect(
        _rejected(budget.fetch([budget.entry(cents: -1500)])),
        Rejection.noChange,
      );
    });

    test('keeps only the last four digits of a number in a bank payee', () {
      final budget = _Budget();
      budget.fetch([budget.entry(payee: 'Card 4111 1111 1111 1111 payment')]);

      expect(budget.transaction('sf-1').payee, 'Card ••••1111 payment');
      expect(
        containsSensitiveNumber(budget.transaction('sf-1').payee),
        isFalse,
      );
    });

    test('the whole fetch can be reverted as one group', () {
      final budget = _Budget();
      final events = _accepted(budget.fetch([budget.entry()]));

      budget.run(RevertGroup(groupId: events.first.groupId));

      expect(budget.bankTransactions, isEmpty);
      expect(budget.state.bankTransaction(budget.checking, 'sf-1'), isNull);
    });
  });
}
