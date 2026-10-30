part of 'engine.dart';

// Scheduled Transactions (ticket 10). They never count in the budget: only
// EnterSchedule writes a real Transaction, and it is Unreviewed.

CommandResult _createSchedule(
  CreateSchedule command,
  BudgetState state,
  _Stamp stamp,
) {
  if (state.account(command.accountId) == null) {
    return const Rejected(Rejection.unknownAccount);
  }
  if (_checkText([command.payee, command.memo]) case final rejected?) {
    return rejected;
  }
  if (_checkSchedule(
        state,
        amount: command.amount,
        category: command.category,
        every: command.every,
      )
      case final rejected?) {
    return rejected;
  }
  final id = newId();
  return Accepted([
    stamp.event(EventType.scheduleCreated, {
      'scheduleId': id,
      ..._scheduleFields(
        accountId: command.accountId,
        payee: command.payee,
        memo: command.memo,
        amount: command.amount,
        category: command.category,
        every: command.every,
        interval: command.interval,
        nextDue: command.nextDue,
      ),
    }),
  ]);
}

CommandResult _editSchedule(
  EditSchedule command,
  BudgetState state,
  _Stamp stamp,
) {
  final schedule = state.schedule(command.scheduleId);
  if (schedule == null) return const Rejected(Rejection.unknownSchedule);
  if (_checkText([command.payee, command.memo]) case final rejected?) {
    return rejected;
  }
  if (command.accountId case final accountId?
      when state.account(accountId) == null) {
    return const Rejected(Rejection.unknownAccount);
  }
  final amount = command.amount ?? schedule.amount;
  final category = command.category ?? schedule.category;
  final every = command.every ?? schedule.every;
  if (_checkSchedule(
        state,
        amount: amount,
        category: category,
        every: every,
        keep: schedule.category,
      )
      case final rejected?) {
    return rejected;
  }
  final payee = command.payee?.trim();
  final memo = command.memo?.trim();
  final fields = <String, Object?>{
    if (command.accountId case final id? when id != schedule.accountId)
      'accountId': id,
    if (payee != null && payee != schedule.payee) 'payee': payee,
    if (memo != null && memo != schedule.memo) 'memo': memo,
    if (amount != schedule.amount) 'amountCents': amount.cents,
    if (category != schedule.category) 'category': category,
    if (every != schedule.every) 'every': every,
    if (command.interval case final interval?
        when interval != schedule.interval)
      'interval': interval.name,
    if (command.nextDue case final nextDue? when nextDue != schedule.nextDue)
      'nextDue': nextDue.toIso(),
  };
  if (fields.isEmpty) return const Rejected(Rejection.noChange);
  return Accepted([
    stamp.event(EventType.scheduleFieldsSet, {
      'scheduleId': schedule.id,
      'fields': fields,
    }),
  ]);
}

CommandResult _deleteSchedule(
  DeleteSchedule command,
  BudgetState state,
  _Stamp stamp,
) {
  final schedule = state.schedule(command.scheduleId);
  if (schedule == null) return const Rejected(Rejection.unknownSchedule);
  return Accepted([
    stamp.event(EventType.scheduleDeleted, {'scheduleId': schedule.id}),
  ]);
}

CommandResult _enterSchedule(
  EnterSchedule command,
  BudgetState state,
  _Stamp stamp,
) {
  final schedule = state.schedule(command.scheduleId);
  if (schedule == null) return const Rejected(Rejection.unknownSchedule);
  if (state.account(schedule.accountId) == null) {
    return const Rejected(Rejection.unknownAccount);
  }
  return Accepted([
    stamp.event(EventType.transactionCreated, {
      'transactionId': newId(),
      'accountId': schedule.accountId,
      'date': schedule.nextDue.toIso(),
      'payee': schedule.payee,
      'memo': schedule.memo,
      'cleared': ClearedStatus.uncleared.name,
      'amountCents': schedule.amount.cents,
      // Unreviewed: the person still chooses its business status in Review
      // (ADR 0003).
      'lines': [
        {
          'lineId': newId(),
          'amountCents': schedule.amount.cents,
          'category': schedule.category,
          'memo': '',
          'reviewed': false,
        },
      ],
    }),
    stamp.event(EventType.scheduleFieldsSet, {
      'scheduleId': schedule.id,
      'fields': {'nextDue': schedule.following.toIso()},
    }),
  ]);
}

/// Rejects a Scheduled Transaction with no amount, an interval of 0 or
/// fewer, or a Category the money may not go to: income goes to Ready to
/// Assign, an outflow needs an active Category. A Category a schedule
/// already has is kept even if it has since been archived, as an edit does
/// for a transaction's lines.
Rejected? _checkSchedule(
  BudgetState state, {
  required Money amount,
  required String category,
  required int every,
  String? keep,
}) {
  if (amount == Money.zero) return const Rejected(Rejection.zeroAmount);
  if (every < 1) return const Rejected(Rejection.intervalMustBePositive);
  if (amount.isPositive) {
    return category == readyToAssignCategory
        ? null
        : const Rejected(Rejection.scheduleCategoryRequired);
  }
  if (category == readyToAssignCategory) {
    return const Rejected(Rejection.scheduleCategoryRequired);
  }
  return category == keep ? null : _checkActive(state, category);
}

/// The stored fields of a Scheduled Transaction, in the same keys as a
/// [EditSchedule] sets.
Map<String, Object?> _scheduleFields({
  required String accountId,
  required String payee,
  required String memo,
  required Money amount,
  required String category,
  required int every,
  required TargetInterval interval,
  required CivilDate nextDue,
}) => {
  'accountId': accountId,
  'payee': payee,
  'memo': memo,
  'amountCents': amount.cents,
  'category': category,
  'every': every,
  'interval': interval.name,
  'nextDue': nextDue.toIso(),
};
