import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'target_parts.dart';
import 'transaction_parts.dart';

/// Adds or changes a Scheduled Transaction (canvas: Edit schedule). It never
/// counts in the budget: Enter now is what makes it a real transaction.
class EditScheduleScreen extends StatefulWidget {
  const EditScheduleScreen({
    super.key,
    required this.engine,
    this.scheduleId,
    this.suggestion,
  });

  final BudgetEngine engine;

  /// Null when adding.
  final String? scheduleId;

  /// Prefills a new schedule from a repeating charge.
  final RecurringSuggestion? suggestion;

  @override
  State<EditScheduleScreen> createState() => _EditScheduleScreenState();
}

class _EditScheduleScreenState extends State<EditScheduleScreen> {
  late final Schedule? _existing = switch (widget.scheduleId) {
    final id? => widget.engine.state.schedule(id),
    null => null,
  };
  late final _payee = TextEditingController(
    text: _existing?.payee ?? widget.suggestion?.payee ?? '',
  );
  late final _amount = TextEditingController(
    text: switch (widget.suggestion?.amount ?? _existing?.amount) {
      final amount? => Money(amount.cents.abs()).format(),
      null => '',
    },
  );
  late final _every = TextEditingController(
    text: '${_existing?.every ?? widget.suggestion?.every ?? 1}',
  );
  late final _memo = TextEditingController(text: _existing?.memo ?? '');
  late var _inflow =
      _existing?.isInflow ?? (widget.suggestion?.amount.isPositive ?? false);
  late var _interval =
      _existing?.interval ??
      widget.suggestion?.interval ??
      TargetInterval.months;
  late var _date =
      _existing?.nextDue ?? widget.suggestion?.nextDue ?? _firstOfNextMonth();
  late String? _accountId =
      _existing?.accountId ??
      widget.suggestion?.accountId ??
      widget.engine.state.accounts.firstOrNull?.id;
  late String? _category = _existing?.category ?? widget.suggestion?.category;

  String? _amountError;
  String? _categoryError;
  String? _payeeError;

  static CivilDate _firstOfNextMonth() {
    final next = thisMonth().next;
    return CivilDate(next.year, next.month, 1);
  }

  BudgetState get _state => widget.engine.state;

  @override
  void initState() {
    super.initState();
    _category ??= _recentCategory();
  }

  /// The last Category used for this payee, as a starting point. The person
  /// confirms it, so nothing is categorized for them (ADR 0003).
  String? _recentCategory() {
    final payee = _payee.text.trim().toLowerCase();
    if (payee.isEmpty) return null;
    for (final transaction in _state.transactions.reversed) {
      if (transaction.payee.trim().toLowerCase() != payee) continue;
      final category = transaction.lines.length == 1
          ? transaction.lines.single.category
          : null;
      if (category != null && category != readyToAssignCategory) {
        return category;
      }
    }
    return null;
  }

  /// The amount entered, as a positive number, or null if it isn't one.
  Money? get _magnitude {
    final amount = Money.tryParse(_amount.text);
    return amount == null || !amount.isPositive ? null : amount;
  }

  int? get _everyValue => int.tryParse(_every.text.trim());

  Future<void> _pickCategory() async {
    final picked = await pickCategory(
      context,
      _state,
      payee: _payee.text,
      date: _date,
    );
    if (picked != null) setState(() => _category = picked);
  }

  void _save() {
    final magnitude = _magnitude;
    final accountId = _accountId;
    final category = _inflow ? readyToAssignCategory : _category;
    setState(() {
      _amountError = magnitude == null ? 'Enter an amount above 0.00' : null;
      _payeeError = containsSensitiveNumber(_payee.text)
          ? accountNumberMessage
          : null;
      // Income goes to Ready to Assign; an outflow needs a Category.
      _categoryError =
          !_inflow && (category == null || category == readyToAssignCategory)
          ? 'Choose a Category'
          : null;
    });
    if (magnitude == null ||
        accountId == null ||
        _payeeError != null ||
        _categoryError != null) {
      return;
    }
    final amount = _inflow ? magnitude : -magnitude;
    final existing = _existing;
    final result = existing == null
        ? widget.engine.execute(
            CreateSchedule(
              accountId: accountId,
              payee: _payee.text,
              amount: amount,
              category: category!,
              every: _everyValue ?? 1,
              interval: _interval,
              nextDue: _date,
              memo: _memo.text,
            ),
          )
        : widget.engine.execute(
            EditSchedule(
              scheduleId: existing.id,
              accountId: accountId,
              payee: _payee.text,
              amount: amount,
              category: category,
              every: _everyValue ?? existing.every,
              interval: _interval,
              nextDue: _date,
              memo: _memo.text,
            ),
          );
    if (result is Accepted ||
        (result is Rejected && result.reason == Rejection.noChange)) {
      Navigator.of(context).pop();
    }
  }

  void _enterNow() {
    final id = _existing?.id;
    if (id == null) return;
    widget.engine.execute(EnterSchedule(scheduleId: id));
    Navigator.of(context).pop();
  }

  void _delete() {
    final id = _existing?.id;
    if (id == null) return;
    widget.engine.execute(DeleteSchedule(scheduleId: id));
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _payee.dispose();
    _amount.dispose();
    _every.dispose();
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final account = _accountId == null ? null : state.account(_accountId!);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormHeader(
              title: _existing == null ? 'New schedule' : 'Edit schedule',
              onClose: () => Navigator.of(context).pop(),
              onSave: _save,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        Segmented<bool>(
                          options: const [(false, 'Outflow'), (true, 'Inflow')],
                          selected: _inflow,
                          onChanged: (inflow) =>
                              setState(() => _inflow = inflow),
                        ),
                        Semantics(
                          label: 'Amount',
                          child: TextField(
                            key: const ValueKey('schedule-amount'),
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: amountStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              prefixText: _inflow ? '+' : '−',
                              prefixStyle: amountStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: Palette.ink,
                              ),
                              errorText: _amountError,
                              filled: false,
                              enabledBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Palette.teal,
                                  width: 2,
                                ),
                              ),
                              focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Palette.teal,
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                            ),
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
                        _Row(
                          label: 'Payee',
                          first: true,
                          child: TextField(
                            key: const ValueKey('schedule-payee'),
                            controller: _payee,
                            textAlign: TextAlign.end,
                            textCapitalization: TextCapitalization.words,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Who is paid',
                              errorText: _payeeError,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        _Row(
                          label: 'Account',
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: PopupMenuButton<String>(
                              tooltip: 'Choose account',
                              onSelected: (id) =>
                                  setState(() => _accountId = id),
                              itemBuilder: (_) => [
                                for (final a in state.accounts)
                                  PopupMenuItem(
                                    value: a.id,
                                    child: Text(a.name),
                                  ),
                              ],
                              child: _Choice(account?.name ?? 'Choose'),
                            ),
                          ),
                        ),
                        if (!_inflow)
                          _Row(
                            label: 'Category',
                            onTap: _pickCategory,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _Choice(
                                    _category == null
                                        ? 'Choose'
                                        : categoryName(state, _category),
                                  ),
                                ),
                                if (_categoryError case final error?)
                                  Text(
                                    error,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Palette.problemText,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        _Row(
                          label: 'Repeats',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            spacing: 6,
                            children: [
                              SizedBox(
                                width: 52,
                                child: TextField(
                                  key: const ValueKey('schedule-every'),
                                  controller: _every,
                                  textAlign: TextAlign.end,
                                  keyboardType: TextInputType.number,
                                  style: amountStyle(),
                                  decoration: const InputDecoration(
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 116,
                                child: IntervalPicker(
                                  value: _interval,
                                  count: _everyValue ?? 2,
                                  onChanged: (interval) =>
                                      setState(() => _interval = interval),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _Row(
                          label: 'Next due',
                          onTap: () async {
                            final picked = await pickDate(context, _date);
                            if (picked != null) setState(() => _date = picked);
                          },
                          child: Text(
                            formatDate(_date),
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: LabeledField(
                      label: 'Memo',
                      child: TextField(
                        key: const ValueKey('schedule-memo'),
                        controller: _memo,
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(hintText: 'Optional'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Hint(
                    'It counts in nothing until it happens: Enter now writes '
                    'the transaction on its due date, and Review asks you for '
                    'its business status.',
                  ),
                  if (_existing != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _enterNow,
                      child: Text(
                        'Enter now · ${formatDay(_existing.nextDue)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: Palette.problemText,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('Delete schedule'),
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

/// A label on the left and its value on the right, 52 px tall.
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.child,
    this.onTap,
    this.first = false,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final bool first;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: Palette.divider)),
      ),
      child: Row(
        spacing: 12,
        children: [
          FieldLabel(label),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

/// A value with a down chevron, as on the canvas's Category row.
class _Choice extends StatelessWidget {
  const _Choice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        const Icon(Icons.keyboard_arrow_down, size: 18, color: Palette.ink),
      ],
    ),
  );
}
