import 'budget_state.dart';
import 'civil_date.dart';
import 'money.dart';
import 'target.dart';

// A whole import (ticket 14), written as one Event group with actor
// `import`. `budget_migration` turns an Actual export into one of these; the
// engine checks it and writes the Events, so no importer can bypass the
// rules below.

/// An account an import creates.
final class ImportAccount {
  const ImportAccount({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;
  final AccountType type;
}

/// A Category group an import creates.
final class ImportCategoryGroup {
  const ImportCategoryGroup({required this.id, required this.name});

  final String id;
  final String name;
}

/// A Category an import creates. A Card Payment Category has its card's
/// [cardAccountId].
final class ImportCategory {
  const ImportCategory({
    required this.id,
    required this.groupId,
    required this.name,
    this.cardAccountId,
    this.archived = false,
  });

  final String id;
  final String groupId;
  final String name;
  final String? cardAccountId;
  final bool archived;
}

/// One line of an imported Transaction. [reviewed] is true for the earlier
/// years the person confirms in one go; the current tax year arrives
/// Unreviewed and pre-filled (ticket 09, ticket 14).
final class ImportLine {
  const ImportLine({
    required this.amount,
    required this.reviewed,
    this.category,
    this.business,
    this.memo = '',
    this.recipient,
  });

  /// Negative for an outflow.
  final Money amount;

  /// A Category id, [readyToAssignCategory] for income, or null while
  /// uncategorized.
  final String? category;
  final BusinessStatus? business;
  final String memo;
  final String? recipient;
  final bool reviewed;
}

/// A Transaction an import creates, with its splits and one side of a
/// transfer already resolved.
final class ImportTransaction {
  const ImportTransaction({
    required this.id,
    required this.accountId,
    required this.date,
    required this.amount,
    required this.lines,
    this.payee = '',
    this.memo = '',
    this.cleared = ClearedStatus.uncleared,
    this.transferAccountId,
    this.transferTransactionId,
    this.startingBalance = false,
    this.importedCategory,
  });

  final String id;
  final String accountId;
  final CivilDate date;

  /// Negative for an outflow. Always the sum of [lines].
  final Money amount;
  final List<ImportLine> lines;
  final String payee;
  final String memo;
  final ClearedStatus cleared;

  /// For one side of a transfer, the other side's account and transaction.
  final String? transferAccountId;
  final String? transferTransactionId;

  /// A card or tracking account's opening balance (ticket 07).
  final bool startingBalance;

  /// The Actual income category an income line lost when it went to Ready to
  /// Assign, kept as read-only metadata (ticket 14).
  final String? importedCategory;
}

/// One Category Assignment, as an absolute amount for the month. The engine
/// records the difference from what is already assigned.
final class ImportAssignment {
  const ImportAssignment({
    required this.categoryId,
    required this.month,
    required this.amount,
  });

  final String categoryId;
  final CalendarMonth month;
  final Money amount;
}

/// A Scheduled Transaction an import creates.
final class ImportSchedule {
  const ImportSchedule({
    required this.id,
    required this.accountId,
    required this.payee,
    required this.amount,
    required this.category,
    required this.every,
    required this.interval,
    required this.nextDue,
    this.memo = '',
  });

  final String id;
  final String accountId;
  final String payee;

  /// Negative for an outflow.
  final Money amount;
  final String category;
  final int every;
  final TargetInterval interval;
  final CivilDate nextDue;
  final String memo;
}

/// A Category Target an import creates, such as one parsed from a
/// `#template` line.
final class ImportTarget {
  const ImportTarget({required this.categoryId, required this.target});

  final String categoryId;
  final Target target;
}

/// Everything one import creates. [expectedBalancesCents] is Actual's
/// balance for every account in [accounts]; the engine refuses the whole
/// group unless the imported transactions add up to each one, to the cent
/// (ticket 14).
final class ImportBatch {
  const ImportBatch({
    required this.accounts,
    required this.categoryGroups,
    required this.categories,
    required this.transactions,
    required this.assignments,
    required this.schedules,
    required this.targets,
    required this.expectedBalancesCents,
  });

  final List<ImportAccount> accounts;
  final List<ImportCategoryGroup> categoryGroups;
  final List<ImportCategory> categories;
  final List<ImportTransaction> transactions;
  final List<ImportAssignment> assignments;
  final List<ImportSchedule> schedules;
  final List<ImportTarget> targets;
  final Map<String, int> expectedBalancesCents;
}
