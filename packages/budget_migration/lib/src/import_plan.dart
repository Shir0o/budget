import 'package:budget_core/budget_core.dart';

import 'actual_export.dart';

// The decisions the Actual import wizard makes (ticket 14): which accounts,
// Category groups and Categories to create, which Business Tag each Actual
// tag and used Category maps to, and the one batch those decisions add up to.

/// Where a Business Tag mapping comes from.
enum TagSource {
  /// A `#tag` token in a transaction's notes.
  tag,

  /// A Category that was used.
  category,
}

/// One distinct Actual `#tag` or used Category, with how often it appears and
/// the Business Tag the person chose for it. A null [tag] means nothing.
final class TagMapping {
  const TagMapping({
    required this.source,
    required this.key,
    required this.label,
    required this.count,
    this.tag,
  });

  final TagSource source;

  /// `#workMeals` for a tag, or a Category id.
  final String key;

  /// What the screen lists: `#workMeals`, or the Category's name.
  final String label;
  final int count;

  /// A Business Tag name, or null for nothing.
  final String? tag;

  TagMapping withTag(String? tag) => TagMapping(
    source: source,
    key: key,
    label: label,
    count: count,
    tag: tag,
  );
}

/// The 1:1 mappings verified against the real exports (ticket 18).
const _defaultTags = {
  'workassets': 'Other business expense',
  'workexpenses': 'Other business expense',
  'workmeals': 'Meals',
  'worksubscriptions': 'Software & subscriptions',
  'worksupplies': 'Supplies',
  'worktravel': 'Travel',
};

/// Every `#tag` and used Category, with the preset mapping where ticket 18
/// has one. Categories default to nothing, so the person chooses.
List<TagMapping> defaultTagMappings(ActualExport export) {
  final names = {
    for (final category in export.categories) category.id: category.name,
  };
  final tagCounts = <String, int>{};
  final categoryCounts = <String, int>{};
  for (final transaction in export.transactions) {
    if (!transaction.isChild) {
      for (final token in actualTags(transaction.notes)) {
        tagCounts[token] = (tagCounts[token] ?? 0) + 1;
      }
    }
    if (transaction.isParent) continue;
    final category = transaction.categoryId;
    if (category != null) {
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }
  }
  final tags = [
    for (final MapEntry(key: token, value: count) in tagCounts.entries)
      TagMapping(
        source: TagSource.tag,
        key: token,
        label: token,
        count: count,
        tag: _defaultTags[token.substring(1).toLowerCase()],
      ),
  ]..sort((a, b) => a.label.compareTo(b.label));
  final categories = [
    for (final MapEntry(key: id, value: count) in categoryCounts.entries)
      TagMapping(
        source: TagSource.category,
        key: id,
        label: names[id] ?? id,
        count: count,
      ),
  ]..sort((a, b) => a.label.compareTo(b.label));
  return [...tags, ...categories];
}

final _tagPattern = RegExp(r'#(\w[\w-]*)');

/// Every `#tag` token in [notes], each once.
Set<String> actualTags(String notes) => {
  for (final match in _tagPattern.allMatches(notes)) '#${match[1]}',
};

/// An Actual account, as the app will create it.
final class MappedAccount {
  const MappedAccount({
    required this.id,
    required this.actualId,
    required this.name,
    required this.type,
    required this.balanceCents,
    this.closed = false,
  });

  /// The id the import gives it.
  final String id;
  final String actualId;
  final String name;
  final AccountType type;

  /// Actual's balance for it, which the import must reproduce to the cent.
  final int balanceCents;

  /// Closed in Actual. The app has no archived account, so it stays open
  /// and the report says so.
  final bool closed;
}

/// An Actual Category group, as the app will create it.
final class MappedCategoryGroup {
  const MappedCategoryGroup({
    required this.id,
    required this.name,
    this.actualId,
  });

  final String id;
  final String name;

  /// Null for the "Credit Card Payments" group the import derives.
  final String? actualId;
}

/// An Actual Category, as the app will create it.
final class MappedCategory {
  const MappedCategory({
    required this.id,
    required this.name,
    required this.groupId,
    required this.actualId,
    this.income = false,
    this.hidden = false,
    this.cardAccountId,
  });

  final String id;
  final String name;
  final String groupId;
  final String actualId;

  /// An income Category: its lines go to Ready to Assign instead, so it is
  /// listed but not created (ticket 14).
  final bool income;

  /// Hidden in Actual. The app has no hidden Category, so it is listed in
  /// the report instead of archived.
  final bool hidden;

  /// The card whose Card Payment Category this is, for one the import
  /// derives.
  final String? cardAccountId;
}

/// Everything the wizard decided, ready to commit as one group.
final class ImportPlan {
  const ImportPlan({
    required this.export,
    required this.today,
    required this.accounts,
    required this.categoryGroups,
    required this.categories,
    required this.tagMappings,
    required this.transactions,
    required this.assignments,
    required this.schedules,
    required this.targets,
    required this.warnings,
  });

  final ActualExport export;

  /// The day the import runs, which decides the current tax year and a
  /// Target's next due date.
  final CivilDate today;
  final List<MappedAccount> accounts;
  final List<MappedCategoryGroup> categoryGroups;
  final List<MappedCategory> categories;
  final List<TagMapping> tagMappings;
  final List<ImportTransaction> transactions;
  final List<ImportAssignment> assignments;
  final List<ImportSchedule> schedules;
  final List<ImportTarget> targets;

  /// What the person should know before committing, such as rules that stay
  /// behind. Every line reads as a sentence.
  final List<String> warnings;

  /// The current tax year: its lines arrive Unreviewed and pre-filled,
  /// earlier years Reviewed (ticket 09).
  int get currentTaxYear => today.year;

  ImportBatch toBatch() => ImportBatch(
    accounts: [
      for (final account in accounts)
        ImportAccount(id: account.id, name: account.name, type: account.type),
    ],
    categoryGroups: [
      for (final group in categoryGroups)
        ImportCategoryGroup(id: group.id, name: group.name),
    ],
    categories: [
      for (final category in categories)
        if (!category.income)
          ImportCategory(
            id: category.id,
            groupId: category.groupId,
            name: category.name,
            cardAccountId: category.cardAccountId,
          ),
    ],
    transactions: transactions,
    assignments: assignments,
    schedules: schedules,
    targets: targets,
    expectedBalancesCents: {
      for (final account in accounts) account.id: account.balanceCents,
    },
  );

  /// Every account whose imported transactions don't add up to Actual's
  /// balance. The engine refuses the commit while this isn't empty, so a
  /// non-empty list is a parser bug (ticket 14).
  List<BalanceMismatch> get balanceMismatches {
    final planned = <String, int>{};
    for (final transaction in transactions) {
      planned[transaction.accountId] =
          (planned[transaction.accountId] ?? 0) + transaction.amount.cents;
    }
    return [
      for (final account in accounts)
        if (account.balanceCents != (planned[account.id] ?? 0))
          BalanceMismatch(
            account: account,
            actualCents: account.balanceCents,
            importedCents: planned[account.id] ?? 0,
          ),
    ];
  }

  bool _inReviewQueue(ImportTransaction t) =>
      t.transferTransactionId == null &&
      accounts.any((a) => a.id == t.accountId && a.type.onBudget);

  ImportReport get report => ImportReport(
    accounts: accounts.length,
    categoryGroups: categoryGroups.length,
    categories: categories.where((category) => !category.income).length,
    incomeCategories: categories.where((category) => category.income).length,
    transactions: transactions.length,
    lines: transactions.fold(0, (total, t) => total + t.lines.length),
    months: {for (final row in export.budgetMonths) row.month}.length,
    schedules: schedules.length,
    rules: export.rules.length,
    reviewedLines: transactions.fold(
      0,
      (total, t) => total + t.lines.where((line) => line.reviewed).length,
    ),
    // Only what Review will list: not transfer lines, not tracking accounts.
    unreviewedLines: transactions.fold(
      0,
      (total, t) => !_inReviewQueue(t)
          ? total
          : total + t.lines.where((line) => !line.reviewed).length,
    ),
    lastTransactionDate: transactions.isEmpty
        ? null
        : transactions
              .map((transaction) => transaction.date)
              .reduce((a, b) => a.compareTo(b) >= 0 ? a : b),
    warnings: warnings,
    balanceMismatches: balanceMismatches,
  );
}

/// One account whose imported transactions don't match Actual.
final class BalanceMismatch {
  const BalanceMismatch({
    required this.account,
    required this.actualCents,
    required this.importedCents,
  });

  final MappedAccount account;
  final int actualCents;
  final int importedCents;

  @override
  String toString() =>
      '${account.name}: Actual ${Money(actualCents)} vs imported '
      '${Money(importedCents)}';
}

/// What an import will do, before the person commits it.
final class ImportReport {
  const ImportReport({
    required this.accounts,
    required this.categoryGroups,
    required this.categories,
    required this.incomeCategories,
    required this.transactions,
    required this.lines,
    required this.months,
    required this.schedules,
    required this.rules,
    required this.reviewedLines,
    required this.unreviewedLines,
    required this.lastTransactionDate,
    required this.warnings,
    required this.balanceMismatches,
  });

  final int accounts;
  final int categoryGroups;
  final int categories;

  /// Income Categories that become Ready to Assign.
  final int incomeCategories;
  final int transactions;
  final int lines;
  final int months;
  final int schedules;

  /// Actual's rules, listed and never imported (ADR 0003).
  final int rules;
  final int reviewedLines;
  final int unreviewedLines;

  /// The newest imported transaction's date, or null when there are none.
  final CivilDate? lastTransactionDate;
  final List<String> warnings;
  final List<BalanceMismatch> balanceMismatches;

  /// False while any account is off by a cent, which blocks the commit.
  bool get balancesMatch => balanceMismatches.isEmpty;
}

/// What committing an import wrote: its one group and its counts.
final class ImportCommit {
  const ImportCommit({
    required this.groupId,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.assignments,
    required this.schedules,
  });

  final String groupId;
  final int accounts;
  final int categories;
  final int transactions;
  final int assignments;
  final int schedules;
}

/// The engine refused the whole import, so nothing was written.
final class ImportBlocked implements Exception {
  const ImportBlocked(this.reason);

  final Rejection reason;

  @override
  String toString() => 'Import blocked: ${reason.name}';
}
