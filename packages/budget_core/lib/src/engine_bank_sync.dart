part of 'engine.dart';

// Bank sync (ticket 10): one hand-run fetch, one Event group, matched to
// the transaction a same SimpleFIN id already created.

CommandResult _importBankTransactions(
  ImportBankTransactions command,
  BudgetState state,
  _Stamp stamp,
) {
  for (final entry in command.entries) {
    if (state.account(entry.accountId) == null) {
      return const Rejected(Rejection.unknownAccount);
    }
  }

  final events = <Event>[];
  final seen = <String>{};
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
      events.add(
        stamp.event(EventType.transactionCreated, {
          'transactionId': newId(),
          'accountId': entry.accountId,
          'date': entry.date.toIso(),
          'payee': payee,
          'memo': memo,
          'cleared': cleared.name,
          'amountCents': entry.amount.cents,
          'bankId': entry.bankId,
          // No Category and no business status: only a person supplies
          // those (ADR 0003).
          'lines': [
            {
              'lineId': newId(),
              'amountCents': entry.amount.cents,
              'category': null,
              'memo': '',
              'reviewed': false,
            },
          ],
        }),
      );
      continue;
    }

    final fields = <String, Object?>{
      if (existing.date != entry.date) 'date': entry.date.toIso(),
      if (existing.payee != payee) 'payee': payee,
      if (existing.memo != memo) 'memo': memo,
      if (existing.cleared != cleared) 'cleared': cleared.name,
    };
    if (fields.isNotEmpty) {
      events.add(
        stamp.event(EventType.transactionFieldsSet, {
          'transactionId': existing.id,
          'fields': fields,
        }),
      );
    }
    // A split is the person's own division of the amount, so a changed
    // bank total leaves it alone.
    if (existing.amount == entry.amount || existing.lines.length != 1) {
      continue;
    }
    final line = existing.lines.single;
    events.add(
      stamp.event(EventType.transactionSplitSet, {
        'transactionId': existing.id,
        'amountCents': entry.amount.cents,
        'lines': [
          {
            ..._storedLine(line),
            'amountCents': entry.amount.cents,
            // The person confirmed the old amount, so ask again.
            'reviewed': false,
            if (line.reviewed || line.note != null)
              'note': bankChangeNote(line.amount, entry.amount),
          },
        ],
      }),
    );
  }
  if (events.isEmpty) return const Rejected(Rejection.noChange);
  return Accepted(events);
}
