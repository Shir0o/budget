import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../theme.dart';
import '../widgets.dart';
import 'history_screen.dart';
import 'move_money_screen.dart';
import 'set_target_screen.dart';
import 'target_parts.dart';

/// Category detail for one month (canvas: Category): Carry + Assigned +
/// Activity = Available, its Target and Automation Mode, and the month's
/// transactions.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    super.key,
    required this.engine,
    required this.categoryId,
    required this.month,
  });

  final BudgetEngine engine;
  final String categoryId;
  final CalendarMonth month;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

/// `+ 300.00` or `− 280.00`.
String _signed(Money amount) =>
    '${amount.isNegative ? '−' : '+'} ${Money(amount.cents.abs()).format()}';

class _CategoryScreenState extends State<CategoryScreen> {
  BudgetState get _state => widget.engine.state;

  Future<void> _assign() async {
    await showAssignSheet(
      context,
      engine: widget.engine,
      categoryId: widget.categoryId,
      month: widget.month,
    );
    setState(() {});
  }

  Future<void> _editTarget() async {
    await openFlow<void>(
      context,
      builder: (_) => SetTargetScreen(
        engine: widget.engine,
        categoryId: widget.categoryId,
        month: widget.month,
      ),
    );
    setState(() {});
  }

  Future<void> _moveMoney() async {
    await openFlow<void>(
      context,
      builder: (_) => MoveMoneyScreen(
        engine: widget.engine,
        fromCategoryId: widget.categoryId,
        month: widget.month,
      ),
    );
    setState(() {});
  }

  Future<void> _history() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntityHistoryScreen(
          engine: widget.engine,
          entity: EntityRef.category(widget.categoryId),
          name: _state.category(widget.categoryId)!.name,
        ),
      ),
    );
    if (!mounted) return;
    // A revert may have removed the Category.
    if (_state.category(widget.categoryId) == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  Future<void> _archive() async {
    final result = widget.engine.execute(
      ArchiveCategory(categoryId: widget.categoryId, month: widget.month),
    );
    if (result is Accepted) {
      Navigator.of(context).pop();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move its money first'),
        content: const Text(
          'A Category can only be archived once its Available is 0.00. '
          'Move it to another Category or back to Ready to Assign.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final id = widget.categoryId;
    final month = widget.month;
    final category = state.category(id)!;
    final available = state.available(id, month);
    final lines = [
      for (final transaction in state.transactions.reversed)
        if (CalendarMonth.of(transaction.date) == month)
          for (final line in transaction.lines)
            if (line.category == id) (transaction, line),
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
                    tooltip: 'Back to budget',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.chevron_left, color: Palette.ink),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${state.categoryGroup(category.groupId)?.name} · '
                          '${formatMonth(month)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Palette.muted,
                          ),
                        ),
                        Text(
                          category.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'Category options',
                    icon: const Icon(Icons.more_vert, color: Palette.muted),
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _history,
                        child: const Text('Change History'),
                      ),
                      PopupMenuItem(
                        value: _archive,
                        child: const Text('Archive category'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  CardBox(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 14,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            const Text(
                              'AVAILABLE',
                              style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 0.96,
                                color: Palette.muted,
                              ),
                            ),
                            Text(
                              available.formatDollars(),
                              style: amountStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w600,
                                color: available.isNegative
                                    ? Palette.problemText
                                    : available.isPositive
                                    ? Palette.positiveText
                                    : Palette.ink,
                              ).copyWith(letterSpacing: -0.72),
                            ),
                          ],
                        ),
                        _Breakdown(
                          rows: [
                            (
                              'Carried from ${monthName(month.previous)}',
                              state.carry(id, month).format(),
                            ),
                            (
                              'Assigned this month',
                              _signed(state.assigned(id, month)),
                            ),
                            ('Activity', _signed(state.activity(id, month))),
                          ],
                          total: available.format(),
                        ),
                        Row(
                          spacing: 8,
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _assign,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Palette.ink,
                                  foregroundColor: Palette.background,
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                child: const Text('Assign'),
                              ),
                            ),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _moveMoney,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                child: const Text('Move money'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TargetSection(
                    state: state,
                    categoryId: id,
                    month: month,
                    onEdit: _editTarget,
                    onMode: (mode) {
                      widget.engine.execute(
                        SetAutomationMode(categoryId: id, mode: mode),
                      );
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
                          child: Text(
                            'Activity',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (final (transaction, line) in lines)
                          _ActivityRow(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.rows, required this.total});

  final List<(String, String)> rows;
  final String total;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 14, color: Palette.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (final (name, value) in rows)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: label),
              Text(value, style: amountStyle(fontSize: 14)),
            ],
          ),
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Palette.cardBorder)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Available',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Text(
                total,
                style: amountStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.payee,
    required this.detail,
    required this.amount,
  });

  final String payee;
  final String detail;
  final Money amount;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
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
              Text(payee, style: const TextStyle(fontSize: 15)),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
            ],
          ),
        ),
        Text(amount.format(), style: amountStyle(fontSize: 14)),
      ],
    ),
  );
}

/// Opens the sheet that sets [categoryId]'s Assignment for [month],
/// filled in with [amount], or with the current Assignment.
Future<void> showAssignSheet(
  BuildContext context, {
  required BudgetEngine engine,
  required String categoryId,
  required CalendarMonth month,
  Money? amount,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Palette.card,
  builder: (_) => _AssignSheet(
    engine: engine,
    categoryId: categoryId,
    month: month,
    amount: amount,
  ),
);

/// Changes the Category's Assignment for the month.
class _AssignSheet extends StatefulWidget {
  const _AssignSheet({
    required this.engine,
    required this.categoryId,
    required this.month,
    this.amount,
  });

  final BudgetEngine engine;
  final String categoryId;
  final CalendarMonth month;
  final Money? amount;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  late final _amount = TextEditingController(
    text:
        (widget.amount ??
                widget.engine.state.assigned(widget.categoryId, widget.month))
            .format(),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final amount = _amount.text.trim().isEmpty
        ? Money.zero
        : Money.tryParse(_amount.text);
    if (amount == null) {
      setState(() => _error = 'Enter an amount like 1,234.56');
      return;
    }
    final result = widget.engine.execute(
      SetAssignment(
        categoryId: widget.categoryId,
        month: widget.month,
        amount: amount,
      ),
    );
    if (result is Accepted ||
        (result is Rejected && result.reason == Rejection.noChange)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.engine.state;
    final name = state.category(widget.categoryId)!.name;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        22 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            'Assign to $name',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          LabeledField(
            label: 'Assigned in ${monthName(widget.month)}',
            child: TextField(
              key: const ValueKey('assign-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              style: amountStyle(fontSize: 22, fontWeight: FontWeight.w600),
              decoration: InputDecoration(errorText: _error),
              onSubmitted: (_) => _save(),
            ),
          ),
          Hint(
            'Ready to Assign: '
            '${state.readyToAssign(thisMonth()).formatDollars()}',
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
