import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'category_picker.dart';
import 'category_screen.dart';
import 'move_money_screen.dart';
import 'target_parts.dart';

/// This month's Suggestion Batch (canvas: Assign), accepted all at once or
/// line by line, and what it doesn't cover: overspent Categories and
/// unfunded card debt.
class AssignScreen extends StatefulWidget {
  const AssignScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<AssignScreen> createState() => _AssignScreenState();
}

class _AssignScreenState extends State<AssignScreen> {
  final _month = thisMonth();

  /// Lines the person unchecked.
  final _unchecked = <String>{};

  BudgetState get _state => widget.engine.state;

  void _accept(List<Suggestion> lines) {
    final result = widget.engine.execute(
      AcceptSuggestions(
        month: _month,
        categoryIds: [for (final line in lines) line.categoryId],
      ),
    );
    if (result is Accepted) Navigator.of(context).pop();
  }

  /// Covers [categoryId]'s overspending from Ready to Assign, as an
  /// Assignment, or from another Category, with Move money.
  Future<void> _cover(String categoryId, Money shortfall) async {
    final from = await showCategoryPicker(
      context,
      state: _state,
      month: _month,
      title: 'Cover from',
      excluding: categoryId,
    );
    if (from == null || !mounted) return;
    if (from == readyToAssignCategory) {
      await _fund(categoryId, shortfall);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MoveMoneyScreen(
          engine: widget.engine,
          fromCategoryId: from,
          toCategoryId: categoryId,
          month: _month,
          amount: shortfall,
        ),
      ),
    );
    setState(() {});
  }

  /// Assigns [shortfall] more to [categoryId] from Ready to Assign.
  Future<void> _fund(String categoryId, Money shortfall) async {
    await showAssignSheet(
      context,
      engine: widget.engine,
      categoryId: categoryId,
      month: _month,
      amount: _state.assigned(categoryId, _month) + shortfall,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final month = _month;
    final batch = state.suggestionBatch(month);
    final checked = [
      for (final line in batch)
        if (!_unchecked.contains(line.categoryId)) line,
    ];
    final total = checked.fold(Money.zero, (sum, line) => sum + line.amount);
    final readyToAssign = state.readyToAssign(month);

    final uncovered = <Widget>[
      for (final category in state.priority)
        if (state.available(category.id, month) case final available
            when available.isNegative)
          _Uncovered(
            name: category.name,
            detail: 'Overspent ${available.format()}',
            action: 'Cover',
            onTap: () => _cover(category.id, -available),
          ),
      for (final account in state.accounts)
        if (state.unfundedDebt(account.id, month) case final debt
            when debt.isPositive)
          if (state.cardPaymentCategory(account.id) case final payment?)
            _Uncovered(
              name: payment.name,
              detail:
                  '${debt.format()} not funded · automation '
                  '${state.automationMode(payment.id).name}',
              action: 'Fund',
              onTap: () => _fund(payment.id, debt),
            ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Row(
                spacing: 4,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.close, size: 22, color: Palette.ink),
                  ),
                  Text(
                    'Assign · ${monthName(month)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  _Hero(
                    readyToAssign: readyToAssign,
                    after: readyToAssign - total,
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 2,
                            children: [
                              const Text(
                                'Suggested from your Targets',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Hint(
                                'Priority order · ${monthName(month)} only · '
                                'nothing is taken out',
                              ),
                            ],
                          ),
                        ),
                        for (final line in batch)
                          _LineRow(
                            name: state.category(line.categoryId)!.name,
                            detail: _detail(state, line, month),
                            partial: _isPartial(state, line, month),
                            amount: line.amount,
                            checked: !_unchecked.contains(line.categoryId),
                            onChanged: (value) => setState(
                              () => value
                                  ? _unchecked.remove(line.categoryId)
                                  : _unchecked.add(line.categoryId),
                            ),
                          ),
                        if (batch.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Hint(
                              'Nothing to suggest. Every Target with '
                              'automation on is funded, or Ready to Assign '
                              'is 0.00.',
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF7F8F5),
                              border: Border(
                                top: BorderSide(color: Palette.cardBorder),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _lines(checked.length),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  total.format(),
                                  style: amountStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (uncovered.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        color: Palette.problemPill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 10,
                        children: [
                          const Text(
                            'Not covered by this batch',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Palette.problemText,
                            ),
                          ),
                          ...uncovered,
                          if (batch.isNotEmpty)
                            const Text(
                              'Uncheck a line above to free money for these.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF5B4A3E),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Palette.card,
                border: Border(top: BorderSide(color: Palette.cardBorder)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        child: const Text('Dismiss'),
                      ),
                      Expanded(
                        child: FilledButton(
                          onPressed: checked.isEmpty
                              ? null
                              : () => _accept(checked),
                          child: Text(
                            checked.isEmpty
                                ? 'Accept'
                                : 'Accept ${_lines(checked.length)} · '
                                      '${total.formatDollars()}',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Saved to Change History as yours',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _lines(int count) => count == 1 ? '1 line' : '$count lines';

bool _isPartial(BudgetState state, Suggestion line, CalendarMonth month) =>
    line.amount.compareTo(state.underfunded(line.categoryId, month)) < 0;

/// `Target 90.00 monthly`, `Tops up to 100.00 · has 22.40`, or for a line
/// that doesn't fill its Target, `Partial · 1,400.60 still needed by Dec 1`.
String _detail(BudgetState state, Suggestion line, CalendarMonth month) {
  final target = state.target(line.categoryId)!;
  if (_isPartial(state, line, month)) {
    final left = state.underfunded(line.categoryId, month) - line.amount;
    final by = switch (target) {
      RepeatingTarget(isShort: false) =>
        ' by ${formatDay(target.dueFor(month))}',
      ByDateTarget(:final date) => ' by ${formatDay(date)}',
      _ => '',
    };
    return 'Partial · ${left.format()} still needed$by';
  }
  return switch (target) {
    RepeatingTarget(every: 1, :final interval) =>
      'Target ${target.amount.format()} ${switch (interval) {
        TargetInterval.days => 'daily',
        TargetInterval.weeks => 'weekly',
        TargetInterval.months => 'monthly',
        TargetInterval.years => 'yearly',
      }}',
    RepeatingTarget() =>
      'Target ${target.amount.format()} ${everyText(target)}',
    ByDateTarget(:final date) =>
      'Target ${target.amount.format()} by ${formatDate(date)}',
    KeepAtLeastTarget() =>
      'Tops up to ${target.amount.format()} · has '
          '${state.availableBeforeAssigning(line.categoryId, month, target).format()}',
    DrivenByScheduleTarget() =>
      'Sums ${state.schedulesFor(line.categoryId).length} scheduled '
          '${state.schedulesFor(line.categoryId).length == 1 ? 'transaction' : 'transactions'}',
  };
}

class _Hero extends StatelessWidget {
  const _Hero({required this.readyToAssign, required this.after});

  final Money readyToAssign;
  final Money after;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
    decoration: BoxDecoration(
      color: Palette.ink,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            const Text(
              'READY TO ASSIGN',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.96,
                color: Palette.heroLabel,
              ),
            ),
            Text(
              readyToAssign.formatDollars(),
              style: amountStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: readyToAssign.isNegative
                    ? Palette.problemOnDark
                    : Palette.background,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 2,
          children: [
            const Text(
              'After this batch',
              style: TextStyle(fontSize: 12, color: Palette.heroLabel),
            ),
            Text(
              after.formatDollars(),
              style: amountStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: after.isNegative
                    ? Palette.problemOnDark
                    : Palette.heroAccent,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.name,
    required this.detail,
    required this.partial,
    required this.amount,
    required this.checked,
    required this.onChanged,
  });

  final String name;
  final String detail;
  final bool partial;
  final Money amount;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: () => onChanged(!checked),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Palette.divider)),
        ),
        child: Row(
          spacing: 12,
          children: [
            Checkbox(
              value: checked,
              onChanged: (value) => onChanged(value ?? false),
              activeColor: Palette.teal,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 15)),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: partial ? Palette.problemText : Palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            Text(amount.format(), style: amountStyle(fontSize: 15)),
          ],
        ),
      ),
    ),
  );
}

class _Uncovered extends StatelessWidget {
  const _Uncovered({
    required this.name,
    required this.detail,
    required this.action,
    required this.onTap,
  });

  final String name;
  final String detail;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 12,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 14)),
            Text(
              detail,
              style: const TextStyle(fontSize: 12, color: Palette.problemText),
            ),
          ],
        ),
      ),
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          foregroundColor: Palette.problemText,
          side: const BorderSide(color: Color(0xFFA84B0C)),
          textStyle: const TextStyle(
            fontFamily: sansFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(action),
      ),
    ],
  );
}
