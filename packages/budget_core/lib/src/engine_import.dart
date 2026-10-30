part of 'engine.dart';

// One-time migration (ticket 14): a whole import becomes one Event group with
// actor `import`, or nothing at all.

const _invalidImport = Rejected(Rejection.importPlanInvalid);

CommandResult _commitImport(
  CommitImport command,
  BudgetState state,
  _Stamp stamp,
) {
  final batch = command.batch;
  final accounts = {for (final account in state.accounts) account.id: account};
  final groups = {for (final group in state.categoryGroups) group.id};
  final categories = {for (final category in state.categories) category.id};
  final tags = {for (final tag in state.businessTags) tag.name};
  final used = <String>{};

  /// Whether [id] is new to both the log and this batch.
  bool fresh(String id) => id.isNotEmpty && used.add(id);
  for (final account in batch.accounts) {
    if (!fresh(account.id) ||
        accounts.containsKey(account.id) ||
        account.name.trim().isEmpty) {
      return _invalidImport;
    }
    accounts[account.id] = Account(
      id: account.id,
      name: account.name.trim(),
      type: account.type,
    );
  }
  final importedAccounts = {for (final account in batch.accounts) account.id};

  for (final group in batch.categoryGroups) {
    if (!fresh(group.id) ||
        groups.contains(group.id) ||
        group.name.trim().isEmpty) {
      return _invalidImport;
    }
    groups.add(group.id);
  }

  final cardPayments = <String>{};
  for (final category in batch.categories) {
    if (!fresh(category.id) ||
        categories.contains(category.id) ||
        category.name.trim().isEmpty ||
        !groups.contains(category.groupId)) {
      return _invalidImport;
    }
    if (category.cardAccountId case final card?) {
      if (accounts[card]?.type != AccountType.creditCard ||
          !cardPayments.add(card)) {
        return _invalidImport;
      }
    }
    categories.add(category.id);
  }

  final transactionIds = <String>{};
  final imported = <String, ImportTransaction>{};
  for (final transaction in batch.transactions) {
    if (!transactionIds.add(transaction.id) ||
        accounts[transaction.accountId] == null ||
        transaction.amount == Money.zero ||
        transaction.lines.isEmpty) {
      return _invalidImport;
    }
    final sum = transaction.lines.fold(Money.zero, (t, l) => t + l.amount);
    if (sum != transaction.amount) return _invalidImport;
    if (transaction.startingBalance) {
      final onBudget = accounts[transaction.accountId]!.type.onBudget;
      if (!onBudget && transaction.lines.any((l) => l.category != null)) {
        return _invalidImport;
      }
      if (onBudget &&
          transaction.lines.any((l) => l.category != readyToAssignCategory)) {
        return _invalidImport;
      }
    }
    for (final line in transaction.lines) {
      final category = line.category;
      if (category != null &&
          category != readyToAssignCategory &&
          !categories.contains(category)) {
        return _invalidImport;
      }
      if (line.business case Business(:final tag) when !tags.contains(tag)) {
        return _invalidImport;
      }
      if (_checkText([line.memo, line.recipient]) case final rejected?) {
        return rejected;
      }
    }
    if (_checkText([transaction.payee, transaction.memo])
        case final rejected?) {
      return rejected;
    }
    imported[transaction.id] = transaction;
  }

  // Both sides of a transfer must be in the batch, point at each other and
  // cancel out.
  for (final transaction in imported.values) {
    final otherId = transaction.transferTransactionId;
    if (otherId == null) {
      if (transaction.transferAccountId != null) return _invalidImport;
      continue;
    }
    final other = imported[otherId];
    if (other == null ||
        transaction.transferAccountId != other.accountId ||
        other.transferTransactionId != transaction.id ||
        other.transferAccountId != transaction.accountId ||
        other.amount != -transaction.amount ||
        transaction.startingBalance ||
        transaction.lines.length != 1) {
      return _invalidImport;
    }
    // A transfer between two budget accounts or two tracking accounts has
    // no Category; across the budget line the budget side needs one, and an
    // outflow can't come from Ready to Assign (ticket 07).
    final side = accounts[transaction.accountId]!.type.onBudget;
    final across = side != accounts[other.accountId]!.type.onBudget;
    final category = transaction.lines.single.category;
    if (!across) {
      if (category != null) return _invalidImport;
    } else if (!side) {
      if (category != null) return _invalidImport;
    } else {
      if (category == null) return _invalidImport;
      if (transaction.amount.isNegative && category == readyToAssignCategory) {
        return _invalidImport;
      }
    }
  }

  final assigned = <String, Map<CalendarMonth, Money>>{};
  for (final assignment in batch.assignments) {
    if (!categories.contains(assignment.categoryId) ||
        assignment.amount == Money.zero) {
      return _invalidImport;
    }
    final byMonth = assigned.putIfAbsent(assignment.categoryId, () => {});
    byMonth[assignment.month] =
        (byMonth[assignment.month] ?? Money.zero) + assignment.amount;
  }

  for (final schedule in batch.schedules) {
    if (!fresh(schedule.id) ||
        accounts[schedule.accountId] == null ||
        schedule.amount == Money.zero ||
        schedule.every < 1 ||
        schedule.payee.trim().isEmpty) {
      return _invalidImport;
    }
    if (schedule.amount.isPositive) {
      if (schedule.category != readyToAssignCategory) return _invalidImport;
    } else if (!categories.contains(schedule.category)) {
      return _invalidImport;
    }
  }

  for (final target in batch.targets) {
    if (!categories.contains(target.categoryId)) return _invalidImport;
    switch (target.target) {
      case RepeatingTarget(:final amount, :final every)
          when !amount.isPositive || every < 1:
        return _invalidImport;
      case ByDateTarget(:final amount) || KeepAtLeastTarget(:final amount)
          when !amount.isPositive:
        return _invalidImport;
      case DrivenByScheduleTarget():
      case RepeatingTarget() || ByDateTarget() || KeepAtLeastTarget():
    }
  }

  // Actual's balance for every account it hands over, to the cent.
  final planned = <String, int>{};
  for (final transaction in imported.values) {
    planned[transaction.accountId] =
        (planned[transaction.accountId] ?? 0) + transaction.amount.cents;
  }
  for (final accountId in importedAccounts) {
    if (batch.expectedBalancesCents[accountId] != (planned[accountId] ?? 0)) {
      return const Rejected(Rejection.importBalanceMismatch);
    }
  }
  for (final accountId in batch.expectedBalancesCents.keys) {
    if (!importedAccounts.contains(accountId)) return _invalidImport;
  }

  return Accepted([
    for (final account in batch.accounts)
      stamp.event(EventType.accountCreated, {
        'accountId': account.id,
        'name': account.name.trim(),
        'accountType': account.type.name,
      }),
    for (final group in batch.categoryGroups)
      stamp.event(EventType.categoryGroupCreated, {
        'categoryGroupId': group.id,
        'name': group.name.trim(),
      }),
    for (final category in batch.categories) ...[
      stamp.event(EventType.categoryCreated, {
        'categoryId': category.id,
        'categoryGroupId': category.groupId,
        'name': category.name.trim(),
        'cardAccountId': ?category.cardAccountId,
      }),
      if (category.archived)
        stamp.event(EventType.categoryArchived, {'categoryId': category.id}),
    ],
    for (final MapEntry(key: categoryId, value: byMonth) in assigned.entries)
      for (final MapEntry(key: month, value: amount) in byMonth.entries)
        if (amount - state.assigned(categoryId, month) != Money.zero)
          _assignment(
            stamp,
            categoryId,
            month,
            amount - state.assigned(categoryId, month),
          ),
    for (final target in batch.targets)
      stamp.event(EventType.targetSet, {
        'categoryId': target.categoryId,
        'target': target.target.toJson(),
      }),
    for (final schedule in batch.schedules)
      stamp.event(EventType.scheduleCreated, {
        'scheduleId': schedule.id,
        'accountId': schedule.accountId,
        'payee': schedule.payee.trim(),
        'memo': schedule.memo.trim(),
        'amountCents': schedule.amount.cents,
        'category': schedule.category,
        'every': schedule.every,
        'interval': schedule.interval.name,
        'nextDue': schedule.nextDue.toIso(),
      }),
    for (final transaction in imported.values)
      stamp.event(EventType.transactionCreated, {
        'transactionId': transaction.id,
        'accountId': transaction.accountId,
        'date': transaction.date.toIso(),
        'payee': transaction.payee.trim(),
        'memo': transaction.memo.trim(),
        'cleared': transaction.cleared.name,
        'amountCents': transaction.amount.cents,
        'lines': [
          for (final line in transaction.lines)
            {
              'lineId': newId(),
              'amountCents': line.amount.cents,
              'category': line.category,
              ...?line.business?.toJson(),
              'memo': line.memo.trim(),
              'recipient': ?line.recipient?.trim(),
              'reviewed': line.reviewed,
            },
        ],
        'transferAccountId': ?transaction.transferAccountId,
        'transferTransactionId': ?transaction.transferTransactionId,
        if (transaction.startingBalance) 'startingBalance': true,
        'importedCategory': ?transaction.importedCategory,
      }),
  ]);
}
