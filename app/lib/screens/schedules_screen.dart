import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'edit_schedule_screen.dart';
import 'target_parts.dart';

/// Scheduled transactions (canvas: Scheduled transactions): what is coming
/// and what the recent transaction history suggests. Nothing here counts in
/// the budget until it happens, and a suggestion is only a suggestion.
class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  BudgetState get _state => widget.engine.state;

  /// Opens Edit schedule, one of the short flows (ticket 60).
  Future<void> _open(EditScheduleScreen screen) async {
    await openFlow<void>(context, builder: (_) => screen);
    setState(() {}); // The engine's state may have changed.
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final schedules = state.schedules;
    final suggestions = state.recurringSuggestions();
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Scheduled transactions'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Hint(
                      'A scheduled transaction is a prediction. It counts in '
                      'nothing until you enter it, and then Review asks you '
                      'for its Category and business status.',
                    ),
                  ),
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final schedule in schedules)
                          _ScheduleRow(
                            schedule: schedule,
                            account: state.account(schedule.accountId)?.name,
                            onTap: () => _open(
                              EditScheduleScreen(
                                engine: widget.engine,
                                scheduleId: schedule.id,
                              ),
                            ),
                          ),
                        if (schedules.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
                            child: Hint(
                              'No scheduled transactions yet. Add one so the '
                              'Forecast and a Driven-by-schedule Target know '
                              'what is coming.',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (suggestions.isNotEmpty) ...[
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
                                  'Repeating charges',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Hint(
                                  'These look like regular charges. Nothing '
                                  'is scheduled until you add it.',
                                ),
                              ],
                            ),
                          ),
                          for (final suggestion in suggestions)
                            _SuggestionRow(
                              suggestion: suggestion,
                              onTap: () => _open(
                                EditScheduleScreen(
                                  engine: widget.engine,
                                  suggestion: suggestion,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        _open(EditScheduleScreen(engine: widget.engine)),
                    child: const Text('Add schedule'),
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

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.schedule,
    required this.account,
    required this.onTap,
  });

  final Schedule schedule;
  final String? account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
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
                Text(schedule.payee, style: const TextStyle(fontSize: 15)),
                Text(
                  '${schedule.amount.formatDollars()} '
                  '${everyText(schedule.implied)} · Next '
                  '${formatDate(schedule.nextDue)}'
                  '${account == null ? '' : ' · $account'}',
                  style: const TextStyle(fontSize: 12, color: Palette.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Palette.muted),
        ],
      ),
    ),
  );
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.onTap});

  final RecurringSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
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
                Text(suggestion.payee, style: const TextStyle(fontSize: 15)),
                Text(
                  '${suggestion.count} charges · '
                  '${suggestion.amount.formatDollars()} '
                  '${everyText(RepeatingTarget(amount: Money(suggestion.amount.cents.abs()), every: suggestion.every, interval: suggestion.interval, nextDue: suggestion.nextDue))} · next ${formatDate(suggestion.nextDue)}',
                  style: const TextStyle(fontSize: 12, color: Palette.muted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
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
  );
}
