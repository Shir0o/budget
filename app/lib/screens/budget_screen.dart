import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_account_screen.dart';
import 'add_category_screen.dart';
import 'assign_screen.dart';
import 'budget_switcher.dart';
import 'category_screen.dart';
import 'new_transaction_screen.dart';
import 'settings_screen.dart';

/// The Budget month (canvas: Main): Ready to Assign with the Assign
/// button, then each category group's Categories with their Assigned and
/// Available for the month.
///
/// The first time a budget opens in a month, an automation run starts for
/// that month (ticket 08).
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  var _month = thisMonth();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstOpenRun());
  }

  Future<void> _firstOpenRun() async {
    final budget = widget.engine.state.budget;
    if (budget == null) return;
    final prefs = AppServicesScope.of(context).prefs;
    final month = thisMonth();
    if (await prefs.readAutomationMonth(budget.id) == month) return;
    await prefs.writeAutomationMonth(budget.id, month);
    if (!mounted) return;
    if (widget.engine.execute(RunAutomation(month: month)) is Accepted) {
      setState(() {});
    }
  }

  /// A run by hand, then this month's Suggestion Batch.
  Future<void> _assign() {
    widget.engine.execute(RunAutomation(month: thisMonth()));
    return _openFlow(AssignScreen(engine: widget.engine));
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    setState(() {}); // The engine's state may have changed.
  }

  /// Opens one of the short flows (ticket 60), then shows the new numbers.
  Future<void> _openFlow(Widget screen) async {
    await openFlow<void>(context, builder: (_) => screen);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final state = engine.state;
    // In the desktop window the toolbar carries the budget name, the month and
    // Settings, so the phone's header is not repeated here.
    final window = DesktopWindowScope.maybeOf(context);
    final month = window?.month ?? _month;
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

    return Scaffold(
      bottomNavigationBar: MainNav(engine: engine, current: Section.budget),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 14,
                children: [
                  if (window == null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Semantics(
                          button: true,
                          label: 'Switch budget',
                          child: InkWell(
                            onTap: () => showBudgetSwitcher(context),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 6,
                                children: [
                                  Text(
                                    state.budget?.name ?? '',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            MonthSwitcher(
                              month: month,
                              onChanged: (changed) {
                                if (window case final desktop?) {
                                  desktop.onMonthChanged(changed);
                                } else {
                                  setState(() => _month = changed);
                                }
                              },
                            ),
                            IconButton(
                              onPressed: () => _open(
                                SettingsScreen(
                                  engine: widget.engine,
                                  services: AppServicesScope.of(context),
                                ),
                              ),
                              tooltip: 'Settings',
                              icon: const Icon(Icons.settings_outlined),
                              color: Palette.ink,
                              iconSize: 22,
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  _ReadyToAssignCard(
                    amount: state.readyToAssign(thisMonth()),
                    onAssign: _assign,
                  ),
                ],
              ),
            ),
            const _ColumnLabels(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  for (final (group, categories) in groups) ...[
                    _GroupCard(
                      name: group.name,
                      children: [
                        for (final category in categories)
                          _CategoryRow(
                            state: state,
                            category: category,
                            month: month,
                            onTap: () => _open(
                              CategoryScreen(
                                engine: engine,
                                categoryId: category.id,
                                month: month,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (groups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 8, 8, 16),
                      child: Hint(
                        'No Categories yet. Add one to start giving your '
                        'money a job.',
                      ),
                    ),
                  const SizedBox(height: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () =>
                            _openFlow(NewTransactionScreen(engine: engine)),
                        child: const Text('New transaction'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _openFlow(AddCategoryScreen(engine: engine)),
                        child: const Text('Add category'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _openFlow(AddAccountScreen(engine: engine)),
                        child: const Text('Add account'),
                      ),
                    ],
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

class _ReadyToAssignCard extends StatelessWidget {
  const _ReadyToAssignCard({required this.amount, required this.onAssign});

  final Money amount;
  final VoidCallback onAssign;

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

  Widget _amount() => Column(
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
          color: amount.isNegative ? Palette.problemOnDark : Palette.background,
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
    ],
  );
}

const _assignedWidth = 84.0;
const _availableWidth = 96.0;

class _ColumnLabels extends StatelessWidget {
  const _ColumnLabels();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      letterSpacing: 0.88,
      color: Palette.muted,
    );
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 6, 24, 6),
      child: Row(
        children: [
          Expanded(child: Text('CATEGORY', style: style)),
          SizedBox(
            width: _assignedWidth,
            child: Text('ASSIGNED', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _availableWidth,
            child: Text('AVAILABLE', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.name, required this.children});

  final String name;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Palette.muted,
              ),
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.state,
    required this.category,
    required this.month,
    required this.onTap,
  });

  final BudgetState state;
  final Category category;
  final CalendarMonth month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = state.available(category.id, month);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Palette.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 6,
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
                  width: _assignedWidth,
                  child: Text(
                    state.assigned(category.id, month).format(),
                    textAlign: TextAlign.right,
                    style: amountStyle(fontSize: 13, color: Palette.muted),
                  ),
                ),
                SizedBox(
                  width: _availableWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AvailablePill(available),
                  ),
                ),
              ],
            ),
            for (final note in [
              if (state.cashOverspending(category.id, month).isPositive)
                'Overspent · comes out of '
                    '${monthName(month.next)}’s Ready to Assign',
              if (state.creditOverspending(category.id, month).isPositive)
                'Overspent on a card · stays as unfunded card debt',
              if (category.cardAccountId case final card?
                  when state.unfundedDebt(card, month).isPositive)
                '${state.unfundedDebt(card, month).formatDollars()} of card '
                    'debt not funded',
            ])
              Text(
                note,
                style: const TextStyle(
                  fontSize: 12,
                  color: Palette.problemText,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
