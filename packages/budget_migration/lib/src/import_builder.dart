import 'package:budget_core/budget_core.dart';

import 'actual_export.dart';
import 'import_plan.dart';

/// Turns a read export and the person's tag mapping into one plan. Nothing
/// is written until [commitImport].
ImportPlan buildImportPlan({
  required ActualExport export,
  required List<TagMapping> tagMappings,
  required CivilDate today,
}) {
  final payeeById = {for (final p in export.payees) p.id: p};
  final groupById = {for (final g in export.categoryGroups) g.id: g};
  final transactionById = {for (final t in export.transactions) t.id: t};
  final children = <String, List<ActualTransaction>>{};
  for (final transaction in export.transactions) {
    final parent = transaction.parentId;
    if (transaction.isChild && parent != null) {
      children.putIfAbsent(parent, () => []).add(transaction);
    }
  }

  final warnings = <String>[];

  // Accounts: off-budget becomes tracking, everything else keeps its type.
  final accounts = [
    for (final account in export.accounts)
      MappedAccount(
        id: 'actual-account-${account.id}',
        actualId: account.id,
        name: _name(account.name, 'Account'),
        type: _accountType(account),
        balanceCents: export.accountBalancesCents[account.id] ?? 0,
        closed: account.closed,
      ),
  ];
  final accountFor = {for (final a in accounts) a.actualId: a};
  final closed = accounts.where((a) => a.closed).length;
  if (closed > 0) {
    warnings.add(
      '$closed ${_plural(closed, 'account')} closed in Actual '
      '${closed == 1 ? 'stays' : 'stay'} open here; the app can’t archive an '
      'account.',
    );
  }

  // Category groups and Categories. Income Categories aren't created: their
  // lines go to Ready to Assign (ticket 14).
  final groups = <MappedCategoryGroup>[];
  final categories = <MappedCategory>[];
  final mappedCategoryById = <String, MappedCategory>{};
  for (final group in export.categoryGroups) {
    final members = export.categories.where((c) => c.groupId == group.id);
    if (group.isIncome || members.every((c) => c.isIncome)) continue;
    groups.add(
      MappedCategoryGroup(
        id: 'actual-group-${group.id}',
        actualId: group.id,
        name: _name(group.name, 'Group'),
      ),
    );
  }
  for (final category in export.categories) {
    final group = groupById[category.groupId];
    final income = category.isIncome || (group?.isIncome ?? false);
    var groupId = '';
    if (!income) {
      groupId = 'actual-group-${category.groupId}';
      if (!groups.any((g) => g.id == groupId)) {
        if (!groups.any((g) => g.id == _otherGroup)) {
          groups.add(
            const MappedCategoryGroup(id: _otherGroup, name: 'Imported'),
          );
        }
        groupId = _otherGroup;
      }
    }
    final mapped = MappedCategory(
      id: 'actual-category-${category.id}',
      actualId: category.id,
      name: _name(category.name, 'Category'),
      groupId: groupId,
      income: income,
      hidden: category.hidden,
    );
    categories.add(mapped);
    mappedCategoryById[category.id] = mapped;
  }
  final hidden = categories.where((c) => c.hidden && !c.income).length;
  if (hidden > 0) {
    warnings.add(
      '$hidden hidden ${_plural(hidden, 'Category', 'Categories')} '
      '${hidden == 1 ? 'stays' : 'stay'} visible here; the app can’t hide one.',
    );
  }

  // Each card gets its Card Payment Category; its balance follows from
  // replaying the card's history (ticket 07).
  final cards = accounts.where((a) => a.type == AccountType.creditCard);
  if (cards.isNotEmpty) {
    const groupId = 'actual-group-card-payments';
    groups.add(
      const MappedCategoryGroup(id: groupId, name: 'Credit Card Payments'),
    );
    for (final card in cards) {
      categories.add(
        MappedCategory(
          id: 'actual-category-card-${card.actualId}',
          actualId: 'card:${card.actualId}',
          name: '${card.name} Payment',
          groupId: groupId,
          cardAccountId: card.id,
        ),
      );
    }
  }

  final tagForToken = <String, String>{};
  final tagForCategory = <String, String>{};
  for (final mapping in tagMappings) {
    final tag = mapping.tag?.trim() ?? '';
    if (tag.isEmpty) continue;
    switch (mapping.source) {
      case TagSource.tag:
        tagForToken[mapping.key] = tag;
      case TagSource.category:
        tagForCategory[mapping.key] = tag;
    }
  }

  // Transactions, splits and transfers.
  final transactions = <ImportTransaction>[];
  var conflictingTags = 0;
  var giftsWithoutRecipient = 0;
  var zeroAmounts = 0;
  var orphanSplits = 0;
  for (final row in export.transactions) {
    if (row.isChild) continue;
    final lines = row.isParent ? children[row.id] ?? const [] : [row];
    if (lines.isEmpty) {
      orphanSplits++;
      continue;
    }
    final amount = lines.fold(0, (total, line) => total + line.amountCents);
    if (amount == 0) {
      zeroAmounts++;
      continue;
    }
    final account = accountFor[row.accountId];
    if (account == null) {
      orphanSplits++;
      continue;
    }
    final transfer = _transfer(
      row,
      transactionById: transactionById,
      accountFor: accountFor,
      categoryFor: (id) => id == null ? null : mappedCategoryById[id],
    );
    final lineModels = <ImportLine>[];
    String? importedCategory;
    for (final line in lines) {
      final category = line.categoryId == null
          ? null
          : mappedCategoryById[line.categoryId];
      final income = category?.income ?? false;
      if (income) importedCategory = category!.name;
      final tags = <String>{
        for (final token in actualTags(row.notes)) ?tagForToken[token],
        if (line.categoryId case final id?) ?tagForCategory[id],
      };
      final conflicted = tags.length > 1;
      if (conflicted) conflictingTags++;
      final business = conflicted
          ? null
          : tags.isEmpty
          ? const Personal()
          : Business(tags.single);
      if (business == const Business(giftsTag)) giftsWithoutRecipient++;
      final startingBalance = row.startingBalance;
      final categoryId = startingBalance
          ? account.type.onBudget
                ? readyToAssignCategory
                : null
          : transfer.isTransfer
          ? transfer.categoryId
          : income
          ? readyToAssignCategory
          : category?.id;
      lineModels.add(
        ImportLine(
          amount: Money(line.amountCents),
          category: categoryId,
          business: transfer.isTransfer || startingBalance ? null : business,
          memo: line == row ? '' : maskSensitiveNumbers(line.notes),
          reviewed:
              transfer.isTransfer ||
              startingBalance ||
              (row.date.year < today.year &&
                  !conflicted &&
                  business != const Business(giftsTag)),
        ),
      );
    }
    transactions.add(
      ImportTransaction(
        id: 'actual-transaction-${row.id}',
        accountId: account.id,
        date: row.date,
        amount: Money(amount),
        lines: lineModels,
        payee: maskSensitiveNumbers(payeeById[row.payeeId]?.name ?? ''),
        memo: maskSensitiveNumbers(row.notes),
        cleared: row.cleared,
        transferAccountId: transfer.otherAccountId,
        transferTransactionId: transfer.otherTransactionId,
        startingBalance: row.startingBalance,
        importedCategory: importedCategory,
      ),
    );
  }
  if (conflictingTags > 0) {
    warnings.add(
      '$conflictingTags ${_plural(conflictingTags, 'line')} mapped to more than '
      'one Business Tag ${conflictingTags == 1 ? 'goes' : 'go'} to Review.',
    );
  }
  if (giftsWithoutRecipient > 0) {
    warnings.add(
      '$giftsWithoutRecipient ${_plural(giftsWithoutRecipient, 'gift line')} '
      '${giftsWithoutRecipient == 1 ? 'has' : 'have'} no recipient, so '
      '${giftsWithoutRecipient == 1 ? 'it stays' : 'they stay'} in Review.',
    );
  }
  if (zeroAmounts > 0) {
    warnings.add(
      '$zeroAmounts zero-amount ${_plural(zeroAmounts, 'transaction')} '
      '${zeroAmounts == 1 ? 'was' : 'were'} skipped.',
    );
  }
  if (orphanSplits > 0) {
    warnings.add(
      '$orphanSplits split ${_plural(orphanSplits, 'transaction')} had no '
      'lines or account and ${orphanSplits == 1 ? 'was' : 'were'} skipped.',
    );
  }

  // Assignments, as one delta per Category and month.
  final assigned = <(String, CalendarMonth), int>{};
  final carryoverMonths = <CalendarMonth>{};
  var incomeAssignments = 0;
  for (final row in export.budgetMonths) {
    final category = mappedCategoryById[row.categoryId];
    if (category == null) continue;
    if (category.income) {
      incomeAssignments++;
      continue;
    }
    final key = (category.id, row.month);
    assigned[key] = (assigned[key] ?? 0) + row.amountCents;
    if (row.carryover) carryoverMonths.add(row.month);
  }
  final assignments = [
    for (final MapEntry(key: (categoryId, month), value: cents)
        in assigned.entries)
      if (cents != 0)
        ImportAssignment(
          categoryId: categoryId,
          month: month,
          amount: Money(cents),
        ),
  ];
  if (carryoverMonths.isNotEmpty) {
    warnings.add(
      '${carryoverMonths.length} '
      '${_plural(carryoverMonths.length, 'month')} used Actual’s roll-over '
      'overspending, which has no equivalent; those months may differ.',
    );
  }
  if (incomeAssignments > 0) {
    warnings.add(
      '$incomeAssignments income Category '
      '${_plural(incomeAssignments, 'Assignment')} to Ready to Assign '
      '${incomeAssignments == 1 ? 'was' : 'were'} skipped: Ready to Assign is '
      'one pool here, not a month’s balance.',
    );
  }
  if (export.trackingBudget) {
    warnings.add(
      'This export is from Actual’s tracking mode, so only its transactions '
      'were imported.',
    );
  }

  // Schedules, best effort: they need a Category and a repeat.
  final schedules = <ImportSchedule>[];
  var unconvertedSchedules = 0;
  for (final schedule in export.schedules) {
    final account = accountFor[schedule.accountId];
    final payee = schedule.payeeId == null ? null : payeeById[schedule.payeeId];
    final category = schedule.categoryId == null
        ? null
        : mappedCategoryById[schedule.categoryId];
    final interval = switch (schedule.frequency) {
      'daily' => TargetInterval.days,
      'weekly' => TargetInterval.weeks,
      'monthly' => TargetInterval.months,
      'yearly' => TargetInterval.years,
      _ => null,
    };
    final categoryId = schedule.amountCents > 0
        ? readyToAssignCategory
        : category == null || category.income
        ? null
        : category.id;
    if (account == null ||
        payee == null ||
        payee.name.trim().isEmpty ||
        categoryId == null ||
        schedule.amountCents == 0 ||
        interval == null ||
        schedule.interval < 1) {
      unconvertedSchedules++;
      continue;
    }
    schedules.add(
      ImportSchedule(
        id: 'actual-schedule-${schedule.id}',
        accountId: account.id,
        payee: maskSensitiveNumbers(payee.name.trim()),
        amount: Money(schedule.amountCents),
        category: categoryId,
        every: schedule.interval,
        interval: interval,
        nextDue: schedule.nextDate,
        memo: _name(schedule.name, ''),
      ),
    );
  }
  if (unconvertedSchedules > 0) {
    warnings.add(
      '$unconvertedSchedules ${_plural(unconvertedSchedules, 'Scheduled Transaction')} '
      'couldn’t be converted; set '
      '${unconvertedSchedules == 1 ? 'it' : 'them'} up by hand.',
    );
  }

  // Targets from `#template` lines, best effort.
  final targets = <ImportTarget>[];
  final unconvertedTemplates = <String>[];
  for (final MapEntry(key: id, value: note) in export.notes.entries) {
    final category = mappedCategoryById[id];
    if (category == null || category.income) continue;
    final templateLines = [
      for (final line in note.split('\n'))
        if (line.contains('#template')) line,
    ];
    if (templateLines.isEmpty) continue;
    final target = templateLines.length == 1
        ? _parseTemplate(templateLines.single, today)
        : null;
    if (target == null) {
      unconvertedTemplates.add(category.name);
      continue;
    }
    targets.add(ImportTarget(categoryId: category.id, target: target));
  }
  if (unconvertedTemplates.isNotEmpty) {
    warnings.add(
      '${unconvertedTemplates.length} '
      '${_plural(unconvertedTemplates.length, 'Category note')} with '
      '${unconvertedTemplates.length == 1 ? 'a #template line was' : '#template lines were'} '
      'left for Targets to set by hand: ${unconvertedTemplates.join(', ')}.',
    );
  }
  if (export.rules.isNotEmpty) {
    warnings.add(
      '${export.rules.length} ${_plural(export.rules.length, 'rule')} '
      '${export.rules.length == 1 ? 'was' : 'were'} listed, not imported: '
      'nothing categorizes a transaction for you.',
    );
  }

  return ImportPlan(
    export: export,
    today: today,
    accounts: accounts,
    categoryGroups: groups,
    categories: categories,
    tagMappings: tagMappings,
    transactions: transactions,
    assignments: assignments,
    schedules: schedules,
    targets: targets,
    warnings: warnings,
  );
}

/// Commits [plan] as one group with actor `import`. Throws [ImportBlocked]
/// when the engine refuses it, so nothing is written.
ImportCommit commitImport(BudgetEngine engine, ImportPlan plan) =>
    commitImportBatch(
      engine,
      plan.toBatch(),
      categories: plan.categories.where((c) => !c.income).length,
    );

/// Commits a prepared [batch] as one group with actor `import`, for an import
/// whose accounts and Categories already exist, such as the YNAB items a
/// person pulled in (ticket 14). Throws [ImportBlocked] when the engine
/// refuses it, so nothing is written.
ImportCommit commitImportBatch(
  BudgetEngine engine,
  ImportBatch batch, {
  int? categories,
}) {
  final result = engine.execute(CommitImport(batch));
  return switch (result) {
    Accepted(:final events) when events.isNotEmpty => ImportCommit(
      groupId: events.first.groupId,
      accounts: batch.accounts.length,
      categories: categories ?? batch.categories.length,
      transactions: batch.transactions.length,
      assignments: batch.assignments.length,
      schedules: batch.schedules.length,
    ),
    Accepted() => throw const ImportBlocked(Rejection.importPlanInvalid),
    Rejected(:final reason) => throw ImportBlocked(reason),
  };
}

AccountType _accountType(ActualAccount account) {
  if (account.offBudget) return AccountType.tracking;
  return switch (account.type?.toLowerCase()) {
    'savings' => AccountType.savings,
    'cash' => AccountType.cash,
    'credit' || 'creditcard' || 'credit card' => AccountType.creditCard,
    _ => AccountType.checking,
  };
}

String _name(String value, String fallback) =>
    value.trim().isEmpty ? fallback : value.trim();

String _plural(int count, String singular, [String? plural]) =>
    count == 1 ? singular : plural ?? '${singular}s';

const _otherGroup = 'actual-group-other';

/// One row's transfer decision. Both sides decide the same way, so a pair
/// never becomes a one-sided transfer. [categoryId] is the budget side's
/// Category when the pair crosses the budget line, and null otherwise.
({
  bool isTransfer,
  String? otherAccountId,
  String? otherTransactionId,
  String? categoryId,
})
_transfer(
  ActualTransaction row, {
  required Map<String, ActualTransaction> transactionById,
  required Map<String, MappedAccount> accountFor,
  required MappedCategory? Function(String? id) categoryFor,
}) {
  const none = (
    isTransfer: false,
    otherAccountId: null,
    otherTransactionId: null,
    categoryId: null,
  );
  final otherId = row.transferId;
  if (otherId == null) return none;
  final other = transactionById[otherId];
  if (other == null ||
      other.isParent ||
      other.isChild ||
      other.transferId != row.id) {
    return none;
  }
  final account = accountFor[row.accountId];
  final otherAccount = accountFor[other.accountId];
  if (account == null ||
      otherAccount == null ||
      account.id == otherAccount.id ||
      other.amountCents != -row.amountCents) {
    return none;
  }
  String? categoryId;
  // Two budget accounts or two tracking accounts need no Category. Across
  // the budget line, the budget side does, and without one the pair stays
  // ordinary so nothing leaves the budget uncategorized.
  if (account.type.onBudget != otherAccount.type.onBudget) {
    final budgetSide = account.type.onBudget ? row : other;
    final category = categoryFor(budgetSide.categoryId);
    if (category?.income ?? false) {
      // Income is only allowed coming into the budget.
      if (budgetSide.amountCents < 0) return none;
      categoryId = readyToAssignCategory;
    } else if (category != null) {
      categoryId = category.id;
    } else if (budgetSide.amountCents > 0) {
      categoryId = readyToAssignCategory;
    } else {
      return none;
    }
  }
  return (
    isTransfer: true,
    otherAccountId: otherAccount.id,
    otherTransactionId: 'actual-transaction-${other.id}',
    categoryId: account.type.onBudget || !otherAccount.type.onBudget
        ? categoryId
        : null,
  );
}

/// One `#template` line as a Target, or null when it doesn't parse.
Target? _parseTemplate(String line, CivilDate today) {
  final text = line.substring(line.indexOf('#template') + '#template'.length);
  final upTo = RegExp(
    r'^\s*up to\s+(\$?[\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  ).firstMatch(text);
  if (upTo != null) {
    final amount = Money.tryParse(upTo[1]!);
    return amount == null || !amount.isPositive
        ? null
        : KeepAtLeastTarget(amount: amount);
  }
  final amountMatch = RegExp(r'^\s*(\$?[\d,]+(?:\.\d{1,2})?)').firstMatch(text);
  if (amountMatch == null) return null;
  final amount = Money.tryParse(amountMatch[1]!);
  if (amount == null || !amount.isPositive) return null;
  final by = RegExp(
    r'\bby\s+(\d{4})-(\d{1,2})',
    caseSensitive: false,
  ).firstMatch(text);
  if (by != null) {
    final month = CalendarMonth(int.parse(by[1]!), int.parse(by[2]!));
    return ByDateTarget(
      amount: amount,
      date: CivilDate(month.year, month.month, 1).addMonths(1).addDays(-1),
    );
  }
  final repeat = RegExp(
    r'repeat every\s+(\d+)\s+(day|week|month|year)s?',
    caseSensitive: false,
  ).firstMatch(text);
  final every = repeat == null ? 1 : int.parse(repeat[1]!);
  final interval = switch (repeat?[2]?.toLowerCase()) {
    'day' => TargetInterval.days,
    'week' => TargetInterval.weeks,
    'year' => TargetInterval.years,
    _ => TargetInterval.months,
  };
  return RepeatingTarget(
    amount: amount,
    every: every,
    interval: interval,
    nextDue: CivilDate(today.year, today.month, 1),
  );
}
