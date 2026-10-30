part of 'budget_state.dart';

// Business Tags and the yearly business report (ticket 04, ticket 09). A
// Business Tag is independent of a Category: it marks one line of a
// transaction as reportable self-employment income or expense, carries its
// Schedule C line, and says how much of it is deductible. The app produces
// records, not tax advice.

/// The Schedule C line self-employment income goes on.
const scheduleCIncomeLine = 'Line 1 (gross receipts)';

/// The Schedule C lines a Business Tag may pick (ticket 04).
const scheduleCLines = [
  scheduleCIncomeLine,
  '8',
  '9',
  '11',
  '15',
  '17',
  '18',
  '20b',
  '22',
  '23',
  '24a',
  '24b',
  '25',
  '27a (other)',
];

/// What the report footer and both CSV files end with (ticket 09).
const businessReportFooter = 'Records only. Not tax advice.';

/// How much of a Business Tag's lines is deductible (ticket 04).
sealed class DeductionRule {
  const DeductionRule();

  /// Restores a rule from an Event's stored form.
  static DeductionRule fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'full' => const FullDeduction(),
        'percent' => PercentDeduction(json['percent'] as int),
        'businessUse' => const BusinessUseDeduction(),
        'perRecipientCap' => PerRecipientCapDeduction(
          Money(json['capCents'] as int),
        ),
        final kind => throw FormatException('Unknown deduction rule', kind),
      };

  /// The rule as an Event stores it.
  Map<String, Object?> toJson();

  /// As the report writes it: `100%`, `50%`, `Business use %` or
  /// `Up to $25.00 per recipient`.
  String get label;
}

/// All of a line is deductible.
final class FullDeduction extends DeductionRule {
  const FullDeduction();

  @override
  Map<String, Object?> toJson() => {'kind': 'full'};

  @override
  String get label => '100%';
}

/// A fixed percentage, such as meals at 50%.
final class PercentDeduction extends DeductionRule {
  const PercentDeduction(this.percent);

  /// 1 to 100.
  final int percent;

  @override
  Map<String, Object?> toJson() => {'kind': 'percent', 'percent': percent};

  @override
  String get label => '$percent%';
}

/// The business-use % a person sets for the tag and tax year.
final class BusinessUseDeduction extends DeductionRule {
  const BusinessUseDeduction();

  @override
  Map<String, Object?> toJson() => {'kind': 'businessUse'};

  @override
  String get label => 'Business use %';
}

/// Deductible up to [cap] per recipient per tax year, applied in date order.
/// Every gift line needs a recipient (ticket 09).
final class PerRecipientCapDeduction extends DeductionRule {
  const PerRecipientCapDeduction(this.cap);

  final Money cap;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'perRecipientCap',
    'capCents': cap.cents,
  };

  @override
  String get label => 'Up to ${cap.formatDollars()} per recipient';
}

/// A label marking a line as reportable self-employment income or expense
/// (ticket 04). It is independent of the line's Category.
final class BusinessTag {
  const BusinessTag({
    required this.name,
    required this.line,
    required this.rule,
    this.custom = false,
  });

  /// Restores a custom tag from its [toJson].
  static BusinessTag fromJson(Map<String, Object?> json) => BusinessTag(
    name: json['name'] as String,
    line: json['line'] as String,
    rule: DeductionRule.fromJson((json['rule'] as Map).cast<String, Object?>()),
    custom: true,
  );

  final String name;

  /// The Schedule C line it reports on, one of [scheduleCLines].
  final String line;
  final DeductionRule rule;

  /// Whether a person added it. The 19 presets ship with the app.
  final bool custom;

  /// Self-employment income is money in, not an expense.
  bool get isIncome => line == scheduleCIncomeLine;

  Map<String, Object?> toJson() => {
    'name': name,
    'line': line,
    'rule': rule.toJson(),
  };
}

/// The 19 preset Business Tags (ticket 04), in report order.
const presetBusinessTags = [
  BusinessTag(
    name: 'Self-employment income',
    line: scheduleCIncomeLine,
    rule: FullDeduction(),
  ),
  BusinessTag(name: 'Advertising', line: '8', rule: FullDeduction()),
  BusinessTag(name: 'Car & truck', line: '9', rule: BusinessUseDeduction()),
  BusinessTag(name: 'Contract labor', line: '11', rule: FullDeduction()),
  BusinessTag(name: 'Insurance', line: '15', rule: FullDeduction()),
  BusinessTag(name: 'Legal & professional', line: '17', rule: FullDeduction()),
  BusinessTag(name: 'Office expense', line: '18', rule: FullDeduction()),
  BusinessTag(name: 'Rent / lease', line: '20b', rule: FullDeduction()),
  BusinessTag(name: 'Supplies', line: '22', rule: FullDeduction()),
  BusinessTag(name: 'Taxes & licenses', line: '23', rule: FullDeduction()),
  BusinessTag(name: 'Travel', line: '24a', rule: FullDeduction()),
  BusinessTag(name: 'Meals', line: '24b', rule: PercentDeduction(50)),
  BusinessTag(name: 'Utilities', line: '25', rule: FullDeduction()),
  BusinessTag(
    name: 'Conferences & education',
    line: '27a (other)',
    rule: FullDeduction(),
  ),
  BusinessTag(
    name: 'Software & subscriptions',
    line: '27a (other)',
    rule: FullDeduction(),
  ),
  BusinessTag(
    name: 'Phone & internet',
    line: '27a (other)',
    rule: BusinessUseDeduction(),
  ),
  BusinessTag(
    name: giftsTag,
    line: '27a (other)',
    rule: PerRecipientCapDeduction(Money(2500)),
  ),
  BusinessTag(
    name: 'Bank & payment fees',
    line: '27a (other)',
    rule: FullDeduction(),
  ),
  BusinessTag(
    name: 'Other business expense',
    line: '27a (other)',
    rule: FullDeduction(),
  ),
];

/// One tagged transaction line in a Business report's detail (ticket 09).
final class BusinessLine {
  const BusinessLine({
    required this.transaction,
    required this.line,
    required this.tag,
    required this.account,
    required this.deductible,
  });

  final Transaction transaction;
  final TransactionLine line;
  final BusinessTag tag;

  /// The account's name.
  final String account;

  /// What the line deducts after its rule, business-use % and the gift cap
  /// have been applied. 0.00 when the report can't apply the rule.
  final Money deductible;

  /// The amount before its rule: income as it arrived, an expense without
  /// its minus sign.
  Money get gross => tag.isIncome ? line.amount : -line.amount;
}

/// One Business Tag's year: the gross amount it covers and what is
/// deductible.
final class BusinessSummaryRow {
  const BusinessSummaryRow({
    required this.tag,
    required this.gross,
    required this.deductible,
  });

  final BusinessTag tag;
  final Money gross;
  final Money deductible;
}

/// Something the person should fix before relying on a Business report
/// (ticket 09).
sealed class BusinessWarning {
  const BusinessWarning();
}

/// Lines dated in the tax year are still Unreviewed.
final class UnreviewedLines extends BusinessWarning {
  const UnreviewedLines(this.count);

  final int count;
}

/// [tag] deducts by business use, but no percentage is set for the year.
final class MissingBusinessUse extends BusinessWarning {
  const MissingBusinessUse(this.tag);

  final BusinessTag tag;
}

/// A gift line has no recipient, so the $25 cap can't be applied to it.
final class GiftWithoutRecipient extends BusinessWarning {
  const GiftWithoutRecipient(this.line);

  final BusinessLine line;
}

/// One tax year's business report (ticket 09): a summary row per Business
/// Tag, every tagged line in date order, the warnings, and the totals.
/// One tax year is one calendar year.
final class BusinessReport {
  const BusinessReport({
    required this.year,
    required this.rows,
    required this.lines,
    required this.warnings,
    required this.income,
    required this.deductibleExpenses,
  });

  final int year;
  final List<BusinessSummaryRow> rows;
  final List<BusinessLine> lines;
  final List<BusinessWarning> warnings;

  /// Total self-employment income, before deductions.
  final Money income;

  /// Total deductible expenses.
  final Money deductibleExpenses;

  Money get net => income - deductibleExpenses;

  bool get hasWarnings => warnings.isNotEmpty;
}

extension BusinessQueries on BudgetState {
  /// The 19 presets, then custom tags in the order they were added.
  List<BusinessTag> get businessTags =>
      List.unmodifiable([...presetBusinessTags, ..._customBusinessTags.values]);

  /// A preset or custom tag by its exact name.
  BusinessTag? businessTag(String name) {
    for (final tag in presetBusinessTags) {
      if (tag.name == name) return tag;
    }
    return _customBusinessTags[name];
  }

  /// [tag]'s business-use % for [year], or null when it isn't set.
  int? businessUse(String tag, int year) => _businessUse[tag]?[year];

  /// Every business-use % set, by tag, then tax year, for the state export.
  Map<String, Map<int, int>> get businessUsePercentages => {
    for (final MapEntry(key: tag, value: byYear) in _businessUse.entries)
      tag: Map.unmodifiable(byYear),
  };

  /// The Business report for [year].
  BusinessReport businessReport(int year) {
    final ordered =
        [
          for (final (position, transaction) in _transactions.values.indexed)
            if (!transaction.isTransfer && transaction.date.year == year)
              (position, transaction),
        ]..sort((a, b) {
          final byDate = a.$2.date.compareTo(b.$2.date);
          return byDate != 0 ? byDate : a.$1 - b.$1;
        });

    final lines = <BusinessLine>[];
    final missingUse = <String>[];
    final giftsWithoutRecipient = <BusinessLine>[];
    // Deductible gifts already counted this year, by lower-cased recipient.
    final giftUsed = <String, int>{};

    for (final (_, transaction) in ordered) {
      final account = _accounts[transaction.accountId]?.name ?? '';
      for (final line in transaction.lines) {
        final business = line.business;
        if (business is! Business) continue;
        final tag = businessTag(business.tag);
        // A tag this version doesn't know has no line or rule to report.
        if (tag == null) continue;
        final gross = (tag.isIncome ? line.amount : -line.amount).cents;
        final rule = tag.rule;
        var deductible = 0;
        if (rule is FullDeduction) {
          deductible = gross;
        } else if (rule is PercentDeduction) {
          deductible = _percentOf(gross, rule.percent);
        } else if (rule is BusinessUseDeduction) {
          final percent = businessUse(tag.name, year);
          if (percent == null) {
            if (!missingUse.contains(tag.name)) missingUse.add(tag.name);
          } else {
            deductible = _percentOf(gross, percent);
          }
        } else if (rule is PerRecipientCapDeduction) {
          // A gift without a recipient can't be capped, and a refund isn't
          // a gift, so both deduct nothing.
          final recipient = line.recipient?.trim() ?? '';
          if (recipient.isNotEmpty && gross > 0) {
            final key = recipient.toLowerCase();
            final room = rule.cap.cents - (giftUsed[key] ?? 0);
            deductible = gross < room ? gross : room;
            if (deductible > 0) {
              giftUsed[key] = (giftUsed[key] ?? 0) + deductible;
            }
          }
        }
        final detail = BusinessLine(
          transaction: transaction,
          line: line,
          tag: tag,
          account: account,
          deductible: Money(deductible),
        );
        lines.add(detail);
        if (rule is PerRecipientCapDeduction &&
            (line.recipient?.trim() ?? '').isEmpty) {
          giftsWithoutRecipient.add(detail);
        }
      }
    }

    final rows = <BusinessSummaryRow>[];
    var income = Money.zero;
    var deductibleExpenses = Money.zero;
    for (final tag in businessTags) {
      final tagged = [
        for (final line in lines)
          if (line.tag.name == tag.name) line,
      ];
      if (tagged.isEmpty) continue;
      final gross = tagged.fold(Money.zero, (sum, line) => sum + line.gross);
      final deductible = tagged.fold(
        Money.zero,
        (sum, line) => sum + line.deductible,
      );
      rows.add(
        BusinessSummaryRow(tag: tag, gross: gross, deductible: deductible),
      );
      if (tag.isIncome) {
        income += gross;
      } else {
        deductibleExpenses += deductible;
      }
    }

    var unreviewed = 0;
    for (final transaction in _transactions.values) {
      if (transaction.isTransfer || transaction.date.year != year) continue;
      if (_accounts[transaction.accountId]?.type.onBudget == false) continue;
      for (final line in transaction.lines) {
        if (!line.reviewed) unreviewed++;
      }
    }

    return BusinessReport(
      year: year,
      rows: rows,
      lines: lines,
      warnings: [
        if (unreviewed > 0) UnreviewedLines(unreviewed),
        for (final tag in businessTags)
          if (missingUse.contains(tag.name)) MissingBusinessUse(tag),
        for (final line in giftsWithoutRecipient) GiftWithoutRecipient(line),
      ],
      income: income,
      deductibleExpenses: deductibleExpenses,
    );
  }
}

/// [cents] at [percent], in whole cents, rounding toward zero: 48.21 at 50%
/// is 24.10, and a refund of 48.21 gives back 24.10.
int _percentOf(int cents, int percent) => cents * percent ~/ 100;
