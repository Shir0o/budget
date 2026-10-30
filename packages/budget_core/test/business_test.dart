import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

final _jan5 = CivilDate(2026, 1, 5);
final _jan20 = CivilDate(2026, 1, 20);
final _feb1 = CivilDate(2026, 2, 1);
final _mar1 = CivilDate(2026, 3, 1);
final _old = CivilDate(2025, 12, 31);

List<Event> _accepted(CommandResult result) {
  expect(result, isA<Accepted>());
  return (result as Accepted).events;
}

Rejection _rejected(CommandResult result) {
  expect(result, isA<Rejected>());
  return (result as Rejected).reason;
}

/// A synthetic budget named Studio, with Checking starting at 5,000.00 and
/// an Advertising Category for expense lines to go in.
final class _Budget {
  _Budget() {
    run(const CreateBudget(name: 'Studio'));
    run(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(500000),
        asOf: _jan5,
      ),
    );
    checking = state.accounts.single.id;
    final group =
        run(const CreateCategoryGroup(name: 'Everyday'))
                .single
                .payload['categoryGroupId']
            as String;
    category =
        run(CreateCategory(groupId: group, name: 'Advertising'))
                .single
                .payload['categoryId']
            as String;
  }

  final log = InMemoryEventLog();
  late final String checking;
  late final String category;

  BudgetEngine engine([Actor actor = Actor.userAndroid]) =>
      BudgetEngine(log: log, deviceId: 'device-a', actor: actor);

  BudgetState get state => BudgetState.replay(log.readAll());

  CommandResult execute(Command command, [Actor actor = Actor.userAndroid]) =>
      engine(actor).execute(command);

  List<Event> run(Command command, [Actor actor = Actor.userAndroid]) =>
      _accepted(execute(command, actor));

  /// A Reviewed outflow line under [tag].
  String spend(
    int cents, {
    required String tag,
    String payee = 'Paper & Co.',
    CivilDate? date,
    String? recipient,
    String memo = '',
  }) =>
      run(
            CreateTransaction(
              accountId: checking,
              date: date ?? _jan20,
              amount: Money(-cents),
              payee: payee,
              lines: [
                LineInput(
                  amount: Money(-cents),
                  category: category,
                  business: Business(tag),
                  recipient: recipient,
                  memo: memo,
                ),
              ],
            ),
          ).single.payload['transactionId']
          as String;

  /// An Unreviewed outflow with no Category and no business status.
  String spendUnreviewed(
    int cents, {
    String payee = 'Mystery charge',
    CivilDate? date,
    Actor actor = Actor.userAndroid,
  }) =>
      run(
            CreateTransaction(
              accountId: checking,
              date: date ?? _mar1,
              amount: Money(-cents),
              payee: payee,
              lines: [LineInput(amount: Money(-cents))],
            ),
            actor,
          ).single.payload['transactionId']
          as String;

  /// Reviewed self-employment income in Checking.
  String income(int cents, {CivilDate? date}) =>
      run(
            CreateTransaction(
              accountId: checking,
              date: date ?? _jan5,
              amount: Money(cents),
              payee: 'Client',
              lines: [
                LineInput(
                  amount: Money(cents),
                  category: readyToAssignCategory,
                  business: const Business('Self-employment income'),
                ),
              ],
            ),
          ).single.payload['transactionId']
          as String;
}

void main() {
  group('preset Business Tags', () {
    test('are the 19 from ticket 04, with their lines and rules', () {
      expect(presetBusinessTags, hasLength(19));
      expect(presetBusinessTags.map((tag) => tag.name), [
        'Self-employment income',
        'Advertising',
        'Car & truck',
        'Contract labor',
        'Insurance',
        'Legal & professional',
        'Office expense',
        'Rent / lease',
        'Supplies',
        'Taxes & licenses',
        'Travel',
        'Meals',
        'Utilities',
        'Conferences & education',
        'Software & subscriptions',
        'Phone & internet',
        'Gifts',
        'Bank & payment fees',
        'Other business expense',
      ]);

      final byName = {for (final tag in presetBusinessTags) tag.name: tag};
      expect(byName['Self-employment income']!.line, scheduleCIncomeLine);
      expect(byName['Self-employment income']!.isIncome, isTrue);
      expect(byName['Advertising']!.line, '8');
      expect(byName['Car & truck']!.line, '9');
      expect(byName['Contract labor']!.line, '11');
      expect(byName['Insurance']!.line, '15');
      expect(byName['Legal & professional']!.line, '17');
      expect(byName['Office expense']!.line, '18');
      expect(byName['Rent / lease']!.line, '20b');
      expect(byName['Supplies']!.line, '22');
      expect(byName['Taxes & licenses']!.line, '23');
      expect(byName['Travel']!.line, '24a');
      expect(byName['Meals']!.line, '24b');
      expect(byName['Utilities']!.line, '25');
      for (final name in [
        'Conferences & education',
        'Software & subscriptions',
        'Phone & internet',
        'Gifts',
        'Bank & payment fees',
        'Other business expense',
      ]) {
        expect(byName[name]!.line, '27a (other)', reason: name);
      }

      expect((byName['Meals']!.rule as PercentDeduction).percent, 50);
      expect(byName['Meals']!.rule.label, '50%');
      expect(byName['Car & truck']!.rule, isA<BusinessUseDeduction>());
      expect(byName['Phone & internet']!.rule, isA<BusinessUseDeduction>());
      final cap = byName['Gifts']!.rule as PerRecipientCapDeduction;
      expect(cap.cap, const Money(2500));
      expect(cap.label, 'Up to \$25.00 per recipient');
      expect(byName['Supplies']!.rule, isA<FullDeduction>());
      expect(byName['Supplies']!.rule.label, '100%');
    });
  });

  group('custom Business Tags', () {
    test('are an Event with a name, a Schedule C line and a rule', () {
      final budget = _Budget();

      final events = budget.run(
        const CreateBusinessTag(
          name: ' Studio rent ',
          line: '20b',
          rule: FullDeduction(),
        ),
      );

      expect(events.single.type, EventType.businessTagCreated);
      expect(events.single.payload, {
        'name': 'Studio rent',
        'line': '20b',
        'rule': {'kind': 'full'},
      });
      final tag = budget.state.businessTag('Studio rent')!;
      expect(tag.line, '20b');
      expect(tag.custom, isTrue);
      expect(budget.state.businessTags.last.name, 'Studio rent');

      budget.spend(50000, tag: 'Studio rent');
      final report = budget.state.businessReport(2026);
      expect(report.rows.single.deductible, const Money(50000));
    });

    test('reject a taken name, a blank line and a bad rule', () {
      final budget = _Budget();

      expect(
        _rejected(
          budget.execute(
            const CreateBusinessTag(
              name: 'meals',
              line: '8',
              rule: FullDeduction(),
            ),
          ),
        ),
        Rejection.businessTagExists,
      );
      expect(
        _rejected(
          budget.execute(
            const CreateBusinessTag(
              name: 'Studio rent',
              line: ' ',
              rule: FullDeduction(),
            ),
          ),
        ),
        Rejection.businessLineRequired,
      );
      expect(
        _rejected(
          budget.execute(
            const CreateBusinessTag(
              name: '  ',
              line: '8',
              rule: FullDeduction(),
            ),
          ),
        ),
        Rejection.nameRequired,
      );
      expect(
        _rejected(
          budget.execute(
            const CreateBusinessTag(
              name: 'Commissions',
              line: '8',
              rule: PercentDeduction(0),
            ),
          ),
        ),
        Rejection.percentOutOfRange,
      );
      expect(
        _rejected(
          budget.execute(
            const CreateBusinessTag(
              name: 'Swag',
              line: '27a (other)',
              rule: PerRecipientCapDeduction(Money.zero),
            ),
          ),
        ),
        Rejection.capMustBePositive,
      );
    });

    test('a line with a tag this version does not know is left out', () {
      final budget = _Budget();
      budget.spend(1000, tag: 'Mystery');

      expect(budget.state.businessReport(2026).rows, isEmpty);
    });
  });

  group('business-use %', () {
    test('is set per tag per tax year, and missing warns', () {
      final budget = _Budget();
      budget.spend(10000, tag: 'Car & truck', date: _jan5);
      budget.spend(10000, tag: 'Car & truck', date: _old);

      expect(budget.state.businessUse('Car & truck', 2026), isNull);
      final before = budget.state.businessReport(2026);
      expect(before.rows.single.gross, const Money(10000));
      expect(before.rows.single.deductible, Money.zero);
      final warning = before.warnings.whereType<MissingBusinessUse>().single;
      expect(warning.tag.name, 'Car & truck');

      budget.run(
        const SetBusinessUse(tag: 'Car & truck', year: 2026, percent: 80),
      );
      budget.run(
        const SetBusinessUse(tag: 'Car & truck', year: 2025, percent: 40),
      );

      expect(budget.state.businessUse('Car & truck', 2026), 80);
      expect(
        budget.state.businessReport(2026).rows.single.deductible,
        const Money(8000),
      );
      expect(
        budget.state.businessReport(2025).rows.single.deductible,
        const Money(4000),
      );
      expect(budget.state.businessReport(2026).warnings, isEmpty);
    });

    test('rejects an unknown tag, a percentage out of range and no change', () {
      final budget = _Budget();

      expect(
        _rejected(
          budget.execute(
            const SetBusinessUse(tag: 'Nope', year: 2026, percent: 50),
          ),
        ),
        Rejection.unknownBusinessTag,
      );
      expect(
        _rejected(
          budget.execute(
            const SetBusinessUse(tag: 'Meals', year: 2026, percent: 101),
          ),
        ),
        Rejection.percentOutOfRange,
      );

      budget.run(
        const SetBusinessUse(tag: 'Phone & internet', year: 2026, percent: 60),
      );
      expect(
        _rejected(
          budget.execute(
            const SetBusinessUse(
              tag: 'Phone & internet',
              year: 2026,
              percent: 60,
            ),
          ),
        ),
        Rejection.noChange,
      );
      expect(budget.state.businessUse('Phone & internet', 2026), 60);
    });

    test('shows in Change History and reverts to unset', () {
      final budget = _Budget();
      final events = budget.run(
        const SetBusinessUse(tag: 'Meals', year: 2026, percent: 60),
      );

      final entry = budget.engine().history.entry(events.single.groupId)!;
      expect(entry.summary, 'Set Business use % for 2026 of Meals');
      expect(entry.canRevert, isTrue);

      budget.run(RevertGroup(groupId: entry.groupId));
      expect(budget.state.businessUse('Meals', 2026), isNull);
    });
  });

  group('the business report', () {
    test('deducts meals at 50%, rounded toward zero', () {
      final budget = _Budget();
      budget.spend(4821, tag: 'Meals', memo: 'Lunch');

      final report = budget.state.businessReport(2026);

      final row = report.rows.single;
      expect(row.tag.name, 'Meals');
      expect(row.tag.line, '24b');
      expect(row.gross, const Money(4821));
      expect(row.deductible, const Money(2410));
      expect(report.lines.single.gross, const Money(4821));
      expect(report.lines.single.deductible, const Money(2410));
      expect(report.income, Money.zero);
      expect(report.deductibleExpenses, const Money(2410));
      expect(report.net, const Money(-2410));
      expect(report.warnings, isEmpty);
      expect(report.year, 2026);
    });

    test('caps gifts at \$25 per recipient per year, in date order', () {
      final budget = _Budget();
      budget.spend(3000, tag: giftsTag, date: _jan20, recipient: 'Dana');
      // Entered later but dated earlier, so it comes first and takes 10.00
      // of Dana's cap.
      budget.spend(1000, tag: giftsTag, date: _jan5, recipient: ' dana ');
      budget.spend(2500, tag: giftsTag, date: _feb1, recipient: 'Sam');

      final report = budget.state.businessReport(2026);

      expect(report.lines.map((line) => line.transaction.date), [
        _jan5,
        _jan20,
        _feb1,
      ]);
      expect(report.lines.map((line) => line.deductible), [
        const Money(1000),
        const Money(1500),
        const Money(2500),
      ]);
      expect(report.rows.single.gross, const Money(6500));
      expect(report.rows.single.deductible, const Money(5000));
      expect(report.warnings, isEmpty);
    });

    test('leaves a gift without a recipient at 0.00 and warns', () {
      final budget = _Budget();
      budget.spend(2000, tag: giftsTag, payee: 'Florist');

      final report = budget.state.businessReport(2026);

      expect(report.rows.single.gross, const Money(2000));
      expect(report.rows.single.deductible, Money.zero);
      final gift = report.warnings.whereType<GiftWithoutRecipient>().single;
      expect(gift.line.transaction.payee, 'Florist');
      expect(report.warnings.whereType<UnreviewedLines>().single.count, 1);
    });

    test('warns about Unreviewed lines dated in the year, not others', () {
      final budget = _Budget();
      budget.spend(1000, tag: 'Meals', date: _jan5);
      budget.spendUnreviewed(1200, date: _mar1);
      budget.spendUnreviewed(900, date: _old);
      // A transfer line skips business status, so it never warns.
      final savings =
          budget
                  .run(
                    AddAccount(
                      name: 'Savings',
                      type: AccountType.savings,
                      startingBalance: Money.zero,
                      asOf: _jan5,
                    ),
                  )
                  .first
                  .payload['accountId']
              as String;
      budget.run(
        CreateTransfer(
          fromAccountId: budget.checking,
          toAccountId: savings,
          amount: const Money(10000),
          date: _feb1,
        ),
        const Actor.fromValue('bank-sync'),
      );

      final report = budget.state.businessReport(2026);
      expect(report.warnings.whereType<UnreviewedLines>().single.count, 1);
      expect(report.lines.single.transaction.payee, 'Paper & Co.');
    });

    test('totals income, deductible expenses and net, in tag order', () {
      final budget = _Budget();
      budget.income(150000);
      budget.spend(
        4821,
        tag: 'Meals',
        memo: 'Lunch with a client',
        date: _jan20,
      );
      budget.spend(1000, tag: 'Advertising', date: _feb1);

      final report = budget.state.businessReport(2026);

      expect(report.rows.map((row) => row.tag.name), [
        'Self-employment income',
        'Advertising',
        'Meals',
      ]);
      expect(report.income, const Money(150000));
      expect(report.deductibleExpenses, const Money(3410));
      expect(report.net, const Money(146590));

      final lunch = report.lines.singleWhere(
        (line) => line.tag.name == 'Meals',
      );
      expect(lunch.transaction.date, _jan20);
      expect(lunch.transaction.payee, 'Paper & Co.');
      expect(lunch.account, 'Checking');
      expect(lunch.line.memo, 'Lunch with a client');
      expect(lunch.line.amount, const Money(-4821));
      expect(lunch.gross, const Money(4821));
      expect(lunch.deductible, const Money(2410));
    });

    test('leaves out another tax year', () {
      final budget = _Budget();
      budget.spend(1000, tag: 'Meals', date: _old);
      budget.income(250000, date: _old);

      final report = budget.state.businessReport(2026);
      expect(report.rows, isEmpty);
      expect(report.lines, isEmpty);
      expect(report.income, Money.zero);
      expect(report.net, Money.zero);
    });
  });

  group('business CSV', () {
    _Budget fixture() {
      final budget = _Budget();
      budget.income(150000);
      budget.spend(
        4821,
        tag: 'Meals',
        memo: 'Lunch with a client',
        date: _jan20,
      );
      budget.spend(
        3000,
        tag: giftsTag,
        payee: 'Florist',
        recipient: 'Dana',
        date: _feb1,
      );
      budget.spend(1000, tag: 'Meals', date: _old);
      return budget;
    }

    test('summary rows, totals and the footer', () {
      final report = fixture().state.businessReport(2026);

      expect(
        businessSummaryCsv(report),
        'Business Tag,Schedule C line,Gross,Rule,Deductible\r\n'
        'Self-employment income,Line 1 (gross receipts),1500.00,100%,1500.00\r\n'
        'Meals,24b,48.21,50%,24.10\r\n'
        'Gifts,27a (other),30.00,Up to \$25.00 per recipient,25.00\r\n'
        '\r\n'
        'Total self-employment income,,1500.00,,1500.00\r\n'
        'Total deductible expenses,,78.21,,49.10\r\n'
        'Net,,1450.90,,\r\n'
        '\r\n'
        'Records only. Not tax advice.\r\n',
      );
    });

    test('detail rows and the footer', () {
      final report = fixture().state.businessReport(2026);

      expect(
        businessDetailCsv(report),
        'Date,Payee,Account,Amount,Memo,Business Tag,Recipient,Deductible\r\n'
        '2026-01-05,Client,Checking,1500.00,,Self-employment income,,1500.00\r\n'
        '2026-01-20,Paper & Co.,Checking,-48.21,Lunch with a client,Meals,,24.10\r\n'
        '2026-02-01,Florist,Checking,-30.00,,Gifts,Dana,25.00\r\n'
        '\r\n'
        'Records only. Not tax advice.\r\n',
      );
    });

    test('is the header, the footer and nothing else in an empty year', () {
      final budget = _Budget();

      expect(
        businessSummaryCsv(budget.state.businessReport(2026)),
        'Business Tag,Schedule C line,Gross,Rule,Deductible\r\n'
        '\r\n'
        'Total self-employment income,,0.00,,0.00\r\n'
        'Total deductible expenses,,0.00,,0.00\r\n'
        'Net,,0.00,,\r\n'
        '\r\n'
        'Records only. Not tax advice.\r\n',
      );
      expect(
        businessDetailCsv(budget.state.businessReport(2026)),
        'Date,Payee,Account,Amount,Memo,Business Tag,Recipient,Deductible\r\n'
        '\r\n'
        'Records only. Not tax advice.\r\n',
      );
    });
  });
}
