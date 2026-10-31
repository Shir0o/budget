import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../theme.dart';
import '../widgets.dart';
import 'edit_schedule_screen.dart';
import 'target_parts.dart';
import 'transaction_parts.dart';

/// Scheduled transactions in the desktop window (ticket 67): one table of
/// next date, payee, repeat, account, Category and amount. Clicking a row
/// opens Edit schedule as a sheet. The phone's list is unchanged.
class DesktopSchedulesView extends StatefulWidget {
  const DesktopSchedulesView({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<DesktopSchedulesView> createState() => _DesktopSchedulesViewState();
}

/// The table's width: its columns and the payee's, below which the card
/// scrolls sideways.
const _tableWidth = 900.0;
const _dateColumn = 104.0;
const _repeatColumn = 132.0;
const _accountColumn = 140.0;
const _categoryColumn = 150.0;
const _amountColumn = 112.0;

class _DesktopSchedulesViewState extends State<DesktopSchedulesView> {
  BudgetState get _state => widget.engine.state;

  Future<void> _open(EditScheduleScreen screen) async {
    await openFlow<void>(context, builder: (_) => screen);
    if (mounted) setState(() {}); // The engine's state may have changed.
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final schedules = state.schedules;
    final suggestions = state.recurringSuggestions();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 20, 12),
              // Add schedule sits on the title's line, or under it when the
              // window is narrow.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      // A section in the content area has nothing to pop;
                      // this screen does.
                      if (Navigator.canPop(context))
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Back',
                          icon: const Icon(Icons.chevron_left, size: 20),
                          color: Palette.ink,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                        ),
                      const Text(
                        'Scheduled transactions',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    key: const ValueKey('schedules-add'),
                    onPressed: () =>
                        _open(EditScheduleScreen(engine: widget.engine)),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add schedule'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final table = _ScheduleTable(
                    state: state,
                    schedules: schedules,
                    onTap: (schedule) => _open(
                      EditScheduleScreen(
                        engine: widget.engine,
                        scheduleId: schedule.id,
                      ),
                    ),
                  );
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: [
                      // A narrow window scrolls the table inside its card
                      // rather than squeezing the columns out of line.
                      if (constraints.maxWidth < _tableWidth)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(width: _tableWidth, child: table),
                        )
                      else
                        table,
                      if (suggestions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _Suggestions(
                          suggestions: suggestions,
                          onAdd: (suggestion) => _open(
                            EditScheduleScreen(
                              engine: widget.engine,
                              suggestion: suggestion,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Hint(
                        'A scheduled transaction is a prediction. It counts '
                        'in nothing until you enter it, and then Review asks '
                        'you for its Category and business status.',
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

class _ScheduleTable extends StatelessWidget {
  const _ScheduleTable({
    required this.state,
    required this.schedules,
    required this.onTap,
  });

  final BudgetState state;
  final List<Schedule> schedules;
  final ValueChanged<Schedule> onTap;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(
      fontSize: 11,
      letterSpacing: 0.88,
      color: Palette.muted,
    );
    return CardBox(
      key: const ValueKey('schedules-table'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                SizedBox(
                  width: _dateColumn,
                  child: Text('NEXT DATE', style: label),
                ),
                Expanded(child: Text('PAYEE', style: label)),
                SizedBox(
                  width: _repeatColumn,
                  child: Text('REPEAT', style: label),
                ),
                SizedBox(
                  width: _accountColumn,
                  child: Text('ACCOUNT', style: label),
                ),
                SizedBox(
                  width: _categoryColumn,
                  child: Text('CATEGORY', style: label),
                ),
                SizedBox(
                  width: _amountColumn,
                  child: Text(
                    'AMOUNT',
                    style: label,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          if (schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Hint(
                'No scheduled transactions yet. Add one so the Forecast and a '
                'Driven-by-schedule Target know what is coming.',
              ),
            ),
          for (final schedule in schedules)
            _ScheduleTableRow(
              key: ValueKey('schedule-row-${schedule.id}'),
              state: state,
              schedule: schedule,
              onTap: () => onTap(schedule),
            ),
        ],
      ),
    );
  }
}

class _ScheduleTableRow extends StatelessWidget {
  const _ScheduleTableRow({
    super.key,
    required this.state,
    required this.schedule,
    required this.onTap,
  });

  final BudgetState state;
  final Schedule schedule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.divider)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _dateColumn,
            child: Text(
              formatDate(schedule.nextDue),
              style: const TextStyle(fontSize: 13, color: Palette.inkSoft),
            ),
          ),
          Expanded(
            child: Text(
              schedule.payee,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          SizedBox(
            width: _repeatColumn,
            child: Text(
              everyText(schedule.implied),
              style: const TextStyle(fontSize: 13, color: Palette.inkSoft),
            ),
          ),
          SizedBox(
            width: _accountColumn,
            child: Text(
              state.account(schedule.accountId)?.name ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Palette.inkSoft),
            ),
          ),
          SizedBox(
            width: _categoryColumn,
            child: Text(
              categoryName(state, schedule.category),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Palette.inkSoft),
            ),
          ),
          SizedBox(
            width: _amountColumn,
            child: Text(
              formatSigned(schedule.amount),
              textAlign: TextAlign.right,
              style: amountStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The repeating charges that look like schedules. Nothing is scheduled until
/// the person adds it.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.suggestions, required this.onAdd});

  final List<RecurringSuggestion> suggestions;
  final ValueChanged<RecurringSuggestion> onAdd;

  @override
  Widget build(BuildContext context) => CardBox(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                'Repeating charges',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Hint(
                'These look like regular charges. Nothing is scheduled until '
                'you add it.',
              ),
            ],
          ),
        ),
        for (final suggestion in suggestions)
          Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Palette.divider)),
            ),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.payee,
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        '${suggestion.count} charges · '
                        '${suggestion.amount.formatDollars()} · next '
                        '${formatDate(suggestion.nextDue)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => onAdd(suggestion),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontFamily: sansFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
