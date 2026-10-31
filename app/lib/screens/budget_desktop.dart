import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_category_screen.dart';
import 'move_money_screen.dart';
import 'set_target_screen.dart';
import 'target_parts.dart';

/// The Ready to Assign card, on the phone and in the desktop window. Given a
/// [month] and this month's [overspending], it also says how much of it comes
/// out of next month's Ready to Assign (ticket 07).
class ReadyToAssignCard extends StatelessWidget {
  const ReadyToAssignCard({
    super.key,
    required this.amount,
    required this.onAssign,
    this.month,
    this.overspending,
  });

  final Money amount;
  final VoidCallback onAssign;

  /// Null on a phone, which shows the card without the Overspending line.
  final CalendarMonth? month;

  /// This month's cash Overspending across every Category.
  final Money? overspending;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
    decoration: BoxDecoration(
      color: Palette.ink,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 12,
      children: [
        Expanded(child: _amount()),
        FilledButton(
          onPressed: onAssign,
          style: FilledButton.styleFrom(
            backgroundColor: Palette.heroAccent,
            foregroundColor: Palette.onHeroAccent,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: const Text('Assign'),
        ),
      ],
    ),
  );

  Widget _amount() {
    final month = this.month;
    final overspending = this.overspending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
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
          amount.formatDollars(),
          style: amountStyle(
            fontSize: 34,
            fontWeight: FontWeight.w600,
            color: amount.isNegative
                ? Palette.problemOnDark
                : Palette.background,
          ).copyWith(letterSpacing: -0.68),
        ),
        if (amount.isNegative)
          const Text(
            'Over-assigned',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Palette.problemOnDark,
            ),
          ),
        if (month != null && overspending != null && overspending.isPositive)
          Text(
            '${overspending.formatDollars()} of Overspending comes out of '
            '${monthName(month.next)}’s Ready to Assign',
            key: const ValueKey('rta-overspending'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Palette.problemOnDark,
            ),
          ),
      ],
    );
  }
}

/// The desktop Budget month (ticket 62): Ready to Assign above a wide
/// Category table, with the selected Category's panel beside the table — or
/// below it when the content area is narrow. The month stays visible while
/// the panel is open, so a Category is read without leaving it.
class DesktopBudgetMonth extends StatefulWidget {
  const DesktopBudgetMonth({
    super.key,
    required this.engine,
    required this.month,
    required this.onAssign,
  });

  final BudgetEngine engine;
  final CalendarMonth month;
  final VoidCallback onAssign;

  @override
  State<DesktopBudgetMonth> createState() => _DesktopBudgetMonthState();
}

/// Below this content width the panel wraps under the table.
const _panelBesideWidth = 760.0;
const _panelWidth = 360.0;

/// The money columns, shared by the header, group totals and rows so they
/// line up.
const _assignedColumn = 100.0;
const _activityColumn = 100.0;
const _availableColumn = 112.0;

class _DesktopBudgetMonthState extends State<DesktopBudgetMonth> {
  String? _selectedId;

  BudgetState get _state => widget.engine.state;

  Future<void> _addCategory() async {
    await openFlow<void>(
      context,
      builder: (_) => AddCategoryScreen(engine: widget.engine),
    );
    if (mounted) setState(() {});
  }

  Future<void> _moveMoney(String fromCategoryId) async {
    await openFlow<void>(
      context,
      builder: (_) => MoveMoneyScreen(
        engine: widget.engine,
        fromCategoryId: fromCategoryId,
        month: widget.month,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final month = widget.month;
    final groups = [
      for (final group in state.categoryGroups)
        (
          group,
          [
            for (final category in state.categories)
              if (category.groupId == group.id && !category.archived) category,
          ],
        ),
    ].where((entry) => entry.$2.isNotEmpty).toList();
    // The Category the panel shows, unless it has since been archived.
    final selected = switch (state.category(_selectedId ?? '')) {
      final category? when !category.archived => category,
      _ => null,
    };
    final overspending = state.categories.fold<Money>(
      Money.zero,
      (sum, category) => sum + state.cashOverspending(category.id, month),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: ReadyToAssignCard(
                amount: state.readyToAssign(month),
                month: month,
                overspending: overspending,
                onAssign: widget.onAssign,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final table = _CategoryTable(
                    key: const ValueKey('budget-table'),
                    state: state,
                    month: month,
                    groups: groups,
                    selectedId: selected?.id,
                    onSelect: (category) =>
                        setState(() => _selectedId = category.id),
                    onAddCategory: _addCategory,
                    onMoveMoney: selected == null
                        ? null
                        : () => _moveMoney(selected.id),
                  );
                  final panel = selected == null
                      ? null
                      : _CategoryPanel(
                          key: const ValueKey('category-panel'),
                          engine: widget.engine,
                          state: state,
                          category: selected,
                          month: month,
                          onClose: () => setState(() => _selectedId = null),
                          onChanged: () => setState(() {}),
                        );
                  if (constraints.maxWidth < _panelBesideWidth) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: [table, ?panel],
                      ),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          child: table,
                        ),
                      ),
                      if (panel != null)
                        SizedBox(
                          width: _panelWidth,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(0, 0, 12, 16),
                            child: panel,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line under a Category in the table: what is wrong, or how its Target
/// stands, and whether it is a problem.
(String, bool) _status(
  BudgetState state,
  Category category,
  CalendarMonth month,
) {
  final cash = state.cashOverspending(category.id, month);
  if (cash.isPositive) {
    return (
      'Overspent · ${cash.formatDollars()} comes out of '
          '${monthName(month.next)}’s Ready to Assign',
      true,
    );
  }
  final credit = state.creditOverspending(category.id, month);
  if (credit.isPositive) {
    return ('Overspent on a card · stays as unfunded card debt', true);
  }
  if (category.cardAccountId case final card?
      when state.unfundedDebt(card, month).isPositive) {
    return (
      '${state.unfundedDebt(card, month).formatDollars()} of card debt '
          'not funded',
      true,
    );
  }
  final target = state.target(category.id);
  if (target == null) return ('No Target', false);
  final underfunded = state.underfunded(category.id, month);
  return underfunded.isPositive
      ? (
          'Target · ${underfunded.format()} more needed in ${monthName(month)}',
          false,
        )
      : ('Target funded', false);
}

class _CategoryTable extends StatelessWidget {
  const _CategoryTable({
    super.key,
    required this.state,
    required this.month,
    required this.groups,
    required this.selectedId,
    required this.onSelect,
    required this.onAddCategory,
    required this.onMoveMoney,
  });

  final BudgetState state;
  final CalendarMonth month;
  final List<(CategoryGroup, List<Category>)> groups;
  final String? selectedId;
  final ValueChanged<Category> onSelect;
  final VoidCallback onAddCategory;

  /// Null until a Category is selected: money moves from a Category.
  final VoidCallback? onMoveMoney;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(
      fontSize: 11,
      letterSpacing: 0.88,
      color: Palette.muted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: [
              Expanded(child: Text('CATEGORY', style: label)),
              SizedBox(
                width: _assignedColumn,
                child: Text(
                  'ASSIGNED',
                  style: label,
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: _activityColumn,
                child: Text(
                  'ACTIVITY',
                  style: label,
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: _availableColumn,
                child: Text(
                  'AVAILABLE',
                  style: label,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        for (final (group, categories) in groups) ...[
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Palette.card,
              border: Border.all(color: Palette.cardBorder),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GroupTotals(
                    key: ValueKey('group-${group.id}'),
                    name: group.name,
                    assigned: categories.fold<Money>(
                      Money.zero,
                      (sum, c) => sum + state.assigned(c.id, month),
                    ),
                    activity: categories.fold<Money>(
                      Money.zero,
                      (sum, c) => sum + state.activity(c.id, month),
                    ),
                    available: categories.fold<Money>(
                      Money.zero,
                      (sum, c) => sum + state.available(c.id, month),
                    ),
                  ),
                  for (final category in categories)
                    _CategoryTableRow(
                      state: state,
                      category: category,
                      month: month,
                      selected: category.id == selectedId,
                      onTap: () => onSelect(category),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Hint(
              'No Categories yet. Add one to start giving your money a job.',
            ),
          ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onAddCategory,
                child: const Text('Add category'),
              ),
            ),
            Expanded(
              child: OutlinedButton(
                onPressed: onMoveMoney,
                child: const Text('Move money'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupTotals extends StatelessWidget {
  const _GroupTotals({
    super.key,
    required this.name,
    required this.assigned,
    required this.activity,
    required this.available,
  });

  final String name;
  final Money assigned;
  final Money activity;
  final Money available;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Palette.muted,
            ),
          ),
        ),
        SizedBox(
          width: _assignedColumn,
          child: Text(
            assigned.format(),
            textAlign: TextAlign.right,
            style: amountStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Palette.inkSoft,
            ),
          ),
        ),
        SizedBox(
          width: _activityColumn,
          child: Text(
            activity.format(),
            textAlign: TextAlign.right,
            style: amountStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Palette.inkSoft,
            ),
          ),
        ),
        SizedBox(
          width: _availableColumn,
          child: Align(
            alignment: Alignment.centerRight,
            child: AvailablePill(available),
          ),
        ),
      ],
    ),
  );
}

class _CategoryTableRow extends StatelessWidget {
  const _CategoryTableRow({
    required this.state,
    required this.category,
    required this.month,
    required this.selected,
    required this.onTap,
  });

  final BudgetState state;
  final Category category;
  final CalendarMonth month;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (status, problem) = _status(state, category, month);
    return InkWell(
      key: ValueKey('category-${category.id}'),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Palette.zeroPill : null,
          border: const Border(top: BorderSide(color: Palette.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 4,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                SizedBox(
                  width: _assignedColumn,
                  child: Text(
                    state.assigned(category.id, month).format(),
                    textAlign: TextAlign.right,
                    style: amountStyle(fontSize: 13, color: Palette.muted),
                  ),
                ),
                SizedBox(
                  width: _activityColumn,
                  child: Text(
                    state.activity(category.id, month).format(),
                    textAlign: TextAlign.right,
                    style: amountStyle(fontSize: 13, color: Palette.inkSoft),
                  ),
                ),
                SizedBox(
                  width: _availableColumn,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AvailablePill(state.available(category.id, month)),
                  ),
                ),
              ],
            ),
            Text(
              status,
              key: ValueKey('status-${category.id}'),
              style: TextStyle(
                fontSize: 12,
                color: problem ? Palette.problemText : Palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The selected Category's panel: its Available, its Target and Automation
/// Mode, and the month's recent activity.
class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({
    super.key,
    required this.engine,
    required this.state,
    required this.category,
    required this.month,
    required this.onClose,
    required this.onChanged,
  });

  final BudgetEngine engine;
  final BudgetState state;
  final Category category;
  final CalendarMonth month;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  Future<void> _editTarget(BuildContext context) async {
    await openFlow<void>(
      context,
      builder: (_) => SetTargetScreen(
        engine: engine,
        categoryId: category.id,
        month: month,
      ),
    );
    onChanged();
  }

  void _setMode(AutomationMode mode) {
    engine.execute(SetAutomationMode(categoryId: category.id, mode: mode));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final available = state.available(category.id, month);
    final lines = [
      for (final transaction in state.transactions.reversed)
        if (CalendarMonth.of(transaction.date) == month)
          for (final line in transaction.lines)
            if (line.category == category.id) (transaction, line),
    ].take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        CardBox(
          padding: const EdgeInsets.fromLTRB(18, 10, 10, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    tooltip: 'Close panel',
                    icon: const Icon(Icons.close, size: 20),
                    color: Palette.muted,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                  ),
                ],
              ),
              Text(
                '${state.categoryGroup(category.groupId)?.name} · '
                '${formatMonth(month)}',
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
              const SizedBox(height: 10),
              const Text(
                'AVAILABLE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.88,
                  color: Palette.muted,
                ),
              ),
              Text(
                available.formatDollars(),
                key: const ValueKey('panel-available'),
                style: amountStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: available.isNegative
                      ? Palette.problemText
                      : available.isPositive
                      ? Palette.positiveText
                      : Palette.ink,
                ).copyWith(letterSpacing: -0.6),
              ),
            ],
          ),
        ),
        TargetSection(
          state: state,
          categoryId: category.id,
          month: month,
          onEdit: () => _editTarget(context),
          onMode: _setMode,
        ),
        CardBox(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Text(
                  'Recent activity',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              for (final (transaction, line) in lines)
                _PanelActivityRow(
                  payee: transaction.payee,
                  detail:
                      '${formatDay(transaction.date)} · '
                      '${state.account(transaction.accountId)?.name}',
                  amount: line.amount,
                ),
              if (lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: Hint('No transactions this month.'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelActivityRow extends StatelessWidget {
  const _PanelActivityRow({
    required this.payee,
    required this.detail,
    required this.amount,
  });

  final String payee;
  final String detail;
  final Money amount;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Palette.divider)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(payee, style: const TextStyle(fontSize: 14)),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
            ],
          ),
        ),
        Text(amount.format(), style: amountStyle(fontSize: 13)),
      ],
    ),
  );
}
