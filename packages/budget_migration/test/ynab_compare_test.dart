import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';
import 'package:test/test.dart';

import 'actual_fixture.dart' show syntheticBytes, syntheticZip;
import 'ynab_fixture.dart';

YnabExport _export({
  String register = ynabRegisterCsv,
  String plan = ynabPlanCsv,
  YnabDateOrder? dateOrder,
}) => YnabExport.read(
  YnabZip.decode(
    syntheticYnabZip(register: register, plan: plan),
    dateOrder: dateOrder,
  ),
);

(BudgetEngine, InMemoryEventLog) _engine() {
  final log = InMemoryEventLog();
  final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  engine.execute(const CreateBudget(name: 'Home'));
  final result = engine.execute(CommitImport(actualHistory()));
  if (result is! Accepted) {
    throw StateError('The synthetic history was refused');
  }
  return (engine, log);
}

final _ynab = _export();
final _historyEngine = _engine().$1;
final _state = _historyEngine.state;

YnabComparison _compare([NamePairing? pairing]) => compareWithYnab(
  ynab: _ynab,
  actual: _state,
  pairing: pairing ?? proposePairs(ynab: _ynab, actual: _state),
);

ComparisonItem _item(
  YnabComparison comparison,
  ComparisonCheck check,
  String label,
) => comparison.itemsFor(check).singleWhere((item) => item.label == label);

void main() {
  group('YnabExport', () {
    test('reads the Register into exact cents and Calendar dates', () {
      expect(_ynab.budgetName, 'Home');
      expect(_ynab.transactions, hasLength(11));
      expect(_ynab.entries, hasLength(10));

      final groceries = _ynab.transactions.firstWhere(
        (transaction) => transaction.payee == 'Corner Market',
      );
      expect(groceries.outflowCents, 12040);
      expect(groceries.inflowCents, 0);
      expect(groceries.amountCents, -12040);
      expect(groceries.date, CivilDate(2024, 1, 6));
      expect(groceries.category, 'Groceries');
      expect(groceries.categoryGroup, 'Bills');
      expect(groceries.cleared, ClearedStatus.cleared);
      expect(groceries.flag, '');

      final opening = _ynab.transactions.first;
      expect(opening.inflowCents, 500000);
      expect(opening.flag, 'Green');
      expect(opening.cleared, ClearedStatus.cleared);
    });

    test('strips a currency symbol and thousands separators in the Plan', () {
      final rent = _ynab.plan.firstWhere(
        (row) => row.category == 'Rent' && row.month.month == 1,
      );

      expect(rent.assignedCents, 150000);
      expect(rent.activityCents, -150000);
      expect(rent.availableCents, 0);
      expect(rent.categoryGroup, 'Bills');
    });

    test('folds the flattened Split rows back into one entry', () {
      final split = _ynab.entries.singleWhere((entry) => entry.isSplit);

      expect(split.rows, hasLength(2));
      expect(split.amountCents, -4500);
      expect(split.rows.map((row) => row.memo), ['veg', 'lunch']);
      expect(split.rows.map((row) => row.category), ['Groceries', 'Meals']);
      expect(split.date, CivilDate(2024, 4, 5));
    });

    test('reads transfers from the payee and drops the group total rows', () {
      final transfer = _ynab.entries.firstWhere(
        (entry) => entry.account == 'Everyday Checking' && entry.isTransfer,
      );

      expect(transfer.first.transferAccountName, 'Rainy Day Savings');
      expect(transfer.amountCents, -20000);
      expect(_ynab.plan, hasLength(8));
      expect(_ynab.firstMonth, CalendarMonth(2024, 1));
      expect(_ynab.lastMonth, CalendarMonth(2024, 4));
    });

    test(
      'detects a day-first export and asks when the sample is ambiguous',
      () {
        const dayFirst = '''Account,Flag,Date,Payee,Category Group/Category,Category Group,Category,Memo,Outflow,Inflow,Cleared
Everyday Checking,,13/01/2024,Landlord,Bills: Rent,Bills,Rent,,1500.00,,Cleared
''';
        final detected = _export(register: dayFirst, plan: '');

        expect(detected.dateOrder, YnabDateOrder.dayFirst);
        expect(detected.dateOrderAmbiguous, isFalse);
        expect(detected.transactions.single.date, CivilDate(2024, 1, 13));

        const ambiguous = '''Account,Flag,Date,Payee,Category Group/Category,Category Group,Category,Memo,Outflow,Inflow,Cleared
Everyday Checking,,03/04/2024,Landlord,Bills: Rent,Bills,Rent,,1500.00,,Cleared
''';
        final unsure = _export(register: ambiguous, plan: '');
        expect(unsure.dateOrderAmbiguous, isTrue);
        expect(unsure.transactions.single.date, CivilDate(2024, 3, 4));

        final answered = _export(
          register: ambiguous,
          plan: '',
          dateOrder: YnabDateOrder.dayFirst,
        );
        expect(answered.transactions.single.date, CivilDate(2024, 4, 3));
        expect(answered.dateOrderAmbiguous, isFalse);
      },
    );

    test('reads an older export whose Plan is Budget.csv and Budgeted', () {
      final export = YnabExport.read(
        YnabZip(
          budgetName: 'Home',
          registerCsv: ynabRegisterCsv,
          planCsv:
              'Month,Category Group/Category,Category Group,Category,Budgeted,Activity,Available\n'
              'Jan 2024,Bills: Rent,Bills,Rent,1500.00,-1500.00,0.00\n',
        ),
      );

      expect(export.plan.single.assignedCents, 150000);
    });

    test('refuses a file that is not a YNAB zip', () {
      expect(
        () => YnabZip.decode(syntheticZip({'notes.txt': 'hi'})),
        throwsA(isA<YnabExportException>()),
      );
      expect(
        () => YnabZip.decode(syntheticBytes('not a zip')),
        throwsA(isA<YnabExportException>()),
      );
    });

    test('refuses an amount that is not whole cents', () {
      const rounded = '''Account,Flag,Date,Payee,Category Group/Category,Category Group,Category,Memo,Outflow,Inflow,Cleared
Everyday Checking,,01/05/2024,Landlord,Bills: Rent,Bills,Rent,,12.345,,Cleared
''';

      expect(
        () => _export(register: rounded, plan: ''),
        throwsA(isA<YnabExportException>()),
      );
    });
  });

  group('proposePairs', () {
    test('pairs exact names and proposes the card payment Category', () {
      final pairing = proposePairs(ynab: _ynab, actual: _state);

      expect(
        pairing.actualIdFor(PairKind.account, 'Everyday Checking'),
        'acct-checking',
      );
      expect(pairing.actualIdFor(PairKind.categoryGroup, 'Bills'), 'grp-bills');
      expect(
        pairing.actualIdFor(PairKind.category, 'Groceries'),
        'cat-groceries',
      );
      final card = pairing.forName(PairKind.category, 'Travel Card')!;
      expect(card.actualId, 'cat-card');
      expect(card.proposed, isTrue);
      expect(pairing.proposed.map((pair) => pair.ynabName), ['Travel Card']);
    });

    test('an unpaired name and the person taking one entity back', () {
      final pairing = proposePairs(ynab: _ynab, actual: _state)
          .withPair(
            kind: PairKind.category,
            ynabName: 'Travel Card',
            actualId: null,
          )
          .withPair(
            kind: PairKind.category,
            ynabName: 'Groceries',
            actualId: 'cat-meals',
            actualName: 'Meals',
          );

      expect(pairing.actualIdFor(PairKind.category, 'Travel Card'), isNull);
      expect(pairing.actualIdFor(PairKind.category, 'Groceries'), 'cat-meals');
      // Meals was paired with nothing else, and one entity never pairs twice.
      expect(pairing.actualIdFor(PairKind.category, 'Meals'), isNull);
    });
  });

  group('comparison', () {
    final comparison = _compare();

    test('(a) month-end balances differ from February on, with the cent', () {
      final tally = comparison.tallyFor(ComparisonCheck.monthEndBalances);

      expect(tally.matched, 9);
      expect(tally.differs, 3);
      final february = _item(
        comparison,
        ComparisonCheck.monthEndBalances,
        'Everyday Checking · Feb 2024',
      );
      expect(february.status, ComparisonStatus.differs);
      expect(february.ynabCents, const Money(487960));
      expect(february.actualCents, const Money(487535));
      expect(february.detail, 'YNAB \$4,879.60 vs budget \$4,875.35');
      expect(
        _item(
          comparison,
          ComparisonCheck.monthEndBalances,
          'Everyday Checking · Mar 2024',
        ).detail,
        contains('first differed in Feb 2024'),
      );
    });

    test('(b) matches exactly, then ±3 days, and compares each field', () {
      final tally = comparison.tallyFor(ComparisonCheck.transactions);

      expect(tally.matched, 8);
      expect(tally.differs, 1);
      expect(tally.ynabOnly, 1);
      expect(tally.actualOnly, 1);
      final moved = _item(
        comparison,
        ComparisonCheck.transactions,
        'Landlord · 2024-02-02',
      );
      expect(moved.detail, contains('Date 2024-02-02 → 2024-02-04'));
      expect(
        _item(
          comparison,
          ComparisonCheck.transactions,
          'Corner Market · 2024-03-02',
        ).status,
        ComparisonStatus.ynabOnly,
      );
      expect(
        _item(
          comparison,
          ComparisonCheck.transactions,
          'Coffee Shop · 2024-02-20',
        ).status,
        ComparisonStatus.actualOnly,
      );
    });

    test('(c) labels carryover, card payment and income as expected', () {
      final tally = comparison.tallyFor(ComparisonCheck.categoryMonths);

      expect(tally.matched, 3);
      expect(tally.expected, 4);
      expect(tally.ynabOnly, 1);
      expect(tally.differs, 0);

      final carry = _item(
        comparison,
        ComparisonCheck.categoryMonths,
        'Groceries · Feb 2024',
      );
      expect(carry.status, ComparisonStatus.expected);
      expect(carry.expected, ExpectedDifference.carryover);
      expect(carry.ynabCents, const Money(-3040));
      expect(carry.actualCents, Money.zero);

      final card = _item(
        comparison,
        ComparisonCheck.categoryMonths,
        'Travel Card · Feb 2024',
      );
      expect(card.expected, ExpectedDifference.cardPayment);

      final income = _item(
        comparison,
        ComparisonCheck.categoryMonths,
        'Inflow: Ready to Assign · Jan 2024',
      );
      expect(income.expected, ExpectedDifference.income);
    });

    test('(d) lists entities only in one file, income aside', () {
      final tally = comparison.tallyFor(ComparisonCheck.entities);

      expect(tally.matched, 14);
      expect(tally.expected, 1);
      expect(tally.actualOnly, 1);
      expect(tally.ynabOnly, 0);
      expect(
        _item(
          comparison,
          ComparisonCheck.entities,
          'Category group “Inflow: Ready to Assign”',
        ).expected,
        ExpectedDifference.income,
      );
      expect(
        _item(
          comparison,
          ComparisonCheck.entities,
          'Payee “Coffee Shop”',
        ).status,
        ComparisonStatus.actualOnly,
      );
    });

    test('offers the YNAB-only transaction and Category month', () {
      final comparison = _compare();
      final pulls = comparison.pullItems;

      expect(pulls, hasLength(2));
      final transaction = pulls.singleWhere(
        (item) => item.check == ComparisonCheck.transactions,
      );
      expect(transaction.pull, isA<PullTransaction>());
      final month = pulls.singleWhere(
        (item) => item.check == ComparisonCheck.categoryMonths,
      );
      expect(month.pull, isA<PullAssignment>());
      expect(comparison.unresolved(const {}), hasLength(2));
    });

    test('a real difference keeps the comparison unclear', () {
      final comparison = _compare();
      final decisions = {
        for (final item in comparison.pullItems)
          item.pull!.key: const PullDecision.ignore('Not needed'),
      };

      expect(comparison.unresolved(decisions), isEmpty);
      // A month-end balance and a moved date really differ, so the report
      // still shows them after every pull is decided.
      expect(comparison.isClear(decisions), isFalse);
      expect(
        comparison.itemsFor(ComparisonCheck.monthEndBalances),
        everyElement(
          isA<ComparisonItem>().having(
            (item) => item.status,
            'status',
            ComparisonStatus.differs,
          ),
        ),
      );
    });

    test('matching history and export compare clear', () {
      final engine = BudgetEngine(
        log: InMemoryEventLog(),
        deviceId: 'test-device',
        actor: Actor.userAndroid,
      )..execute(const CreateBudget(name: 'Simple'));
      engine.execute(
        CommitImport(
          ImportBatch(
            accounts: const [
              ImportAccount(
                id: 'acct-cash',
                name: 'Cash',
                type: AccountType.checking,
              ),
            ],
            categoryGroups: const [
              ImportCategoryGroup(id: 'grp-bills', name: 'Bills'),
            ],
            categories: const [
              ImportCategory(
                id: 'cat-food',
                groupId: 'grp-bills',
                name: 'Food',
              ),
            ],
            transactions: [
              ImportTransaction(
                id: 'tx-market',
                accountId: 'acct-cash',
                date: CivilDate(2024, 1, 10),
                payee: 'Market',
                cleared: ClearedStatus.cleared,
                amount: const Money(-1000),
                lines: const [
                  ImportLine(
                    amount: Money(-1000),
                    category: 'cat-food',
                    reviewed: true,
                  ),
                ],
              ),
            ],
            assignments: [
              ImportAssignment(
                categoryId: 'cat-food',
                month: CalendarMonth(2024, 1),
                amount: const Money(1000),
              ),
            ],
            schedules: const [],
            targets: const [],
            expectedBalancesCents: const {'acct-cash': -1000},
          ),
        ),
      );
      final ynab = YnabExport.read(
        YnabZip(
          budgetName: 'Simple',
          registerCsv:
              'Account,Flag,Date,Payee,Category Group/Category,Category Group,'
              'Category,Memo,Outflow,Inflow,Cleared\n'
              'Cash,,01/10/2024,Market,Bills: Food,Bills,Food,,10.00,,Cleared\n',
          planCsv:
              'Month,Category Group/Category,Category Group,Category,Assigned,'
              'Activity,Available\n'
              'Jan 2024,Bills: Food,Bills,Food,10.00,-10.00,0.00\n',
        ),
      );
      final comparison = compareWithYnab(
        ynab: ynab,
        actual: engine.state,
        pairing: proposePairs(ynab: ynab, actual: engine.state),
      );

      expect(comparison.items, isEmpty);
      for (final check in ComparisonCheck.values) {
        expect(comparison.tallyFor(check).differs, 0, reason: check.title);
        expect(comparison.tallyFor(check).ynabOnly, 0, reason: check.title);
      }
      expect(comparison.isClear(const {}), isTrue);
    });
  });

  group('pullBatch', () {
    test('adds the chosen transaction Unreviewed and the assignment', () {
      final comparison = _compare();
      final decisions = {
        for (final item in comparison.pullItems)
          item.pull!.key: const PullDecision.add(),
      };
      final batch = pullBatch(comparison: comparison, decisions: decisions);

      expect(batch.accounts, isEmpty);
      expect(batch.expectedBalancesCents, isEmpty);
      expect(batch.transactions, hasLength(1));
      final transaction = batch.transactions.single;
      expect(transaction.accountId, 'acct-checking');
      expect(transaction.date, CivilDate(2024, 3, 2));
      expect(transaction.payee, 'Corner Market');
      expect(transaction.amount, const Money(-4275));
      expect(transaction.lines.single.category, 'cat-groceries');
      expect(transaction.lines.single.reviewed, isFalse);
      expect(transaction.lines.single.business, isNull);

      expect(batch.assignments, hasLength(1));
      expect(batch.assignments.single.categoryId, 'cat-meals');
      expect(batch.assignments.single.month, CalendarMonth(2024, 1));
      expect(batch.assignments.single.amount, const Money(2500));
    });

    test('writes the pull-ins as one revertable group', () {
      final engine = _engine().$1;
      final comparison = _compare();
      final decisions = {
        for (final item in comparison.pullItems)
          item.pull!.key: const PullDecision.add(),
      };
      final before = engine.events.length;

      final commit = commitYnabPull(
        engine,
        pullBatch(comparison: comparison, decisions: decisions),
      );

      final state = engine.state;
      expect(engine.events.skip(before).map((event) => event.groupId).toSet(), {
        commit.groupId,
      });
      final pulled = state.transactions.singleWhere(
        (transaction) =>
            transaction.payee == 'Corner Market' &&
            transaction.date == CivilDate(2024, 3, 2),
      );
      expect(pulled.amount, const Money(-4275));
      expect(pulled.lines.single.category, 'cat-groceries');
      expect(pulled.lines.single.reviewed, isFalse);
      expect(
        state.assigned('cat-meals', CalendarMonth(2024, 1)),
        const Money(2500),
      );
      expect(
        state.reviewQueue.any((line) => line.transaction.id == pulled.id),
        isTrue,
      );

      expect(
        engine.execute(
          RevertGroup(groupId: commit.groupId, includeDependents: true),
        ),
        isA<Accepted>(),
      );
      expect(
        engine.state.transactions.any(
          (transaction) =>
              transaction.payee == 'Corner Market' &&
              transaction.date == CivilDate(2024, 3, 2),
        ),
        isFalse,
      );
      expect(
        engine.state.assigned('cat-meals', CalendarMonth(2024, 1)),
        Money.zero,
      );
    });

    test('leaves an ignored item out', () {
      final comparison = _compare();
      final decisions = {
        for (final item in comparison.pullItems)
          item.pull!.key: const PullDecision.ignore('Already handled'),
      };
      final batch = pullBatch(comparison: comparison, decisions: decisions);

      expect(batch.transactions, isEmpty);
      expect(batch.assignments, isEmpty);
    });
  });
}
