part of 'engine.dart';

// Card Payment Categories and transfers (ticket 05, ticket 07).

/// The name of the group Card Payment Categories go in.
const _cardPaymentsGroup = 'Credit Card Payments';

/// The card's Card Payment Category, in the group that already holds the
/// others, or a new "Credit Card Payments" group.
List<Event> _cardPaymentCategory(
  BudgetState state,
  _Stamp stamp,
  String accountId,
  String name,
) {
  final existing = state.categories
      .where((c) => c.cardAccountId != null)
      .firstOrNull
      ?.groupId;
  final groupId = existing ?? newId();
  return [
    if (existing == null)
      stamp.event(EventType.categoryGroupCreated, {
        'categoryGroupId': groupId,
        'name': _cardPaymentsGroup,
      }),
    stamp.event(EventType.categoryCreated, {
      'categoryId': newId(),
      'categoryGroupId': groupId,
      'name': '$name Payment',
      'cardAccountId': accountId,
    }),
  ];
}

/// A card or tracking account's Starting Balance. It has no Category and
/// doesn't touch Ready to Assign (ticket 07 example 6).
Event _offBudgetStartingBalance(
  _Stamp stamp,
  String accountId,
  AddAccount command,
) => stamp.event(EventType.transactionCreated, {
  'transactionId': newId(),
  'accountId': accountId,
  'date': command.asOf.toIso(),
  'payee': 'Starting Balance',
  'memo': '',
  'cleared': ClearedStatus.cleared.name,
  'amountCents': command.startingBalance.cents,
  'startingBalance': true,
  'lines': [
    {
      'lineId': newId(),
      'amountCents': command.startingBalance.cents,
      'category': null,
      'memo': '',
      'reviewed': stamp.actor.isPerson,
    },
  ],
});

/// A stored transfer line. Transfer lines skip business status, and the
/// Category rules were checked already, so a person's line is Reviewed
/// (ticket 09).
Map<String, Object?> _transferLine(
  Money amount,
  String? category,
  Actor actor, {
  String? id,
}) => {
  'lineId': id ?? newId(),
  'amountCents': amount.cents,
  'category': category,
  'memo': '',
  'reviewed': actor.isPerson,
};

/// Checks [category] on the [side] of a transfer whose other side is in
/// [other]. Only the budget side of a budget-and-tracking transfer has one.
Rejected? _checkTransferCategory(
  BudgetState state,
  Account side,
  Account other,
  String? category, {
  required bool inflow,
}) {
  final needed = side.type.onBudget && !other.type.onBudget;
  if (!needed) {
    return category == null
        ? null
        : const Rejected(Rejection.transferHasNoCategory);
  }
  if (category == null) {
    return const Rejected(Rejection.transferCategoryRequired);
  }
  if (category == readyToAssignCategory) {
    return inflow ? null : const Rejected(Rejection.transferCategoryRequired);
  }
  return _checkActive(state, category);
}

CommandResult _createTransfer(
  CreateTransfer command,
  BudgetState state,
  _Stamp stamp,
) {
  final from = state.account(command.fromAccountId);
  final to = state.account(command.toAccountId);
  if (from == null || to == null) {
    return const Rejected(Rejection.unknownAccount);
  }
  if (from.id == to.id) return const Rejected(Rejection.sameAccount);
  if (!command.amount.isPositive) {
    return const Rejected(Rejection.amountMustBePositive);
  }
  if (_checkText([command.memo]) case final rejected?) return rejected;
  final category = command.category;
  final fromCategory = from.type.onBudget && !to.type.onBudget
      ? category
      : null;
  final toCategory = to.type.onBudget && !from.type.onBudget ? category : null;
  if (category != null && fromCategory == null && toCategory == null) {
    return const Rejected(Rejection.transferHasNoCategory);
  }
  for (final (side, other, sideCategory, inflow) in [
    (from, to, fromCategory, false),
    (to, from, toCategory, true),
  ]) {
    if (_checkTransferCategory(state, side, other, sideCategory, inflow: inflow)
        case final rejected?) {
      return rejected;
    }
  }

  final fromId = newId();
  final toId = newId();
  Event side(
    String id,
    Account account,
    Account other,
    String pairId,
    Money amount,
    String? category,
  ) => stamp.event(EventType.transactionCreated, {
    'transactionId': id,
    'accountId': account.id,
    'date': command.date.toIso(),
    'payee': '',
    'memo': command.memo.trim(),
    'cleared': ClearedStatus.uncleared.name,
    'amountCents': amount.cents,
    'transferAccountId': other.id,
    'transferTransactionId': pairId,
    'lines': [_transferLine(amount, category, stamp.actor)],
  });
  return Accepted([
    side(fromId, from, to, toId, -command.amount, fromCategory),
    side(toId, to, from, fromId, command.amount, toCategory),
  ]);
}

/// Checks a transfer side's new [amount] and [lines]: one line, with the
/// Category its side needs.
Rejected? _checkTransferLines(
  BudgetState state,
  Transaction transaction,
  Money amount,
  List<LineInput> lines,
) {
  if (lines.length != 1) return const Rejected(Rejection.transferCannotSplit);
  final side = state.account(transaction.accountId);
  final other = state.account(transaction.transferAccountId!);
  if (side == null || other == null) return null;
  if (lines.single.category != transaction.lines.single.category ||
      amount.isPositive != transaction.amount.isPositive) {
    return _checkTransferCategory(
      state,
      side,
      other,
      lines.single.category,
      inflow: amount.isPositive,
    );
  }
  return null;
}

/// Copies a transfer side's new date and amount to the other side.
List<Event> _mirrorTransfer(
  BudgetState state,
  _Stamp stamp,
  Transaction transaction,
  List<Event> edits,
) {
  final pair = state.transaction(transaction.transferTransactionId!);
  if (pair == null) return const [];
  return [
    for (final edit in edits)
      if (edit.type == EventType.transactionFieldsSet &&
          (edit.payload['fields'] as Map)['date'] != null)
        stamp.event(EventType.transactionFieldsSet, {
          'transactionId': pair.id,
          'fields': {'date': (edit.payload['fields'] as Map)['date']},
        })
      else if (edit.type == EventType.transactionSplitSet &&
          edit.payload['amountCents'] != transaction.amount.cents)
        stamp.event(EventType.transactionSplitSet, {
          'transactionId': pair.id,
          'amountCents': -(edit.payload['amountCents'] as int),
          'lines': [
            for (final line in pair.lines)
              {
                ..._storedLine(line),
                'amountCents': -(edit.payload['amountCents'] as int),
              },
          ],
        }),
  ];
}

// Reconcile (ticket 09).

CommandResult _reconcile(Reconcile command, BudgetState state, _Stamp stamp) {
  if (state.account(command.accountId) == null) {
    return const Rejected(Rejection.unknownAccount);
  }
  final difference =
      command.bankBalance - state.clearedBalance(command.accountId);
  final adjust = difference != Money.zero;
  if (adjust && !command.addAdjustment) {
    return const Rejected(Rejection.reconcileMismatch);
  }
  return Accepted([
    if (adjust)
      stamp.event(EventType.transactionCreated, {
        'transactionId': newId(),
        'accountId': command.accountId,
        'date': command.date.toIso(),
        'payee': 'Reconciliation Adjustment',
        'memo': '',
        'cleared': ClearedStatus.cleared.name,
        'amountCents': difference.cents,
        'lines': [
          {
            'lineId': newId(),
            'amountCents': difference.cents,
            'category': readyToAssignCategory,
            'memo': '',
            // Only a person's review counts (ADR 0003).
            'reviewed': false,
          },
        ],
      }),
    stamp.event(EventType.reconciled, {
      'accountId': command.accountId,
      'date': command.date.toIso(),
      'clearedBalanceCents': command.bankBalance.cents,
    }),
  ]);
}
