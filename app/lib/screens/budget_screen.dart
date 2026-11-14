import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_account_screen.dart';
import 'add_category_screen.dart';
import 'assign_screen.dart';
import 'budget_desktop.dart';
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

  /// A run by hand, then the month's Suggestion Batch. On a phone the run
  /// comes first. On desktop the sheet opens without writing anything, so Esc
  /// changes nothing, and the run happens when the batch is accepted.
  Future<void> _assign() {
    final window = DesktopWindowScope.maybeOf(context);
    if (window == null) {
      widget.engine.execute(RunAutomation(month: thisMonth()));
      return _openFlow(AssignScreen(engine: widget.engine));
    }
    return _openFlow(
      AssignScreen(
        engine: widget.engine,
        month: window.month,
        runAutomationOnAccept: true,
      ),
    );
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
    // In the desktop window the month is the wide table and side panel
    // (ticket 62); its toolbar carries the budget name, the month and
    // Settings, so the phone's header is not repeated here.
    if (DesktopWindowScope.maybeOf(context) case final window?) {
      return DesktopBudgetMonth(
        engine: engine,
        month: window.month,
        onAssign: _assign,
      );
    }
    final month = _month;
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
    // Matches the header's own check: the page's 20px side padding, so the
    // columns tighten exactly when the header stacks the month.
    final compact = _isCompact(
      MediaQuery.sizeOf(context).width - 40,
      MediaQuery.textScalerOf(context).scale(1),
    );

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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final name = Semantics(
                        button: true,
                        label: 'Switch budget',
                        child: InkWell(
                          onTap: () => showBudgetSwitcher(context),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 6,
                              children: [
                                Flexible(
                                  child: Text(
                                    state.budget?.name ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.keyboard_arrow_down, size: 16),
                              ],
                            ),
                          ),
                        ),
                      );
                      final switcher = MonthSwitcher(
                        month: month,
                        onChanged: (changed) =>
                            setState(() => _month = changed),
                      );
                      final settings = IconButton(
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
                      );
                      // A narrow phone, or large text, gives the month its
                      // own line so nothing is clipped.
                      final compact = _isCompact(
                        constraints.maxWidth,
                        MediaQuery.textScalerOf(context).scale(1),
                      );
                      if (!compact) {
                        return Row(
                          children: [
                            Expanded(child: name),
                            switcher,
                            settings,
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 6,
                        children: [
                          Row(
                            children: [
                              Expanded(child: name),
                              settings,
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: switcher,
                          ),
                        ],
                      );
                    },
                  ),
                  ReadyToAssignCard(
                    amount: state.readyToAssign(thisMonth()),
                    onAssign: _assign,
                  ),
                ],
              ),
            ),
            _ColumnLabels(compact: compact),
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
                            compact: compact,
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

/// A narrow phone, or large text: the month takes its own line, and the
/// Assigned and Available columns tighten, so nothing is clipped.
bool _isCompact(double width, double textScale) =>
    width < 340 || textScale > 1.3;

const _assignedWidth = 84.0;
const _availableWidth = 96.0;
const _compactAssignedWidth = 68.0;
const _compactAvailableWidth = 80.0;

class _ColumnLabels extends StatelessWidget {
  const _ColumnLabels({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      letterSpacing: 0.88,
      color: Palette.muted,
    );
    final assignedWidth = compact ? _compactAssignedWidth : _assignedWidth;
    final availableWidth = compact ? _compactAvailableWidth : _availableWidth;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
      child: Row(
        spacing: 8,
        children: [
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('CATEGORY', style: style),
              ),
            ),
          ),
          SizedBox(
            width: assignedWidth,
            child: const Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('ASSIGNED', style: style),
              ),
            ),
          ),
          SizedBox(
            width: availableWidth,
            child: const Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('AVAILABLE', style: style),
              ),
            ),
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
    required this.compact,
    required this.onTap,
  });

  final BudgetState state;
  final Category category;
  final CalendarMonth month;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = state.available(category.id, month);
    final assignedWidth = compact ? _compactAssignedWidth : _assignedWidth;
    final availableWidth = compact ? _compactAvailableWidth : _availableWidth;
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                SizedBox(
                  width: assignedWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        state.assigned(category.id, month).format(),
                        textAlign: TextAlign.right,
                        style: amountStyle(fontSize: 13, color: Palette.muted),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: availableWidth,
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
