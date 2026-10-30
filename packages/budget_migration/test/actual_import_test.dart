import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';
import 'package:test/test.dart';

import 'actual_fixture.dart';

final _today = CivilDate(2026, 10, 30);

final _zip = syntheticActualZip();
final _export = ActualExport.read(ActualZip.decode(_zip));

ActualExport _read() => ActualExport.read(ActualZip.decode(_zip));

ImportPlan _plan({List<TagMapping>? tags}) => buildImportPlan(
  export: _export,
  tagMappings: tags ?? defaultTagMappings(_export),
  today: _today,
);

(BudgetEngine, InMemoryEventLog) _engine() {
  final log = InMemoryEventLog();
  final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  engine.execute(const CreateBudget(name: 'Home'));
  return (engine, log);
}

void main() {
  group('ActualExport', () {
    test(
      'reads accounts, groups, Categories and payees, skipping tombstones',
      () {
        final export = _read();

        expect(export.budgetName, 'Home');
        expect(export.accounts.map((a) => a.name), [
          'Everyday Checking',
          'Rainy Day Savings',
          'Travel Card',
          'Brokerage',
          'Old Checking',
        ]);
        expect(export.categoryGroups.map((g) => g.name), [
          'Income',
          'Bills',
          'Fun',
        ]);
        expect(export.categories.map((c) => c.name), [
          'Paycheck',
          'Rent',
          'Groceries',
          'Meals',
          'Old savings goal',
        ]);
        expect(export.payees.map((p) => p.name), contains('Corner Market'));
        expect(export.trackingBudget, isFalse);
        expect(export.rules, hasLength(3));
      },
    );

    test('keeps money in exact cents and dates as calendar dates', () {
      final export = _read();

      expect(export.accountBalancesCents, {
        'acct-checking': 493300,
        'acct-savings': 50000,
        'acct-card': 8500,
        'acct-brokerage': 100000,
        'acct-old': -1000,
      });
      final rent = export.transactions.singleWhere((t) => t.id == 'tx-rent');
      expect(rent.amountCents, -150000);
      expect(rent.date, CivilDate(2023, 2, 1));
      expect(rent.cleared, ClearedStatus.cleared);
    });

    test('resolves merged Categories and payees before importing', () {
      final export = _read();

      final merged = export.transactions.singleWhere(
        (t) => t.id == 'tx-merged',
      );
      expect(merged.categoryId, 'cat-groceries');
      expect(merged.payeeId, 'pay-store');
    });

    test('refuses a file that is not an Actual zip', () {
      expect(() => _read(), returnsNormally);
      expect(
        () => ActualZip.decode(syntheticBytes('not a zip')),
        throwsA(isA<ActualExportException>()),
      );
    });

    test('refuses a zip without db.sqlite', () {
      expect(
        () => ActualZip.decode(syntheticZip({'metadata.json': '{}'})),
        throwsA(isA<ActualExportException>()),
      );
    });
  });

  group('defaultTagMappings', () {
    test(
      'lists every #tag and used Category with counts and ticket 18 defaults',
      () {
        final mappings = defaultTagMappings(_export);

        final meals = mappings.singleWhere((m) => m.key == '#workMeals');
        expect(meals.source, TagSource.tag);
        expect(meals.count, 2);
        expect(meals.tag, 'Meals');
        expect(
          mappings.singleWhere((m) => m.key == '#workTravel').tag,
          'Travel',
        );

        final groceries = mappings.singleWhere(
          (m) => m.label == 'Groceries' && m.source == TagSource.category,
        );
        expect(groceries.count, 6);
        expect(groceries.tag, isNull);
      },
    );
  });

  group('ImportPlan', () {
    test('maps accounts: off-budget to tracking and closed stays listed', () {
      final plan = _plan();
      final byActual = {for (final a in plan.accounts) a.actualId: a};

      expect(byActual['acct-checking']!.type, AccountType.checking);
      expect(byActual['acct-savings']!.type, AccountType.savings);
      expect(byActual['acct-card']!.type, AccountType.creditCard);
      expect(byActual['acct-brokerage']!.type, AccountType.tracking);
      expect(byActual['acct-old']!.closed, isTrue);
      expect(plan.balanceMismatches, isEmpty);
    });

    test('derives a Card Payment Category for every card', () {
      final plan = _plan();
      final payments = plan.categories.where((c) => c.cardAccountId != null);

      expect(payments, hasLength(1));
      final payment = payments.single;
      expect(payment.name, 'Travel Card Payment');
      expect(payment.cardAccountId, 'actual-account-acct-card');
      expect(
        plan.categoryGroups.singleWhere((g) => g.id == payment.groupId).name,
        'Credit Card Payments',
      );
    });

    test('sends income to Ready to Assign and keeps its category name', () {
      final plan = _plan();
      final income = plan.transactions.singleWhere(
        (t) => t.id == 'actual-transaction-tx-income',
      );

      expect(income.lines.single.category, readyToAssignCategory);
      expect(income.importedCategory, 'Paycheck');
      expect(
        plan.categories.singleWhere((c) => c.name == 'Paycheck').income,
        isTrue,
      );
      expect(
        plan.toBatch().categories.any((c) => c.name == 'Paycheck'),
        isFalse,
      );
    });

    test('turns a split into one transaction with one line per child', () {
      final plan = _plan();
      final split = plan.transactions.singleWhere(
        (t) => t.id == 'actual-transaction-tx-split',
      );

      expect(split.amount, const Money(-9000));
      expect(split.lines, hasLength(2));
      expect(split.lines.map((l) => l.amount), [
        const Money(-5000),
        const Money(-4000),
      ]);
      expect(split.lines.map((l) => l.memo), ['half', 'rest']);
      expect(split.lines.map((l) => l.business), [
        const Business('Meals'),
        const Business('Meals'),
      ]);
    });

    test(
      'links both sides of every transfer and keeps the budget side Category',
      () {
        final plan = _plan();
        final transfers = plan.transactions.where(
          (t) => t.transferTransactionId != null,
        );

        expect(transfers, hasLength(6));
        final out = plan.transactions.singleWhere(
          (t) => t.id == 'actual-transaction-tx-transfer-out',
        );
        final into = plan.transactions.singleWhere(
          (t) => t.id == 'actual-transaction-tx-transfer-in',
        );
        expect(out.transferTransactionId, into.id);
        expect(into.transferTransactionId, out.id);
        expect(out.amount, -into.amount);
        expect(out.lines.single.category, isNull);

        final toTracking = plan.transactions.singleWhere(
          (t) => t.id == 'actual-transaction-tx-brokerage-out',
        );
        expect(toTracking.lines.single.category, 'actual-category-cat-rent');
        final fromTracking = plan.transactions.singleWhere(
          (t) => t.id == 'actual-transaction-tx-brokerage-in',
        );
        expect(fromTracking.lines.single.category, isNull);
      },
    );

    test('imports earlier years Reviewed and the current year Unreviewed', () {
      final plan = _plan();
      final current = plan.transactions.singleWhere(
        (t) => t.id == 'actual-transaction-tx-current',
      );
      final rent = plan.transactions.singleWhere(
        (t) => t.id == 'actual-transaction-tx-rent',
      );
      final starting = plan.transactions.singleWhere(
        (t) => t.id == 'actual-transaction-tx-open',
      );

      expect(current.lines.single.reviewed, isFalse);
      expect(current.lines.single.category, 'actual-category-cat-groceries');
      expect(current.lines.single.business, const Personal());
      expect(rent.lines.single.reviewed, isTrue);
      expect(rent.lines.single.business, const Personal());
      expect(starting.startingBalance, isTrue);
      expect(starting.lines.single.reviewed, isTrue);
      expect(starting.lines.single.category, readyToAssignCategory);
    });

    test('imports current-year transfers and Starting Balances Unreviewed', () {
      final export = ActualExport.read(
        ActualZip.decode(syntheticActualZip(extraRows: _visaRows)),
      );
      final plan = buildImportPlan(
        export: export,
        tagMappings: defaultTagMappings(export),
        today: _today,
      );
      ImportLine line(String id) => plan.transactions
          .singleWhere((t) => t.id == 'actual-transaction-$id')
          .lines
          .single;

      expect(line('tx-transfer-out').reviewed, isFalse);
      expect(line('tx-transfer-in').reviewed, isFalse);
      expect(line('tx-visa-open').reviewed, isFalse);
      // Earlier years stay Reviewed.
      expect(line('tx-open').reviewed, isTrue);
    });

    test('sends a line mapped to two tags back to Review', () {
      final plan = _plan();
      final conflict = plan.transactions.singleWhere(
        (t) => t.id == 'actual-transaction-tx-conflict',
      );

      expect(conflict.lines.single.business, isNull);
      expect(conflict.lines.single.reviewed, isFalse);
      expect(
        plan.warnings.any((warning) => warning.contains('more than one')),
        isTrue,
      );
    });

    test('imports Assignments as one amount per Category and month', () {
      final plan = _plan();

      expect(plan.assignments, hasLength(3));
      expect(
        [
          for (final assignment in plan.assignments)
            (assignment.month.toIso(), assignment.amount),
        ],
        [
          ('2026-09', const Money(150000)),
          ('2026-10', const Money(150000)),
          ('2026-10', const Money(25000)),
        ],
      );
      expect(
        plan.warnings.any((w) => w.contains('income Category Assignment')),
        isTrue,
      );
    });

    test('converts a monthly Schedule and lists the one it cannot', () {
      final plan = _plan();

      final schedule = plan.schedules.single;
      expect(schedule.payee, 'Landlord');
      expect(schedule.amount, const Money(-150000));
      expect(schedule.category, 'actual-category-cat-rent');
      expect(schedule.every, 1);
      expect(schedule.interval, TargetInterval.months);
      expect(schedule.nextDue, CivilDate(2026, 11, 1));
      expect(
        plan.warnings.any((w) => w.contains('Scheduled Transaction')),
        isTrue,
      );
    });

    test('turns #template lines into Targets where they parse', () {
      final plan = _plan();
      final byCategory = {
        for (final target in plan.targets) target.categoryId: target.target,
      };

      expect(
        byCategory['actual-category-cat-groceries']?.toJson(),
        RepeatingTarget(
          amount: Money(40000),
          every: 1,
          interval: TargetInterval.months,
          nextDue: CivilDate(2026, 10, 1),
        ).toJson(),
      );
      expect(
        byCategory['actual-category-cat-meals']?.toJson(),
        KeepAtLeastTarget(amount: Money(10000)).toJson(),
      );
      expect(
        byCategory['actual-category-cat-rent']?.toJson(),
        ByDateTarget(
          amount: Money(150000),
          date: CivilDate(2026, 12, 31),
        ).toJson(),
      );
      expect(plan.warnings.any((w) => w.contains('#template')), isTrue);
    });

    test('lists rules and warns about what the app cannot mirror', () {
      final plan = _plan();
      final report = plan.report;

      expect(report.rules, 3);
      expect(report.accounts, 5);
      expect(report.transactions, 15);
      expect(report.incomeCategories, 1);
      expect(report.balancesMatch, isTrue);
      // The current year's two non-transfer lines on budget accounts: what
      // Review lists (asserted against reviewQueue below).
      expect(report.unreviewedLines, 2);
      expect(report.lastTransactionDate, CivilDate(2026, 10, 1));
      for (final expected in [
        '3 rules',
        'roll-over',
        'hidden Category',
        'closed',
        'zero-amount',
      ]) {
        expect(
          plan.warnings.any((warning) => warning.contains(expected)),
          isTrue,
          reason: 'No warning about $expected',
        );
      }
    });
  });

  group('commitImport', () {
    test('writes the whole import as one group with actor import', () {
      final (engine, log) = _engine();
      final before = engine.events.length;
      final plan = _plan();

      final commit = commitImport(engine, plan);

      final added = log.readAll().skip(before).toList();
      expect(added, isNotEmpty);
      expect(added.map((event) => event.groupId).toSet(), {commit.groupId});
      expect(added.map((event) => event.actor.value).toSet(), {'import'});
      expect(commit.accounts, 5);
      expect(commit.transactions, 15);
      expect(commit.assignments, 3);
      expect(commit.schedules, 1);
    });

    test('every account balance equals Actual to the cent', () {
      final (engine, _) = _engine();
      commitImport(engine, _plan());
      final state = engine.state;

      for (final account in _export.accounts) {
        final id = 'actual-account-${account.id}';
        expect(
          state.balance(id),
          Money(_export.accountBalancesCents[account.id]!),
          reason: account.name,
        );
      }
      expect(state.accounts, hasLength(5));
      expect(
        state.account('actual-account-acct-brokerage')!.type,
        AccountType.tracking,
      );
    });

    test(
      'projects income, Assignments, Schedules, Targets and the card payment',
      () {
        final (engine, _) = _engine();
        final plan = _plan();
        commitImport(engine, plan);
        final state = engine.state;

        expect(state.category('actual-category-cat-income'), isNull);
        final income = state.transactions.singleWhere(
          (t) => t.importedCategory == 'Paycheck',
        );
        expect(income.lines.single.category, readyToAssignCategory);
        expect(income.lines.single.reviewed, isTrue);

        expect(
          state.assigned('actual-category-cat-rent', CalendarMonth(2026, 9)),
          const Money(150000),
        );
        expect(
          state.assigned(
            'actual-category-cat-groceries',
            CalendarMonth(2026, 10),
          ),
          const Money(25000),
        );
        expect(
          state.assigned('actual-category-cat-rent', CalendarMonth(2023, 3)),
          Money.zero,
        );

        expect(state.schedules, hasLength(1));
        expect(state.schedules.single.payee, 'Landlord');
        expect(
          state.target('actual-category-cat-groceries')?.toJson(),
          RepeatingTarget(
            amount: Money(40000),
            every: 1,
            interval: TargetInterval.months,
            nextDue: CivilDate(2026, 10, 1),
          ).toJson(),
        );
        final cardPayment = state.cardPaymentCategory(
          'actual-account-acct-card',
        );
        expect(cardPayment?.name, 'Travel Card Payment');

        expect(state.reviewQueue, hasLength(2));
        expect(plan.report.unreviewedLines, state.reviewQueue.length);
      },
    );

    test('ticket 07 example 6: imported card debt starts unfunded', () {
      final export = ActualExport.read(
        ActualZip.decode(syntheticActualZip(extraRows: _visaRows)),
      );
      final plan = buildImportPlan(
        export: export,
        tagMappings: defaultTagMappings(export),
        today: _today,
      );
      final (withoutVisa, _) = _engine();
      commitImport(withoutVisa, _plan());
      final (engine, _) = _engine();

      commitImport(engine, plan);

      final state = engine.state;
      const visa = 'actual-account-acct-visa';
      final month = CalendarMonth(2026, 10);
      final opening = state.register(visa).single;
      expect(opening.startingBalance, isTrue);
      expect(opening.lines.single.category, isNull);
      expect(state.balance(visa), const Money(-200000));
      expect(
        state.available(state.cardPaymentCategory(visa)!.id, month),
        Money.zero,
      );
      expect(state.unfundedDebt(visa, month), const Money(200000));
      expect(
        state.readyToAssign(month),
        withoutVisa.state.readyToAssign(month),
      );
    });

    test('reverts the whole import as one group', () {
      final (engine, _) = _engine();
      final commit = commitImport(engine, _plan());

      final result = engine.execute(
        RevertGroup(groupId: commit.groupId, includeDependents: true),
      );

      expect(result, isA<Accepted>());
      final state = engine.state;
      expect(state.accounts, isEmpty);
      expect(state.transactions, isEmpty);
      expect(state.categoryGroups, isEmpty);
      expect(state.schedules, isEmpty);
      expect(state.category('actual-category-cat-rent'), isNull);
      expect(
        state.assigned('actual-category-cat-rent', CalendarMonth(2026, 9)),
        Money.zero,
      );
    });

    test('blocks the commit when one account is off by a cent', () {
      final (engine, log) = _engine();
      final before = log.readAll().length;
      final plan = _plan();
      final batch = plan.toBatch();
      final tampered = ImportBatch(
        accounts: batch.accounts,
        categoryGroups: batch.categoryGroups,
        categories: batch.categories,
        transactions: batch.transactions,
        assignments: batch.assignments,
        schedules: batch.schedules,
        targets: batch.targets,
        expectedBalancesCents: {
          ...batch.expectedBalancesCents,
          'actual-account-acct-checking': 493301,
        },
      );

      final result = engine.execute(CommitImport(tampered));

      expect(result, isA<Rejected>());
      expect((result as Rejected).reason, Rejection.importBalanceMismatch);
      expect(log.readAll(), hasLength(before));
      expect(engine.state.accounts, isEmpty);
    });
  });
}

/// A Visa opened in the current year with $2,000 of existing debt.
const _visaRows = '''
  INSERT INTO accounts VALUES
    ('acct-visa', 'Visa', 0, 0, 'credit', 0);
  INSERT INTO transactions VALUES
    ('tx-visa-open', 'acct-visa', NULL, -200000, NULL, '',
     20261001, 'cleared', 1, 0, 0, NULL, NULL, 1, NULL, NULL, NULL, 0);
''';
