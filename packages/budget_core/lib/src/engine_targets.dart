part of 'engine.dart';

// Targets, priority and automation runs (ticket 08).

CommandResult _setTarget(SetTarget command, BudgetState state, _Stamp stamp) {
  final id = command.categoryId;
  if (_checkActive(state, id) case final rejected?) return rejected;
  final target = command.target;
  switch (target) {
    // A Driven-by-schedule Target has no amount of its own: it sums the
    // Category's Scheduled Transactions.
    case RepeatingTarget(:final amount) ||
        ByDateTarget(:final amount) ||
        KeepAtLeastTarget(:final amount):
      if (!amount.isPositive) {
        return const Rejected(Rejection.targetAmountMustBePositive);
      }
    case DrivenByScheduleTarget():
  }
  if (target is RepeatingTarget && target.every < 1) {
    return const Rejected(Rejection.intervalMustBePositive);
  }
  if (jsonEncode(state.target(id)?.toJson()) == jsonEncode(target.toJson())) {
    return const Rejected(Rejection.noChange);
  }
  return Accepted([
    stamp.event(EventType.targetSet, {
      'categoryId': id,
      'target': target.toJson(),
    }),
  ]);
}

CommandResult _clearTarget(
  ClearTarget command,
  BudgetState state,
  _Stamp stamp,
) {
  final id = command.categoryId;
  if (state.category(id) == null) {
    return const Rejected(Rejection.unknownCategory);
  }
  if (state.target(id) == null) return const Rejected(Rejection.noChange);
  return Accepted([
    stamp.event(EventType.targetCleared, {'categoryId': id}),
  ]);
}

CommandResult _setAutomationMode(
  SetAutomationMode command,
  BudgetState state,
  _Stamp stamp,
) {
  final id = command.categoryId;
  if (_checkActive(state, id) case final rejected?) return rejected;
  if (state.automationMode(id) == command.mode) {
    return const Rejected(Rejection.noChange);
  }
  return Accepted([
    stamp.event(EventType.automationModeSet, {
      'categoryId': id,
      'mode': command.mode.name,
    }),
  ]);
}

CommandResult _setPriority(
  SetPriority command,
  BudgetState state,
  _Stamp stamp,
) {
  final ids = command.categoryIds;
  if (ids.any((id) => state.category(id) == null)) {
    return const Rejected(Rejection.unknownCategory);
  }
  if (ids.toSet().length != ids.length) {
    return const Rejected(Rejection.duplicateCategory);
  }
  final current = [for (final c in state.priority) c.id];
  final next = [...ids, ...current.where((id) => !ids.contains(id))];
  if (next.join(',') == current.join(',')) {
    return const Rejected(Rejection.noChange);
  }
  return Accepted([
    stamp.event(EventType.prioritySet, {'categoryIds': ids}),
  ]);
}

CommandResult _acceptSuggestions(
  AcceptSuggestions command,
  BudgetState state,
  _Stamp stamp,
) {
  final batch = {
    for (final line in state.suggestionBatch(command.month))
      line.categoryId: line.amount,
  };
  final ids = command.categoryIds.toSet();
  if (ids.isEmpty) return const Rejected(Rejection.noChange);
  if (!ids.every(batch.containsKey)) {
    return const Rejected(Rejection.notSuggested);
  }
  return Accepted([
    for (final MapEntry(key: id, value: amount) in batch.entries)
      if (ids.contains(id))
        _assignment(
          stamp,
          id,
          command.month,
          amount,
          note: acceptedSuggestionNote,
        ),
  ]);
}

CommandResult _runAutomation(
  RunAutomation command,
  BudgetState state,
  _Stamp stamp,
) {
  final lines = state.autoAssignments(command.month);
  if (lines.isEmpty) return const Rejected(Rejection.noChange);
  return Accepted([
    for (final line in lines)
      _assignment(stamp, line.categoryId, command.month, line.amount),
  ]);
}

/// Whether [events], accepted from a person against [before], review an
/// income line: a ReviewSet to Ready to Assign (ticket 04), or a line in
/// Ready to Assign that becomes Reviewed.
bool _reviewsIncome(BudgetState before, List<Event> events) {
  for (final event in events) {
    if (!event.actor.isPerson) continue;
    final p = event.payload;
    switch (event.type) {
      // EventType.reviewSet arrives with ticket 04.
      case 'ReviewSet' when p['category'] == readyToAssignCategory:
        return true;
      case EventType.transactionCreated || EventType.transactionSplitSet:
        final was = before.transaction(p['transactionId'] as String);
        for (final line in (p['lines'] as List).cast<Map>()) {
          if (line['category'] != readyToAssignCategory ||
              line['reviewed'] != true) {
            continue;
          }
          final old = was?.lines.where((l) => l.id == line['lineId']);
          final already =
              old != null &&
              old.any((l) => l.reviewed && l.category == readyToAssignCategory);
          if (!already) return true;
        }
    }
  }
  return false;
}
