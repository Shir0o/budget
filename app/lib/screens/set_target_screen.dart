import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'target_parts.dart';

enum _Kind { repeating, byDate, keepAtLeast, schedule }

/// Sets or changes a Category's Target (canvas: SetTarget), showing what it
/// needs in [month] as you type. Driven by schedule sums the Category's
/// Scheduled Transactions, so it has no amount of its own.
class SetTargetScreen extends StatefulWidget {
  const SetTargetScreen({
    super.key,
    required this.engine,
    required this.categoryId,
    required this.month,
  });

  final BudgetEngine engine;
  final String categoryId;
  final CalendarMonth month;

  @override
  State<SetTargetScreen> createState() => _SetTargetScreenState();
}

class _SetTargetScreenState extends State<SetTargetScreen> {
  late final Target? _existing = widget.engine.state.target(widget.categoryId);
  late var _kind = switch (_existing) {
    ByDateTarget() => _Kind.byDate,
    KeepAtLeastTarget() => _Kind.keepAtLeast,
    DrivenByScheduleTarget() => _Kind.schedule,
    _ => _Kind.repeating,
  };
  late final _amount = TextEditingController(
    text: switch (_existing) {
      RepeatingTarget(:final amount) ||
      ByDateTarget(:final amount) ||
      KeepAtLeastTarget(:final amount) => amount.format(),
      _ => '',
    },
  );
  late final _every = TextEditingController(
    text:
        '${switch (_existing) {
          RepeatingTarget(:final every) => every,
          _ => 1,
        }}',
  );
  late var _interval = switch (_existing) {
    RepeatingTarget(:final interval) => interval,
    _ => TargetInterval.months,
  };
  late var _date = switch (_existing) {
    RepeatingTarget(:final nextDue) => nextDue,
    ByDateTarget(:final date) => date,
    _ => _firstOfNextMonth(),
  };
  String? _amountError;
  String? _everyError;

  static CivilDate _firstOfNextMonth() {
    final next = thisMonth().next;
    return CivilDate(next.year, next.month, 1);
  }

  @override
  void dispose() {
    _amount.dispose();
    _every.dispose();
    super.dispose();
  }

  int? get _everyValue => int.tryParse(_every.text.trim());

  /// The Target as entered, or null while a field isn't valid yet.
  Target? get _draft {
    if (_kind == _Kind.schedule) return const DrivenByScheduleTarget();
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive) return null;
    return switch (_kind) {
      _Kind.repeating => switch (_everyValue) {
        final every? when every >= 1 => RepeatingTarget(
          amount: amount,
          every: every,
          interval: _interval,
          nextDue: _date,
        ),
        _ => null,
      },
      _Kind.byDate => ByDateTarget(amount: amount, date: _date),
      _Kind.keepAtLeast => KeepAtLeastTarget(amount: amount),
      _Kind.schedule => const DrivenByScheduleTarget(),
    };
  }

  void _save() {
    final draft = _draft;
    if (draft == null) {
      final amount = Money.tryParse(_amount.text);
      setState(() {
        _amountError = amount == null || !amount.isPositive
            ? 'Enter an amount like 600.00'
            : null;
        _everyError = _kind == _Kind.repeating && (_everyValue ?? 0) < 1
            ? 'At least 1'
            : null;
      });
      return;
    }
    final result = widget.engine.execute(
      SetTarget(categoryId: widget.categoryId, target: draft),
    );
    if (result is Accepted ||
        (result is Rejected && result.reason == Rejection.noChange)) {
      Navigator.of(context).pop();
    }
  }

  void _remove() {
    widget.engine.execute(ClearTarget(categoryId: widget.categoryId));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.engine.state;
    final name = state.category(widget.categoryId)!.name;
    final draft = _draft;
    final scheduled = state.schedulesFor(widget.categoryId).length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 4),
              child: Row(
                spacing: 4,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.chevron_left, color: Palette.ink),
                  ),
                  Expanded(
                    child: Text(
                      'Target · $name',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Palette.ink,
                      foregroundColor: Palette.background,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (i, (kind, title, hint)) in const [
                          (
                            _Kind.repeating,
                            'Repeating',
                            'An amount every few days, weeks, months or years',
                          ),
                          (
                            _Kind.byDate,
                            'One-time by date',
                            'Save up an amount by a date',
                          ),
                          (
                            _Kind.keepAtLeast,
                            'Keep at least',
                            'Top up to a floor every month',
                          ),
                          (
                            _Kind.schedule,
                            'Driven by schedule',
                            'Sum this Category’s scheduled transactions',
                          ),
                        ].indexed)
                          _KindRow(
                            title: title,
                            hint: hint,
                            selected: kind == _kind,
                            divided: i > 0,
                            onTap: () => setState(() => _kind = kind),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        if (_kind == _Kind.schedule)
                          const Hint(
                            'A Driven-by-schedule Target has no amount of '
                            'its own: it needs whatever the scheduled '
                            'transactions in this Category add up to.',
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 10,
                            children: [
                              Expanded(
                                child: LabeledField(
                                  label: 'Amount',
                                  child: TextField(
                                    key: const ValueKey('target-amount'),
                                    controller: _amount,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    style: amountStyle(),
                                    decoration: InputDecoration(
                                      hintText: '0.00',
                                      errorText: _amountError,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ),
                              if (_kind == _Kind.repeating)
                                Expanded(
                                  child: LabeledField(
                                    label: 'Every',
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      spacing: 6,
                                      children: [
                                        SizedBox(
                                          width: 52,
                                          child: TextField(
                                            key: const ValueKey('target-every'),
                                            controller: _every,
                                            keyboardType: TextInputType.number,
                                            style: amountStyle(),
                                            decoration: InputDecoration(
                                              errorText: _everyError,
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                        Expanded(
                                          child: IntervalPicker(
                                            value: _interval,
                                            count: _everyValue ?? 2,
                                            onChanged: (interval) => setState(
                                              () => _interval = interval,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        if (_kind != _Kind.keepAtLeast &&
                            _kind != _Kind.schedule)
                          LabeledField(
                            label: _kind == _Kind.repeating ? 'Next due' : 'By',
                            child: DateField(
                              value: _date,
                              onChanged: (date) => setState(() => _date = date),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (draft != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        color: Palette.positivePill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        spacing: 12,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Needed in ${monthName(widget.month)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Palette.positiveText,
                                  ),
                                ),
                                Text(
                                  neededExplanation(
                                    draft,
                                    widget.month,
                                    state.availableBeforeAssigning(
                                      widget.categoryId,
                                      widget.month,
                                      draft,
                                    ),
                                    scheduled: scheduled,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Palette.positiveText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            state
                                .neededFor(
                                  widget.categoryId,
                                  draft,
                                  widget.month,
                                )
                                .format(),
                            style: amountStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Palette.positiveText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_existing != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _remove,
                      style: TextButton.styleFrom(
                        foregroundColor: Palette.problemText,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('Remove Target'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.title,
    required this.hint,
    required this.selected,
    required this.divided,
    required this.onTap,
  });

  final String title;
  final String hint;
  final bool selected;
  final bool divided;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: selected,
    child: InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: divided
              ? const Border(top: BorderSide(color: Palette.divider))
              : null,
        ),
        child: Row(
          spacing: 12,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 22,
              color: selected ? Palette.teal : Palette.muted,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  Hint(hint),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
