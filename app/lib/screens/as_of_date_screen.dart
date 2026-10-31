import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Go back to a date (canvas: AsOfDate): the budget as it was at the end of
/// [date], read-only, with Restore to that date as one revertable group.
class AsOfDateScreen extends StatefulWidget {
  const AsOfDateScreen({super.key, required this.engine, required this.date});

  final BudgetEngine engine;
  final CivilDate date;

  @override
  State<AsOfDateScreen> createState() => _AsOfDateScreenState();
}

class _AsOfDateScreenState extends State<AsOfDateScreen> {
  late var _date = widget.date;

  Future<void> _pick() async {
    final picked = await pickDate(context, _date);
    if (picked != null) setState(() => _date = picked);
  }

  void _restore() {
    final result = widget.engine.execute(RestoreToDate(_date));
    if (result is Accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restored to ${formatDay(_date)}. '
            'Revert it from Change History.',
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final state = engine.stateAsOf(_date);
    final month = CalendarMonth.of(_date);
    final categories = [
      for (final group in state.categoryGroups)
        for (final category in state.categories)
          if (category.groupId == group.id && !category.archived) category,
    ];
    final restore = restoreTo(engine.events, _date, by: engine.actor);
    final changes = engine.history
        .entries(filter: HistoryFilter(from: endOfDay(_date)))
        .where((e) => e.revertedBy == null && !e.isRevert)
        .length;
    final hint = switch (restore.rejection) {
      null =>
        'Undoes $changes change${changes == 1 ? '' : 's'} as one group, '
            'which you can revert.',
      Rejection.noChange => 'Nothing changed after ${formatDay(_date)}.',
      _ => 'The budget can’t be restored to ${formatDay(_date)}.',
    };

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadOnlyBar(
            date: _date,
            // A Mac window calls leaving the read-only budget Back to today.
            desktop: DesktopWindowScope.maybeOf(context) != null,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      monthName(month),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Change date',
                      child: InkWell(
                        onTap: _pick,
                        borderRadius: BorderRadius.circular(999),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Center(
                            widthFactor: 1,
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.only(
                                left: 14,
                                right: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Palette.card,
                                border: Border.all(color: Palette.fieldBorder),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 2,
                                children: [
                                  Text(
                                    formatDay(_date),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CardBox(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text(
                          'Ready to Assign',
                          style: TextStyle(fontSize: 13, color: Palette.muted),
                        ),
                      ),
                      Text(
                        state.readyToAssign(month).formatDollars(),
                        style: amountStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CardBox(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                        child: _Columns(
                          name: Text('Category'),
                          assigned: Text('Assigned'),
                          available: Text('Available'),
                          style: TextStyle(fontSize: 12, color: Palette.muted),
                        ),
                      ),
                      if (categories.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                          child: Hint('No categories yet.'),
                        ),
                      for (final category in categories)
                        Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Palette.divider),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: _Columns(
                            name: Text(
                              category.name,
                              style: const TextStyle(fontSize: 15),
                            ),
                            assigned: Text(
                              state.assigned(category.id, month).format(),
                              style: amountStyle(
                                fontSize: 14,
                                color: Palette.muted,
                              ),
                            ),
                            available: Text(
                              state.available(category.id, month).format(),
                              style: amountStyle(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: Palette.card,
              border: Border(top: BorderSide(color: Palette.cardBorder)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: restore.rejection == null ? _restore : null,
                      child: Text('Restore to ${formatDay(_date)}'),
                    ),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Palette.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `Viewing Oct 31, 2026 · read-only` and Exit — Back to today on a Mac,
/// where the budget behind the bar is the whole window — on dark.
class _ReadOnlyBar extends StatelessWidget {
  const _ReadOnlyBar({required this.date, this.desktop = false});

  final CivilDate date;

  /// A Mac window's bar offers Back to today instead of Exit.
  final bool desktop;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: ColoredBox(
      color: Palette.ink,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
          child: Row(
            spacing: 10,
            children: [
              const Icon(Icons.schedule, size: 18, color: Palette.onDarkAccent),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 14,
                      color: Palette.background,
                    ),
                    children: [
                      const TextSpan(text: 'Viewing '),
                      TextSpan(
                        text: formatDate(date),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' · read-only'),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: Palette.onDarkAccent,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontFamily: sansFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(desktop ? 'Back to today' : 'Exit'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A Category name with right-aligned Assigned and Available columns.
class _Columns extends StatelessWidget {
  const _Columns({
    required this.name,
    required this.assigned,
    required this.available,
    this.style,
  });

  final Widget name;
  final Widget assigned;
  final Widget available;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    Widget column(double width, Widget child) => SizedBox(
      width: width,
      child: Align(alignment: Alignment.centerRight, child: child),
    );
    final row = Row(
      children: [
        Expanded(child: name),
        column(84, assigned),
        column(96, available),
      ],
    );
    return style == null
        ? row
        : DefaultTextStyle.merge(style: style, child: row);
  }
}
