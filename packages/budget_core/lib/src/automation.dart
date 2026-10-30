part of 'budget_state.dart';

// Targets, priority and automation runs (ticket 08).

/// One proposed Assignment from an automation run.
final class Suggestion {
  const Suggestion({required this.categoryId, required this.amount});

  final String categoryId;

  /// Positive. Automation never takes money out of a Category.
  final Money amount;

  @override
  bool operator ==(Object other) =>
      other is Suggestion &&
      other.categoryId == categoryId &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(categoryId, amount);

  @override
  String toString() => 'Suggestion($categoryId, $amount)';
}

extension AutomationQueries on BudgetState {
  /// [categoryId]'s Target, or null when it has none.
  Target? target(String categoryId) => _targets[categoryId];

  /// Suggest unless set, except Card Payment Categories, which are off.
  AutomationMode automationMode(String categoryId) =>
      _modes[categoryId] ??
      (_categories[categoryId]?.cardAccountId != null
          ? AutomationMode.off
          : AutomationMode.suggest);

  /// Every active Category in the order automation fills them: the order
  /// the person set, then the rest in their order on screen (group by
  /// group).
  List<Category> get priority {
    final active = [
      for (final group in _groups.values)
        for (final category in _categories.values)
          if (category.groupId == group.id && !category.archived) category,
    ];
    final ranked = {
      for (final id in _priority)
        if (_categories[id] case final category? when !category.archived)
          category,
    };
    return [...ranked, ...active.where((c) => !ranked.contains(c))];
  }

  /// Carry + Activity: what [categoryId] holds in [month] before any
  /// Assignment.
  Money availableBeforeAssigning(String categoryId, CalendarMonth month) =>
      carry(categoryId, month) + activity(categoryId, month);

  /// What [categoryId]'s Target needs in [month]. Zero without a Target. A
  /// Driven-by-schedule Target sums the Category's Scheduled Transactions
  /// (ticket 10), which is why the sum lives in `neededFor`.
  Money needed(String categoryId, CalendarMonth month) {
    final target = this.target(categoryId);
    return target == null ? Money.zero : neededFor(categoryId, target, month);
  }

  /// max(0, Needed − Assigned).
  Money underfunded(String categoryId, CalendarMonth month) {
    final gap = needed(categoryId, month) - assigned(categoryId, month);
    return gap.isPositive ? gap : Money.zero;
  }

  /// The Suggestion Batch for [month]: the suggest-mode lines of a run.
  List<Suggestion> suggestionBatch(CalendarMonth month) =>
      _fill(month, AutomationMode.suggest);

  /// The Assignments a run makes for auto-mode Categories in [month].
  List<Suggestion> autoAssignments(CalendarMonth month) =>
      _fill(month, AutomationMode.auto);

  /// Goes through the Categories in [priority] order, giving each one that
  /// isn't off min(Underfunded, remaining Ready to Assign), and keeps the
  /// lines for [mode]. It stops when Ready to Assign reaches 0, so it never
  /// takes it negative, and it only assigns to [month].
  ///
  /// Once a run's auto lines are assigned, those Categories are no longer
  /// underfunded and Ready to Assign is down by the same amount, so the
  /// suggest lines come out the same as before.
  List<Suggestion> _fill(CalendarMonth month, AutomationMode mode) {
    var remaining = readyToAssign(month);
    final lines = <Suggestion>[];
    for (final category in priority) {
      if (!remaining.isPositive) break;
      final categoryMode = automationMode(category.id);
      if (categoryMode == AutomationMode.off) continue;
      final gap = underfunded(category.id, month);
      if (!gap.isPositive) continue;
      final amount = gap.compareTo(remaining) < 0 ? gap : remaining;
      remaining -= amount;
      if (categoryMode == mode) {
        lines.add(Suggestion(categoryId: category.id, amount: amount));
      }
    }
    return lines;
  }
}
