import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _nov1 = CivilDate(2026, 11, 1);
final _nov4 = CivilDate(2026, 11, 4);
final _nov5 = CivilDate(2026, 11, 5);
final _nov10 = CivilDate(2026, 11, 10);
final _nov12 = CivilDate(2026, 11, 12);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// A budget named Home with Checking and a Dining out Category, and a clock
/// the fetch reads to decide a pending charge has been missing for 10 days.
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

  /// The day every command and fetch sees.
  var now = _nov12;

  int get _nowMs =>
      DateTime(now.year, now.month, now.day, 9).millisecondsSinceEpoch;

  BudgetEngine engine([Actor actor = Actor.userAndroid]) => BudgetEngine(
    log: log,
    deviceId: 'device-a',
    actor: actor,
    nowMs: () => _nowMs,
  );

  BudgetState get state => BudgetState.replay(log.readAll());

  CommandResult execute(Command command, [Actor actor = Actor.userAndroid]) =>
      engine(actor).execute(command);

  List<Event> run(Command command, [Actor actor = Actor.userAndroid]) =>
      _accepted(execute(command, actor));

  /// One fetch, as the app runs it after a hand pull. [accounts] are the app
  /// accounts it covered, whose pendings it may drop.
  CommandResult fetch(List<BankEntry> entries, {List<String>? accounts}) =>
      execute(
        ImportBankTransactions(
          entries: entries,
          fetchedAccounts: accounts ?? [checking],
        ),
      );

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
    date: date ?? now,
    amount: Money(cents),
    description: payee,
    memo: memo,
    pending: pending,
  );

  /// A line entered by hand. It is Reviewed only when [category] and
  /// [business] are both given.
  String handEntered({
    required int cents,
    required CivilDate date,
    String payee = 'Corner Bistro',
    String? category,
    BusinessStatus? business,
  }) =>
      run(
            CreateTransaction(
              accountId: checking,
              date: date,
              amount: Money(cents),
              payee: payee,
              lines: [
                LineInput(
                  amount: Money(cents),
                  category: category,
                  business: business,
                ),
              ],
            ),
          ).single.payload['transactionId']
          as String;

  List<Transaction> get bankTransactions => [
    for (final transaction in state.transactions)
      if (transaction.bankId != null) transaction,
  ];

  Transaction transaction(String bankId) =>
      state.bankTransaction(checking, bankId)!;

  TransactionLine line(String bankId) => transaction(bankId).lines.single;

  CommandResult review(
    String bankId, {
    BusinessStatus business = const Personal(),
  }) {
    final transaction = this.transaction(bankId);
    return execute(
      ReviewLine(
        transactionId: transaction.id,
        lineId: transaction.lines.single.id,
        category: diningOut,
        business: business,
      ),
    );
  }
}

void main() {
  group('a pending charge that posts under a new id', () {
    test('replaces it in place, keeping the category, business and memo', () {
      final budget = _Budget();
      budget.fetch([
        budget.entry(bankId: 'pending-1', cents: -4000, pending: true),
      ]);
      final id = budget.transaction('pending-1').id;
      _accepted(budget.review('pending-1', business: const Business('Meals')));
      budget.run(EditTransaction(transactionId: id, memo: 'Team lunch'));

      budget.now = _nov12;
      budget.fetch([
        budget.entry(bankId: 'posted-2', cents: -4600, payee: 'CORNER BISTRO'),
      ]);

      expect(budget.bankTransactions, hasLength(1));
      final replaced = budget.state.transaction(id)!;
      expect(replaced.bankId, 'posted-2');
      expect(replaced.amount, const Money(-4600));
      expect(replaced.date, _nov12);
      expect(replaced.cleared, ClearedStatus.cleared);
      expect(replaced.memo, 'Team lunch');
      final line = replaced.lines.single;
      expect(line.category, budget.diningOut);
      expect(line.business, const Business('Meals'));
      expect(line.memo, '');
      expect(line.amount, const Money(-4600));
      expect(line.reviewed, isFalse);
      expect(line.note, 'changed by bank: −\$40.00 → −\$46.00');
      expect(budget.state.reviewQueue.single.transaction.id, id);
    });

    test('keeps the line Reviewed when the amount did not change', () {
      final budget = _Budget();
      budget.fetch([budget.entry(bankId: 'pending-1', pending: true)]);
      final pendingId = budget.transaction('pending-1').id;
      _accepted(budget.review('pending-1'));

      budget.fetch([budget.entry(bankId: 'posted-2')]);

      final line = budget.state.transaction(pendingId)!.lines.single;
      expect(line.reviewed, isTrue);
      expect(line.note, isNull);
      expect(budget.state.reviewQueue, isEmpty);
    });

    test(
      'needs a payee and a day within seven, and an amount within range',
      () {
        final budget = _Budget();
        budget.now = _nov12;
        budget.fetch([
          budget.entry(
            bankId: 'pending-1',
            cents: -4000,
            date: _nov4,
            pending: true,
          ),
        ]);
        final pendingId = budget.transaction('pending-1').id;

        // Eight days later: a new charge, not this one.
        budget.fetch([
          budget.entry(bankId: 'posted-2', cents: -4000, date: _nov12),
        ]);
        expect(budget.state.transaction(pendingId)!.bankId, 'pending-1');

        // A different payee a day later is a different charge.
        budget.fetch([
          budget.entry(
            bankId: 'posted-3',
            cents: -4000,
            payee: 'Hardware Store',
            date: _nov5,
          ),
        ]);
        expect(budget.state.transaction(pendingId)!.bankId, 'pending-1');

        // A tip that takes it past +25% is not the same charge either.
        budget.fetch([
          budget.entry(bankId: 'posted-4', cents: -5001, date: _nov5),
        ]);
        expect(budget.state.transaction(pendingId)!.bankId, 'pending-1');
        expect(budget.bankTransactions, hasLength(4));
      },
    );

    test('the posted window is +25% and −10% of the pending amount', () {
      expect(
        withinPostedWindow(const Money(-4000), const Money(-5000)),
        isTrue,
      );
      expect(
        withinPostedWindow(const Money(-4000), const Money(-5001)),
        isFalse,
      );
      expect(
        withinPostedWindow(const Money(-4000), const Money(-3600)),
        isTrue,
      );
      expect(
        withinPostedWindow(const Money(-4000), const Money(-3599)),
        isFalse,
      );
      // A refund is never the posted version of a charge.
      expect(
        withinPostedWindow(const Money(-4000), const Money(4000)),
        isFalse,
      );
    });

    test('a payee about 80% the same still matches', () {
      final budget = _Budget();
      budget.fetch([
        budget.entry(
          bankId: 'pending-1',
          payee: 'Corner Bistro',
          pending: true,
        ),
      ]);
      budget.fetch([
        budget.entry(bankId: 'posted-2', payee: 'Corner Bistr #2'),
      ]);

      expect(budget.bankTransactions, hasLength(1));
      expect(budget.transaction('posted-2').payee, 'Corner Bistr #2');
    });

    test('only a posted charge replaces a pending one', () {
      final budget = _Budget();
      budget.fetch([
        budget.entry(bankId: 'pending-1', cents: -4000, pending: true),
      ]);

      budget.fetch([
        budget.entry(bankId: 'pending-2', cents: -4000, pending: true),
      ]);

      expect(budget.bankTransactions, hasLength(2));
      expect(budget.state.transactions.first.pendingMatch, isNull);
    });
  });

  group('a pending charge that vanishes', () {
    test('is dropped after 10 days and leaves the balance', () {
      final budget = _Budget();
      budget.fetch([
        budget.entry(
          bankId: 'pending-1',
          cents: -4820,
          date: _nov1,
          pending: true,
        ),
      ]);
      expect(budget.state.balance(budget.checking), const Money(45180));

      // Nine days later it may still be on its way.
      budget.now = _nov10;
      expect(_rejected(budget.fetch(const [])), Rejection.noChange);
      expect(budget.state.balance(budget.checking), const Money(45180));

      // On the tenth day a feed that no longer has it drops it.
      budget.now = _nov1.addDays(10);
      final events = _accepted(budget.fetch(const []));
      expect(events.single.type, EventType.transactionDeleted);
      expect(events.single.actor, Actor.bankSync);
      expect(
        budget.state.bankTransaction(budget.checking, 'pending-1'),
        isNull,
      );
      expect(budget.state.balance(budget.checking), const Money(50000));
      expect(
        budget.state.register(budget.checking).single.payee,
        'Starting Balance',
      );
      // The log keeps it; the revert test below restores it.
    });

    test('stays while the feed still reports it', () {
      final budget = _Budget();
      budget.fetch([
        budget.entry(
          bankId: 'pending-1',
          cents: -4820,
          date: _nov1,
          pending: true,
        ),
      ]);

      budget.now = _nov1.addDays(11);
      budget.fetch([
        budget.entry(
          bankId: 'pending-1',
          cents: -4820,
          date: _nov1,
          pending: true,
        ),
      ]);

      expect(
        budget.state.bankTransaction(budget.checking, 'pending-1'),
        isNotNull,
      );
      expect(budget.state.balance(budget.checking), const Money(45180));
    });

    test('is only dropped in an account the fetch covered', () {
      final budget = _Budget();
      budget.fetch([
        budget.entry(
          bankId: 'pending-1',
          cents: -4820,
          date: _nov1,
          pending: true,
        ),
      ]);

      budget.now = _nov1.addDays(11);
      expect(
        _rejected(budget.fetch(const [], accounts: const [])),
        Rejection.noChange,
      );
      expect(
        budget.state.bankTransaction(budget.checking, 'pending-1'),
        isNotNull,
      );
    });

    test('a posted charge is never dropped', () {
      final budget = _Budget();
      budget.fetch([
        budget.entry(bankId: 'posted-1', cents: -4820, date: _nov1),
      ]);

      budget.now = _nov1.addDays(30);
      expect(_rejected(budget.fetch(const [])), Rejection.noChange);
      expect(
        budget.state.bankTransaction(budget.checking, 'posted-1'),
        isNotNull,
      );
    });

    test('the drop can be reverted', () {
      final budget = _Budget();
      budget.fetch([
        budget.entry(
          bankId: 'pending-1',
          cents: -4820,
          date: _nov1,
          pending: true,
        ),
      ]);
      budget.now = _nov1.addDays(10);
      final drop = _accepted(budget.fetch(const []));

      budget.run(RevertGroup(groupId: drop.single.groupId));

      expect(
        budget.state.bankTransaction(budget.checking, 'pending-1'),
        isNotNull,
      );
      expect(budget.state.balance(budget.checking), const Money(45180));
    });
  });

  group('a charge that looks like a line entered by hand', () {
    test('is only proposed, never merged, until a person confirms', () {
      final budget = _Budget();
      final hand = budget.handEntered(
        cents: -4820,
        date: _nov10,
        category: budget.diningOut,
        business: const Personal(),
      );

      budget.fetch([budget.entry(cents: -4820)]);

      // Nothing moved: no new line, no bank id, the balance counts once.
      expect(budget.bankTransactions, isEmpty);
      expect(budget.state.transactions, hasLength(2));
      final waiting = budget.state.transaction(hand)!;
      expect(waiting.bankId, isNull);
      expect(waiting.pendingMatch?.bankId, 'sf-1');
      expect(waiting.pendingMatch?.amount, const Money(-4820));
      expect(waiting.pendingMatch?.description, 'Corner Bistro');
      expect(budget.state.balance(budget.checking), const Money(45180));
      expect(budget.state.proposedMatches.single.id, hand);

      budget.run(ConfirmBankMatch(transactionId: hand));

      final matched = budget.state.transaction(hand)!;
      expect(matched.bankId, 'sf-1');
      expect(matched.pendingMatch, isNull);
      expect(matched.amount, const Money(-4820));
      expect(matched.date, _nov12);
      expect(matched.cleared, ClearedStatus.cleared);
      expect(matched.lines.single.category, budget.diningOut);
      expect(matched.lines.single.business, const Personal());
      expect(matched.lines.single.reviewed, isTrue);
      expect(budget.state.balance(budget.checking), const Money(45180));
      expect(budget.state.proposedMatches, isEmpty);
      expect(budget.state.reviewQueue, isEmpty);
    });

    test('rejecting enters the bank charge as its own Unreviewed line', () {
      final budget = _Budget();
      final hand = budget.handEntered(
        cents: -4820,
        date: _nov10,
        category: budget.diningOut,
        business: const Personal(),
      );
      budget.fetch([budget.entry(cents: -4820)]);

      budget.run(RejectBankMatch(transactionId: hand));

      expect(budget.state.transaction(hand)!.pendingMatch, isNull);
      expect(budget.state.transaction(hand)!.bankId, isNull);
      final created = budget.state.bankTransaction(budget.checking, 'sf-1')!;
      expect(created.amount, const Money(-4820));
      expect(created.cleared, ClearedStatus.cleared);
      expect(created.lines.single.category, isNull);
      expect(created.lines.single.reviewed, isFalse);
      // Both are the person's to sort out; nothing was categorized for them.
      expect(budget.state.reviewQueue.single.transaction.id, created.id);
      expect(budget.state.balance(budget.checking), const Money(40360));
    });

    test('an equally exact line five days away still looks like it', () {
      final budget = _Budget();
      final hand = budget.handEntered(cents: -4820, date: _nov12.addDays(-5));
      budget.fetch([budget.entry(cents: -4820, date: _nov12)]);
      expect(budget.state.transaction(hand)!.pendingMatch?.bankId, 'sf-1');

      final far = budget.handEntered(cents: -1500, date: _nov12.addDays(-6));
      budget.fetch([budget.entry(bankId: 'sf-2', cents: -1500, date: _nov12)]);
      expect(budget.state.transaction(far)!.pendingMatch, isNull);
      expect(budget.state.bankTransaction(budget.checking, 'sf-2'), isNotNull);
    });

    test('needs the exact amount', () {
      final budget = _Budget();
      final hand = budget.handEntered(cents: -4820, date: _nov10);

      budget.fetch([budget.entry(cents: -4821)]);

      expect(budget.state.transaction(hand)!.pendingMatch, isNull);
      expect(budget.state.bankTransaction(budget.checking, 'sf-1'), isNotNull);
    });

    test('a line waiting on a match stays out of Review', () {
      final budget = _Budget();
      final hand = budget.handEntered(cents: -4820, date: _nov10);
      expect(budget.state.reviewQueue, hasLength(1));

      budget.fetch([budget.entry(cents: -4820)]);

      expect(budget.state.transaction(hand)!.pendingMatch, isNotNull);
      expect(budget.state.reviewQueue, isEmpty);
    });

    test('a Starting Balance is never a candidate', () {
      final budget = _Budget();
      final card =
          budget
                  .run(
                    AddAccount(
                      name: 'Card',
                      type: AccountType.creditCard,
                      startingBalance: const Money(-12000),
                      asOf: _nov1,
                    ),
                  )
                  .first
                  .payload['accountId']
              as String;

      budget.fetch([budget.entry(accountId: card, cents: -12000, date: _nov1)]);

      expect(budget.state.proposedMatches, isEmpty);
      expect(budget.state.bankTransaction(card, 'sf-1'), isNotNull);
    });

    test('a transfer is never a candidate', () {
      final budget = _Budget();
      final savings =
          budget
                  .run(
                    AddAccount(
                      name: 'Savings',
                      type: AccountType.savings,
                      startingBalance: Money.zero,
                      asOf: _nov1,
                    ),
                  )
                  .first
                  .payload['accountId']
              as String;
      budget.run(
        CreateTransfer(
          fromAccountId: budget.checking,
          toAccountId: savings,
          amount: const Money(4820),
          date: _nov10,
        ),
      );

      budget.fetch([budget.entry(cents: -4820)]);

      expect(budget.state.proposedMatches, isEmpty);
      expect(budget.state.bankTransaction(budget.checking, 'sf-1'), isNotNull);
    });

    test('confirming needs a person and a proposal', () {
      final budget = _Budget();
      final hand = budget.handEntered(cents: -4820, date: _nov10);
      expect(
        _rejected(
          budget.execute(ConfirmBankMatch(transactionId: hand), Actor.bankSync),
        ),
        Rejection.personRequired,
      );

      expect(
        _rejected(budget.execute(ConfirmBankMatch(transactionId: hand))),
        Rejection.noProposedMatch,
      );
      expect(
        _rejected(
          budget.execute(const ConfirmBankMatch(transactionId: 'nope')),
        ),
        Rejection.unknownTransaction,
      );
    });

    test('an edited amount no longer fits the bank charge', () {
      final budget = _Budget();
      final hand = budget.handEntered(cents: -4820, date: _nov10);
      budget.fetch([budget.entry(cents: -4820)]);
      final line = budget.state.transaction(hand)!.lines.single;
      budget.run(
        EditTransaction(
          transactionId: hand,
          amount: const Money(-5000),
          lines: [LineInput(id: line.id, amount: const Money(-5000))],
        ),
      );

      expect(
        _rejected(budget.execute(ConfirmBankMatch(transactionId: hand))),
        Rejection.matchAmountChanged,
      );
      expect(budget.state.transaction(hand)!.bankId, isNull);
      expect(budget.state.transaction(hand)!.pendingMatch, isNotNull);
    });

    test('a re-fetch refreshes the proposal without duplicating it', () {
      final budget = _Budget();
      final hand = budget.handEntered(cents: -4820, date: _nov10);
      budget.fetch([budget.entry(cents: -4820)]);

      budget.fetch([budget.entry(cents: -4820, payee: 'Cafe Bistro')]);

      expect(budget.state.proposedMatches, hasLength(1));
      expect(
        budget.state.transaction(hand)!.pendingMatch?.description,
        'Cafe Bistro',
      );
      expect(budget.state.transactions, hasLength(2));
    });

    test('a fetched proposal for the same bank id writes no second group', () {
      final budget = _Budget();
      budget.handEntered(cents: -4820, date: _nov10);
      budget.fetch([budget.entry(cents: -4820)]);
      final events = budget.log.readAll().length;

      expect(
        _rejected(budget.fetch([budget.entry(cents: -4820)])),
        Rejection.noChange,
      );
      expect(budget.log.readAll(), hasLength(events));
    });
  });

  group('payee matching', () {
    test('normalizes case and punctuation', () {
      expect(normalizedPayee('CORNER BISTRO #2'), 'cornerbistro2');
      expect(samePayee('Corner Bistro', 'corner bistro'), isTrue);
      expect(samePayee('Corner Bistro', 'Hardware Store'), isFalse);
    });

    test('scores alike payees at least 80', () {
      expect(payeeSimilarity('Corner Bistro', 'Corner Bistro'), 100);
      expect(payeeSimilarity('Corner Bistro', 'Corner Bistr'), greaterThan(80));
      expect(payeeSimilarity('Corner Bistro', 'Hardware'), lessThan(80));
    });
  });

  group('the balance check', () {
    test('is null when the bank agrees with the app', () {
      final budget = _Budget();
      expect(
        balanceDiscrepancy(
          state: budget.state,
          accountId: budget.checking,
          bankBalance: const Money(50000),
          date: _nov12,
        ),
        isNull,
      );
    });

    test('is the bank balance less the app balance', () {
      final budget = _Budget();
      final discrepancy = balanceDiscrepancy(
        state: budget.state,
        accountId: budget.checking,
        bankBalance: const Money(49000),
        date: _nov12,
      )!;
      expect(discrepancy.bankBalance, const Money(49000));
      expect(discrepancy.appBalance, const Money(50000));
      expect(discrepancy.difference, const Money(-1000));
      expect(discrepancy.date, _nov12);
    });
  });
}
