part of 'engine.dart';

// Bank sync (ticket 10): one hand-run fetch, one Event group, matched to
// the transaction a same SimpleFIN id already created. The edges a fetch
// runs into: a pending charge that posts under a new id, a pending charge
// that vanishes, and a charge that looks like a line someone entered by
// hand.

CommandResult _importBankTransactions(
  ImportBankTransactions command,
  BudgetState state,
  _Stamp stamp,
) {
  for (final accountId in [
    ...command.fetchedAccounts,
    for (final entry in command.entries) entry.accountId,
  ]) {
    if (state.account(accountId) == null) {
      return const Rejected(Rejection.unknownAccount);
    }
  }

  final today = CivilDate.fromDateTime(
    DateTime.fromMillisecondsSinceEpoch(stamp._engine._nowMs()),
  );
  final events = <Event>[];
  final seen = <String>{};
  // The pending charges this fetch matched or proposed, so step 3 leaves
  // them alone.
  final replaced = <String>{};
  final proposed = <String>{};

  for (final entry in command.entries) {
    // One bank id arrives once per fetch; a repeat would duplicate the line.
    if (!seen.add('${entry.accountId}/${entry.bankId}')) continue;
    final existing = state.bankTransaction(entry.accountId, entry.bankId);
    final payee = maskSensitiveNumbers(entry.description.trim());
    final memo = maskSensitiveNumbers(entry.memo.trim());
    final cleared = entry.pending
        ? ClearedStatus.uncleared
        : ClearedStatus.cleared;

    if (existing == null) {
      final pending = state.postedReplacementFor(entry, except: replaced);
      if (pending != null) {
        replaced.add(pending.id);
        events.addAll(_replacePending(stamp, pending, entry, payee, cleared));
        continue;
      }
      final candidate = state.proposedMatchFor(entry, except: proposed);
      if (candidate != null) {
        proposed.add(candidate.id);
        final match = ProposedMatch(
          bankId: entry.bankId,
          date: entry.date,
          amount: entry.amount,
          description: payee,
          memo: memo,
          pending: entry.pending,
        );
        if (jsonEncode(candidate.pendingMatch?.toJson()) !=
            jsonEncode(match.toJson())) {
          events.add(
            stamp.event(EventType.transactionFieldsSet, {
              'transactionId': candidate.id,
              'fields': {'pendingMatch': match.toJson()},
            }),
          );
        }
        continue;
      }
      events.add(_bankCreated(stamp, entry, payee, memo, cleared));
      continue;
    }

    // Editing a Reconciled transaction needs the person's confirmation
    // (ticket 09), so a fetch changes nothing on it. A new bank amount
    // waits in Review for the person to apply.
    if (existing.cleared == ClearedStatus.reconciled) {
      if (existing.amount != entry.amount) {
        events.addAll(_flagReconciled(stamp, existing, entry.amount));
      }
      continue;
    }
    // Only the bank's own fields change. The memo, Categories, business
    // status and Review are the person's, and a fetch never takes a
    // cleared line back to pending.
    final fields = <String, Object?>{
      if (existing.date != entry.date) 'date': entry.date.toIso(),
      if (existing.payee != payee) 'payee': payee,
      if (existing.cleared == ClearedStatus.uncleared &&
          cleared == ClearedStatus.cleared)
        'cleared': cleared.name,
    };
    if (fields.isNotEmpty) {
      events.add(
        stamp.event(EventType.transactionFieldsSet, {
          'transactionId': existing.id,
          'fields': fields,
        }),
      );
    }
    if (existing.amount != entry.amount) {
      events.add(_bankAmountSet(stamp, existing, entry.amount));
    }
  }

  // Step 3: a pending charge this fetch covered and no longer reports is
  // dropped once it has been missing for 10 days. History keeps it.
  for (final accountId in command.fetchedAccounts) {
    for (final transaction in state.register(accountId)) {
      final bankId = transaction.bankId;
      if (bankId == null ||
          transaction.cleared != ClearedStatus.uncleared ||
          replaced.contains(transaction.id) ||
          seen.contains('$accountId/$bankId')) {
        continue;
      }
      if (transaction.date.addDays(bankDropAfterDays).compareTo(today) > 0) {
        continue;
      }
      events.add(
        stamp.event(EventType.transactionDeleted, {
          'transactionId': transaction.id,
        }),
      );
    }
  }

  if (events.isEmpty) return const Rejected(Rejection.noChange);
  return Accepted(events);
}

/// The Events that turn the still-pending [pending] into the posted
/// [entry]: the bank's id, date and cleared state, and its amount, keeping
/// the person's Category, business status and memo (ticket 10, step 2).
List<Event> _replacePending(
  _Stamp stamp,
  Transaction pending,
  BankEntry entry,
  String payee,
  ClearedStatus cleared,
) {
  final events = [
    stamp.event(EventType.transactionFieldsSet, {
      'transactionId': pending.id,
      'fields': {
        'bankId': entry.bankId,
        if (pending.date != entry.date) 'date': entry.date.toIso(),
        if (pending.payee != payee) 'payee': payee,
        if (pending.cleared != cleared) 'cleared': cleared.name,
      },
    }),
  ];
  if (pending.amount != entry.amount) {
    events.add(_bankAmountSet(stamp, pending, entry.amount));
  }
  return events;
}

/// The Event that gives [transaction] the bank's new [amount] and sends it
/// back to Review. A single line takes the amount. A split keeps the
/// person's lines and puts the difference in a new Unreviewed line, so the
/// lines still sum to the amount.
Event _bankAmountSet(_Stamp stamp, Transaction transaction, Money amount) {
  final note = bankChangeNote(transaction.amount, amount);
  final List<Map<String, Object?>> lines;
  if (transaction.lines.length == 1) {
    final line = transaction.lines.single;
    lines = [
      {
        ..._storedLine(line),
        'amountCents': amount.cents,
        // The person confirmed the old amount, so ask again.
        'reviewed': false,
        if (line.reviewed || line.note != null) 'note': note,
      },
    ];
  } else {
    lines = [
      for (final line in transaction.lines)
        {..._storedLine(line), 'note': ?line.note},
      {
        'lineId': newId(),
        'amountCents': (amount - transaction.amount).cents,
        'category': null,
        'memo': '',
        'reviewed': false,
        'note': note,
      },
    ];
  }
  return stamp.event(EventType.transactionSplitSet, {
    'transactionId': transaction.id,
    'amountCents': amount.cents,
    'lines': lines,
  });
}

/// The Events that put a Reconciled [transaction] the bank now reports as
/// [amount] back in Review, its amount unchanged, until a person confirms
/// an edit. None when it already waits there.
List<Event> _flagReconciled(
  _Stamp stamp,
  Transaction transaction,
  Money amount,
) {
  final note =
      'bank shows ${amount.formatDollars()}, '
      'Reconciled at ${transaction.amount.formatDollars()}';
  if (transaction.lines.every((line) => !line.reviewed && line.note == note)) {
    return const [];
  }
  return [
    stamp.event(EventType.transactionSplitSet, {
      'transactionId': transaction.id,
      'amountCents': transaction.amount.cents,
      'lines': [
        for (final line in transaction.lines)
          {..._storedLine(line), 'reviewed': false, 'note': note},
      ],
    }),
  ];
}

/// A new Unreviewed transaction for [entry], with actor `bank-sync`. No
/// Category and no business status: only a person supplies those
/// (ADR 0003).
Event _bankCreated(
  _Stamp stamp,
  BankEntry entry,
  String payee,
  String memo,
  ClearedStatus cleared,
) => stamp.event(EventType.transactionCreated, {
  'transactionId': newId(),
  'accountId': entry.accountId,
  'date': entry.date.toIso(),
  'payee': payee,
  'memo': memo,
  'cleared': cleared.name,
  'amountCents': entry.amount.cents,
  'bankId': entry.bankId,
  'lines': [
    {
      'lineId': newId(),
      'amountCents': entry.amount.cents,
      'category': null,
      'memo': '',
      'reviewed': false,
    },
  ],
});

CommandResult _confirmBankMatch(
  ConfirmBankMatch command,
  BudgetState state,
  _Stamp stamp,
) {
  if (!stamp.actor.isPerson) return const Rejected(Rejection.personRequired);
  final transaction = state.transaction(command.transactionId);
  if (transaction == null) {
    return const Rejected(Rejection.unknownTransaction);
  }
  final match = transaction.pendingMatch;
  if (match == null) return const Rejected(Rejection.noProposedMatch);
  // The line may have been edited since the match was offered.
  if (transaction.amount != match.amount) {
    return const Rejected(Rejection.matchAmountChanged);
  }
  final cleared = match.pending
      ? ClearedStatus.uncleared
      : ClearedStatus.cleared;
  return Accepted([
    stamp.event(EventType.transactionFieldsSet, {
      'transactionId': transaction.id,
      'fields': {
        'bankId': match.bankId,
        if (transaction.date != match.date) 'date': match.date.toIso(),
        if (transaction.cleared != cleared) 'cleared': cleared.name,
        'pendingMatch': null,
      },
    }),
  ]);
}

CommandResult _rejectBankMatch(
  RejectBankMatch command,
  BudgetState state,
  _Stamp stamp,
) {
  if (!stamp.actor.isPerson) return const Rejected(Rejection.personRequired);
  final transaction = state.transaction(command.transactionId);
  if (transaction == null) {
    return const Rejected(Rejection.unknownTransaction);
  }
  final match = transaction.pendingMatch;
  if (match == null) return const Rejected(Rejection.noProposedMatch);
  final entry = BankEntry(
    accountId: transaction.accountId,
    bankId: match.bankId,
    date: match.date,
    amount: match.amount,
    description: match.description,
    memo: match.memo,
    pending: match.pending,
  );
  return Accepted([
    stamp.event(EventType.transactionFieldsSet, {
      'transactionId': transaction.id,
      'fields': {'pendingMatch': null},
    }),
    _bankCreated(
      stamp,
      entry,
      maskSensitiveNumbers(entry.description.trim()),
      maskSensitiveNumbers(entry.memo.trim()),
      entry.pending ? ClearedStatus.uncleared : ClearedStatus.cleared,
    ),
  ]);
}
