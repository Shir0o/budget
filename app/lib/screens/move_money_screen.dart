import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'category_picker.dart';

/// Move money (canvas: MoveMoney) from one Category to another, or back to
/// Ready to Assign. A move between Categories leaves Ready to Assign
/// unchanged.
class MoveMoneyScreen extends StatefulWidget {
  const MoveMoneyScreen({
    super.key,
    required this.engine,
    required this.fromCategoryId,
    required this.month,
    this.toCategoryId,
    this.amount,
  });

  final BudgetEngine engine;
  final String fromCategoryId;
  final CalendarMonth month;

  /// Fills in the To Category and the amount, as Cover does on Assign.
  final String? toCategoryId;
  final Money? amount;

  @override
  State<MoveMoneyScreen> createState() => _MoveMoneyScreenState();
}

class _MoveMoneyScreenState extends State<MoveMoneyScreen> {
  /// A Category id, [readyToAssignCategory], or null until chosen.
  late String? _to = widget.toCategoryId;
  late final _amount = TextEditingController(text: widget.amount?.format());

  BudgetState get _state => widget.engine.state;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Money _available(String categoryId) =>
      _state.available(categoryId, widget.month);

  String _name(String id) => id == readyToAssignCategory
      ? 'Ready to Assign'
      : _state.category(id)!.name;

  Future<void> _pickTo() async {
    final picked = await showCategoryPicker(
      context,
      state: _state,
      month: widget.month,
      title: 'Move to',
      excluding: widget.fromCategoryId,
    );
    if (picked != null) setState(() => _to = picked);
  }

  void _setAmount(Money amount) =>
      setState(() => _amount.text = amount.format());

  void _move(String to, Money amount) {
    final result = widget.engine.execute(
      MoveMoney(
        fromCategoryId: widget.fromCategoryId,
        toCategoryId: to,
        month: widget.month,
        amount: amount,
      ),
    );
    if (result is Accepted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final from = widget.fromCategoryId;
    final to = _to;
    final fromAvailable = _available(from);
    final toAvailable = to == null || to == readyToAssignCategory
        ? null
        : _available(to);
    final readyToAssign = _state.readyToAssign(thisMonth());
    final amount = Money.tryParse(_amount.text);
    final valid = to != null && amount != null && amount.isPositive;

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
                    tooltip: 'Back',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.chevron_left, color: Palette.ink),
                  ),
                  const Text(
                    'Move money',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _EndRow(
                          label: 'From',
                          name: Text(_name(from), style: _endName),
                          amount: fromAvailable,
                        ),
                        _EndRow(
                          label: 'To',
                          divided: true,
                          name: InkWell(
                            onTap: _pickTo,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 32),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 4,
                                children: [
                                  Text(
                                    to == null
                                        ? 'Choose a Category'
                                        : _name(to),
                                    style: _endName,
                                  ),
                                  const Icon(Icons.expand_more, size: 18),
                                ],
                              ),
                            ),
                          ),
                          amount: to == readyToAssignCategory
                              ? readyToAssign
                              : toAvailable,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 8,
                      children: [
                        const FieldLabel('Amount'),
                        TextField(
                          key: const ValueKey('move-amount'),
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          style: amountStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(hintText: '0.00'),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (toAvailable != null && toAvailable.isNegative)
                              SelectChip(
                                label: 'Cover overspending',
                                selected: false,
                                onTap: () => _setAmount(-toAvailable),
                              ),
                            if (fromAvailable.isPositive)
                              SelectChip(
                                label: 'All ${fromAvailable.format()}',
                                selected: false,
                                onTap: () => _setAmount(fromAvailable),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (valid) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        color: Palette.summary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: [
                          Text(
                            'After the move · ${monthName(widget.month)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          _Change(
                            name: _name(from),
                            before: fromAvailable,
                            after: fromAvailable - amount,
                          ),
                          if (toAvailable != null)
                            _Change(
                              name: _name(to),
                              before: toAvailable,
                              after: toAvailable + amount,
                            )
                          else
                            _Change(
                              name: 'Ready to Assign',
                              before: readyToAssign,
                              after: readyToAssign + amount,
                            ),
                          if (toAvailable != null)
                            const Hint('Ready to Assign doesn’t change.'),
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
              child: FilledButton(
                onPressed: valid ? () => _move(to, amount) : null,
                child: Text(valid ? 'Move ${amount.formatDollars()}' : 'Move'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _endName = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w500,
  color: Palette.ink,
);

class _EndRow extends StatelessWidget {
  const _EndRow({
    required this.label,
    required this.name,
    required this.amount,
    this.divided = false,
  });

  final String label;
  final Widget name;
  final Money? amount;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final amount = this.amount;
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: divided
            ? const Border(top: BorderSide(color: Palette.divider))
            : null,
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Hint(label), name],
            ),
          ),
          if (amount != null)
            Text(
              amount.format(),
              style: amountStyle(
                fontSize: 15,
                color: amount.isNegative ? Palette.problemText : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({
    required this.name,
    required this.before,
    required this.after,
  });

  final String name;
  final Money before;
  final Money after;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(name, style: const TextStyle(fontSize: 14)),
      Text(
        '${before.format()} → ${after.format()}',
        style: amountStyle(fontSize: 14),
      ),
    ],
  );
}
