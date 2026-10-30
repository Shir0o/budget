import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

// Shared by the Category, Set Target, Assign and schedule screens (tickets
// 08 and 10).

/// `day`, `week`, `month` or `year`.
String intervalName(TargetInterval interval, {int count = 1}) {
  final name = switch (interval) {
    TargetInterval.days => 'day',
    TargetInterval.weeks => 'week',
    TargetInterval.months => 'month',
    TargetInterval.years => 'year',
  };
  return count == 1 ? name : '${name}s';
}

/// A number of days, weeks, months or years.
class IntervalPicker extends StatelessWidget {
  const IntervalPicker({
    super.key,
    required this.value,
    required this.count,
    required this.onChanged,
  });

  final TargetInterval value;

  /// The number to pluralise with.
  final int count;
  final ValueChanged<TargetInterval> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<TargetInterval>(
    key: const ValueKey('target-interval'),
    initialValue: value,
    isExpanded: true,
    items: [
      for (final interval in TargetInterval.values)
        DropdownMenuItem(
          value: interval,
          child: Text(intervalName(interval, count: count)),
        ),
    ],
    onChanged: (interval) {
      if (interval != null) onChanged(interval);
    },
  );
}

/// `every month` or `every 6 months`.
String everyText(RepeatingTarget target) => target.every == 1
    ? 'every ${intervalName(target.interval)}'
    : 'every ${target.every} ${intervalName(target.interval, count: 2)}';

/// `Repeating · $300.00 every month`, as on the Category screen.
String describeTarget(Target target, {int scheduled = 0}) => switch (target) {
  RepeatingTarget() =>
    'Repeating · ${target.amount.formatDollars()} ${everyText(target)}',
  ByDateTarget(:final date) =>
    'One-time · ${target.amount.formatDollars()} by ${formatDate(date)}',
  KeepAtLeastTarget() => 'Keep at least · ${target.amount.formatDollars()}',
  DrivenByScheduleTarget() =>
    scheduled == 1
        ? 'Driven by schedule · 1 transaction'
        : 'Driven by schedule · $scheduled transactions',
};

/// `Nov`
String shortMonth(CalendarMonth month) => formatMonth(month).substring(0, 3);

/// How [target]'s Needed in [month] is worked out, given what the Category
/// holds before assigning: `600.00 over 6 months, Nov–Apr`. [scheduled] is
/// how many Scheduled Transactions a Driven-by-schedule Target sums.
String neededExplanation(
  Target target,
  CalendarMonth month,
  Money availableBeforeAssigning, {
  int scheduled = 0,
}) {
  String over(Money amount, CalendarMonth due) {
    final remaining = amount - availableBeforeAssigning;
    if (!remaining.isPositive) {
      return 'Already holds ${amount.format()}';
    }
    final months = monthsThrough(month, due);
    return months == 1
        ? '${remaining.format()} due in ${monthName(due)}'
        : '${remaining.format()} over $months months, '
              '${shortMonth(month)}–${shortMonth(due)}';
  }

  return switch (target) {
    RepeatingTarget(isShort: true) =>
      '${target.dueDatesIn(month)} due '
          '${target.dueDatesIn(month) == 1 ? 'date' : 'dates'} × '
          '${target.amount.format()}',
    RepeatingTarget(:final amount) => over(
      amount,
      CalendarMonth.of(target.dueFor(month)),
    ),
    ByDateTarget() when target.isCompleteIn(month) => 'Complete',
    ByDateTarget(:final amount, :final date) => over(
      amount,
      CalendarMonth.of(date),
    ),
    KeepAtLeastTarget(:final amount) =>
      'Tops up to ${amount.format()} · has '
          '${availableBeforeAssigning.format()}',
    DrivenByScheduleTarget() =>
      scheduled == 1
          ? 'Sums 1 scheduled transaction'
          : 'Sums $scheduled scheduled transactions',
  };
}

/// The Target and Automation card on the Category screen (canvas:
/// Category).
class TargetSection extends StatelessWidget {
  const TargetSection({
    super.key,
    required this.state,
    required this.categoryId,
    required this.month,
    required this.onEdit,
    required this.onMode,
  });

  final BudgetState state;
  final String categoryId;
  final CalendarMonth month;
  final VoidCallback onEdit;
  final ValueChanged<AutomationMode> onMode;

  static const _modeHints = {
    AutomationMode.off: 'Automation leaves this Category alone.',
    AutomationMode.suggest:
        'Proposes Assignments for you to accept. Nothing moves until you do.',
    AutomationMode.auto:
        'Assigns to its Target on each run. Saved to Change History as '
        'automation.',
  };

  @override
  Widget build(BuildContext context) {
    final target = state.target(categoryId);
    final mode = state.automationMode(categoryId);
    return CardBox(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Target',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(
                    fontFamily: sansFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(target == null ? 'Set' : 'Edit'),
              ),
            ],
          ),
          if (target == null)
            const Hint(
              'No Target yet. Set one so automation knows what this '
              'Category needs.',
            )
          else
            _Progress(state: state, categoryId: categoryId, month: month),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              const Text(
                'Automation',
                style: TextStyle(fontSize: 13, color: Palette.muted),
              ),
              Segmented<AutomationMode>(
                options: const [
                  (AutomationMode.off, 'Off'),
                  (AutomationMode.suggest, 'Suggest'),
                  (AutomationMode.auto, 'Auto'),
                ],
                selected: mode,
                onChanged: onMode,
              ),
              Hint(_modeHints[mode]!),
            ],
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.state,
    required this.categoryId,
    required this.month,
  });

  final BudgetState state;
  final String categoryId;
  final CalendarMonth month;

  @override
  Widget build(BuildContext context) {
    final target = state.target(categoryId)!;
    final needed = state.needed(categoryId, month);
    final underfunded = state.underfunded(categoryId, month);
    final assigned = state.assigned(categoryId, month).cents;
    final fraction = !needed.isPositive || !underfunded.isPositive
        ? 1.0
        : (assigned <= 0 ? 0.0 : assigned / needed.cents);
    final complete = target is ByDateTarget && target.isCompleteIn(month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(
          describeTarget(
            target,
            scheduled: state.schedulesFor(categoryId).length,
          ),
          style: const TextStyle(fontSize: 14),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: Palette.divider,
            color: Palette.teal,
          ),
        ),
        Text(
          complete
              ? 'Complete'
              : underfunded.isPositive
              ? '${underfunded.format()} more needed in ${monthName(month)}'
              : 'Funded for ${monthName(month)}',
          style: TextStyle(
            fontSize: 12,
            color: underfunded.isPositive
                ? Palette.problemText
                : Palette.positiveText,
          ),
        ),
      ],
    );
  }
}
