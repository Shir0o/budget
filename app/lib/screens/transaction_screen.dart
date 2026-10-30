import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'history_screen.dart';
import 'transaction_parts.dart';

/// One transaction (canvas: Transaction): payee, date, account, amount and
/// cleared status, its lines with Left to split, the memo, and who created
/// and last changed it, with a link to its Change History.
class TransactionScreen extends StatefulWidget {
  const TransactionScreen({
    super.key,
    required this.engine,
    required this.transactionId,
  });

  final BudgetEngine engine;
  final String transactionId;

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  late final Transaction _saved = widget.engine.state.transaction(
    widget.transactionId,
  )!;
  late final bool _outflow = _saved.amount.isNegative;
  late String _payee = _saved.payee;
  late CivilDate _date = _saved.date;
  late Money _magnitude = _outflow ? -_saved.amount : _saved.amount;
  late ClearedStatus _cleared = _saved.cleared;
  late final List<LineDraft> _lines = [
    for (final line in _saved.lines) LineDraft.of(line, outflow: _outflow),
  ];
  late final _memo = TextEditingController(text: _saved.memo);
  String? _memoError;

  BudgetState get _state => widget.engine.state;

  Money get _left =>
      _lines.fold<Money>(_magnitude, (left, line) => left - line.amount);

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  Future<void> _editDetails() async {
    final details = await showModalBottomSheet<_Details>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.card,
      builder: (_) => _DetailsSheet(
        details: (payee: _payee, date: _date, amount: _magnitude),
      ),
    );
    if (details == null) return;
    setState(() {
      // An unsplit line follows the amount.
      if (_lines.length == 1) _lines.single.amount = details.amount;
      _payee = details.payee;
      _date = details.date;
      _magnitude = details.amount;
    });
  }

  Future<void> _editLine(int index) async {
    final edit = await showLineEditor(
      context,
      state: _state,
      line: _lines[index],
      payee: _payee,
      date: _date,
      canRemove: _lines.length > 1,
    );
    if (edit == null) return;
    setState(() {
      if (edit.line case final line?) {
        _lines[index] = line;
      } else {
        _lines.removeAt(index);
      }
    });
  }

  Future<void> _addLine() async {
    final left = _left;
    final edit = await showLineEditor(
      context,
      state: _state,
      line: LineDraft(amount: left.isPositive ? left : Money.zero),
      payee: _payee,
      date: _date,
      canRemove: false,
    );
    if (edit?.line case final line?) setState(() => _lines.add(line));
  }

  Future<void> _save() async {
    if (containsSensitiveNumber(_memo.text)) {
      setState(() => _memoError = accountNumberMessage);
      return;
    }
    final reconciled = _saved.cleared == ClearedStatus.reconciled;
    if (reconciled && !await _confirmReconciledEdit() || !mounted) return;
    final result = widget.engine.execute(
      EditTransaction(
        transactionId: widget.transactionId,
        payee: _payee,
        date: _date,
        memo: _memo.text,
        cleared: _cleared,
        confirmReconciled: reconciled,
        amount: _outflow ? -_magnitude : _magnitude,
        lines: [for (final line in _lines) line.toInput(outflow: _outflow)],
      ),
    );
    if (result is Accepted ||
        (result is Rejected && result.reason == Rejection.noChange)) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmReconciledEdit() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change a reconciled transaction?'),
          content: const Text(
            'This transaction was reconciled with your bank. Changing it '
            'can put the account out of step with the bank again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Change it'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text(
          'It comes out of the account and the budget. Change History '
          'keeps a record of it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Palette.problemText),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = widget.engine.execute(
      DeleteTransaction(transactionId: widget.transactionId),
    );
    if (result is Accepted && mounted) Navigator.of(context).pop();
  }

  Future<void> _openHistory() async {
    final before = widget.engine.events.length;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntityHistoryScreen(
          engine: widget.engine,
          entity: EntityRef.transaction(widget.transactionId),
          name: _saved.payee.isEmpty ? 'No payee' : _saved.payee,
        ),
      ),
    );
    // A revert changed it, so these unsaved values are out of date.
    if (mounted && widget.engine.events.length != before) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final cleared = _cleared != ClearedStatus.uncleared;
    final changes = widget.engine.history.entries(
      filter: HistoryFilter(
        entity: EntityRef.transaction(widget.transactionId),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormHeader(
              title: 'Transaction',
              onClose: () => Navigator.of(context).pop(),
              onSave: _left == Money.zero ? _save : null,
              actions: [
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Transaction options',
                  icon: const Icon(Icons.more_vert, color: Palette.muted),
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _delete,
                      child: const Text('Delete transaction'),
                    ),
                  ],
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  CardBox(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 14,
                      children: [
                        Semantics(
                          button: true,
                          label: 'Edit payee, date and amount',
                          child: InkWell(
                            onTap: _editDetails,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              spacing: 12,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    spacing: 2,
                                    children: [
                                      Text(
                                        _saved.isTransfer
                                            ? 'Transfer '
                                                  '${_outflow ? 'to' : 'from'} '
                                                  '${state.account(_saved.transferAccountId!)?.name}'
                                            : _payee.isEmpty
                                            ? 'No payee'
                                            : _payee,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${formatDate(_date)} · '
                                        '${state.account(_saved.accountId)?.name}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Palette.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatSigned(
                                    _outflow ? -_magnitude : _magnitude,
                                  ),
                                  style: amountStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Semantics(
                              button: true,
                              toggled: cleared,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: _cleared == ClearedStatus.reconciled
                                    ? null
                                    : () => setState(
                                        () => _cleared = cleared
                                            ? ClearedStatus.uncleared
                                            : ClearedStatus.cleared,
                                      ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 44,
                                  ),
                                  child: Center(
                                    widthFactor: 1,
                                    child: _StatusPill(_cleared),
                                  ),
                                ),
                              ),
                            ),
                            if (_lines.length > 1)
                              Container(
                                height: 28,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Palette.zeroPill,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    'Split · ${_lines.length} lines',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Palette.inkSoft,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // A transfer between budget accounts has no Category.
                  if (!_saved.isTransfer ||
                      _saved.lines.single.category != null) ...[
                    const SizedBox(height: 12),
                    SplitLinesCard(
                      state: state,
                      lines: _lines,
                      left: _left,
                      outflow: _outflow,
                      onEdit: _editLine,
                      onAdd: _addLine,
                    ),
                  ],
                  const SizedBox(height: 12),
                  CardBox(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    child: LabeledField(
                      label: 'Memo',
                      child: TextField(
                        key: const ValueKey('transaction-memo'),
                        controller: _memo,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Optional',
                          errorText: _memoError,
                          helperText: _memoError == null
                              ? accountNumberMessage
                              : null,
                          helperStyle: const TextStyle(
                            fontSize: 12,
                            color: Palette.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        if (changes.lastOrNull case final created?)
                          Hint(
                            'Created by ${actorPhrase(created)} · '
                            '${historyTime(created.time)}',
                          ),
                        if (changes.length > 1)
                          Hint(
                            'Last changed by ${actorPhrase(changes.first)} · '
                            '${historyTime(changes.first.time)}',
                          ),
                        TextButton(
                          onPressed: _openHistory,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: EdgeInsets.zero,
                            foregroundColor: Palette.teal,
                            textStyle: const TextStyle(
                              fontFamily: sansFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: const Text('See Change History'),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);

  final ClearedStatus status;

  @override
  Widget build(BuildContext context) {
    final uncleared = status == ClearedStatus.uncleared;
    final foreground = uncleared ? Palette.inkSoft : Palette.positiveText;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: uncleared ? Palette.zeroPill : Palette.positivePill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (!uncleared) Icon(Icons.check, size: 14, color: foreground),
          Text(
            clearedLabel(status),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// `Cleared`, `Uncleared` or `Reconciled`.
String clearedLabel(ClearedStatus status) => switch (status) {
  ClearedStatus.uncleared => 'Uncleared',
  ClearedStatus.cleared => 'Cleared',
  ClearedStatus.reconciled => 'Reconciled',
};

typedef _Details = ({String payee, CivilDate date, Money amount});

/// Edits the payee, date and amount.
class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({required this.details});

  final _Details details;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  late final _payee = TextEditingController(text: widget.details.payee);
  late final _amount = TextEditingController(
    text: widget.details.amount.format(),
  );
  late CivilDate _date = widget.details.date;
  String? _payeeError;
  String? _amountError;

  @override
  void dispose() {
    _payee.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _done() {
    final amount = Money.tryParse(_amount.text);
    setState(() {
      _payeeError = containsSensitiveNumber(_payee.text)
          ? accountNumberMessage
          : null;
      _amountError = amount == null || !amount.isPositive
          ? 'Enter an amount above 0.00'
          : null;
    });
    if (_payeeError != null || _amountError != null) return;
    Navigator.of(context)
        .pop((payee: _payee.text.trim(), date: _date, amount: amount!));
  }

  @override
  Widget build(BuildContext context) => Padding(
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
        const Text(
          'Payee, date and amount',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        LabeledField(
          label: 'Payee',
          child: TextField(
            key: const ValueKey('details-payee'),
            controller: _payee,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(errorText: _payeeError),
          ),
        ),
        LabeledField(
          label: 'Date',
          child: DateField(
            value: _date,
            onChanged: (date) => setState(() => _date = date),
          ),
        ),
        LabeledField(
          label: 'Amount',
          child: TextField(
            key: const ValueKey('details-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: amountStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(errorText: _amountError),
          ),
        ),
        FilledButton(onPressed: _done, child: const Text('Done')),
      ],
    ),
  );
}
