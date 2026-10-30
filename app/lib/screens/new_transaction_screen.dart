import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'transaction_parts.dart';

/// Enters a transaction by hand (canvas: AddTransaction). An inflow to
/// Ready to Assign is income. Transfer moves money to another account
/// (ticket 07).
class NewTransactionScreen extends StatefulWidget {
  const NewTransactionScreen({super.key, required this.engine, this.accountId});

  final BudgetEngine engine;

  /// The account to start in. Defaults to the first one.
  final String? accountId;

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  final _amount = TextEditingController();
  final _payee = TextEditingController();
  final _memo = TextEditingController();
  var _kind = _Kind.outflow;
  var _date = today();
  late String? _accountId = widget.accountId ?? _state.accounts.firstOrNull?.id;

  /// A transfer's other account.
  String? _toAccountId;

  /// A transfer moves money out of the chosen account.
  bool get _outflow => _kind != _Kind.inflow;
  bool get _transfer => _kind == _Kind.transfer;

  /// Whether the transfer crosses between a budget and a tracking account,
  /// so its budget side needs a Category (ticket 07).
  bool get _transferNeedsCategory {
    final from = _accountId == null ? null : _state.account(_accountId!);
    final to = _toAccountId == null ? null : _state.account(_toAccountId!);
    return from != null && to != null && from.type.onBudget != to.type.onBudget;
  }

  /// Used until the transaction is split.
  String? _category;
  BusinessStatus? _business;

  /// Null until Split is tapped.
  List<LineDraft>? _lines;

  String? _amountError;
  String? _payeeError;
  String? _memoError;
  String? _businessError;
  String? _transferError;

  BudgetState get _state => widget.engine.state;

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _memo.dispose();
    super.dispose();
  }

  /// The amount entered, as a positive number, or null if it isn't one.
  Money? get _magnitude {
    final amount = Money.tryParse(_amount.text);
    return amount == null || amount.isNegative ? null : amount;
  }

  Money? get _left {
    final total = _magnitude;
    final lines = _lines;
    if (total == null || lines == null) return null;
    return lines.fold<Money>(total, (left, line) => left - line.amount);
  }

  Future<void> _pickCategory() async {
    final picked = await pickCategory(
      context,
      _state,
      payee: _payee.text,
      date: _date,
    );
    if (picked != null) setState(() => _category = picked);
  }

  void _split() => setState(
    () => _lines = [
      LineDraft(
        amount: _magnitude ?? Money.zero,
        category: _category,
        business: _business,
      ),
    ],
  );

  Future<void> _editLine(int index) async {
    final lines = _lines!;
    final edit = await showLineEditor(
      context,
      state: _state,
      line: lines[index],
      payee: _payee.text,
      date: _date,
      canRemove: lines.length > 1,
    );
    if (edit == null) return;
    setState(() {
      if (edit.line case final line?) {
        lines[index] = line;
      } else {
        lines.removeAt(index);
      }
    });
  }

  Future<void> _addLine() async {
    final left = _left;
    final edit = await showLineEditor(
      context,
      state: _state,
      line: LineDraft(
        amount: left != null && left.isPositive ? left : Money.zero,
      ),
      payee: _payee.text,
      date: _date,
      canRemove: false,
    );
    if (edit?.line case final line?) setState(() => _lines!.add(line));
  }

  void _saveTransfer(Money magnitude) {
    final from = _accountId;
    final to = _toAccountId;
    if (from == null || to == null) {
      setState(() => _transferError = 'Choose the account to transfer to');
      return;
    }
    final result = widget.engine.execute(
      CreateTransfer(
        fromAccountId: from,
        toAccountId: to,
        amount: magnitude,
        date: _date,
        category: _transferNeedsCategory ? _category : null,
        memo: _memo.text,
      ),
    );
    if (result is Accepted) {
      Navigator.of(context).pop();
    } else if (result is Rejected) {
      setState(
        () => _transferError = switch (result.reason) {
          Rejection.transferCategoryRequired =>
            'Choose a Category: this money leaves the budget',
          Rejection.sameAccount => 'Choose a different account',
          _ => null,
        },
      );
    }
  }

  void _save() {
    final magnitude = _magnitude;
    final accountId = _accountId;
    setState(() {
      _amountError = magnitude == null || magnitude == Money.zero
          ? 'Enter an amount above 0.00'
          : null;
      _payeeError = containsSensitiveNumber(_payee.text)
          ? accountNumberMessage
          : null;
      _memoError = containsSensitiveNumber(_memo.text)
          ? accountNumberMessage
          : null;
      _businessError =
          !_transfer &&
              _lines == null &&
              _business is Business &&
              !isSet(_business)
          ? 'Choose a Business Tag'
          : null;
    });
    if (magnitude == null ||
        accountId == null ||
        _amountError != null ||
        _payeeError != null ||
        _memoError != null ||
        _businessError != null) {
      return;
    }
    if (_transfer) return _saveTransfer(magnitude);
    final lines =
        _lines ??
        [
          LineDraft(
            amount: magnitude,
            category: _category,
            business: _business,
          ),
        ];
    final result = widget.engine.execute(
      CreateTransaction(
        accountId: accountId,
        date: _date,
        amount: _outflow ? -magnitude : magnitude,
        payee: _payee.text,
        memo: _memo.text,
        lines: [for (final line in lines) line.toInput(outflow: _outflow)],
      ),
    );
    if (result is Accepted) Navigator.of(context).pop();
  }

  String get _reviewHint {
    final lines = _lines;
    if (lines != null) {
      return 'Each line with a Category and Personal or Business saves as '
          'Reviewed.';
    }
    if (_category != null && _business == const Business(giftsTag)) {
      return 'Gift lines need a recipient, so it saves as Unreviewed. Add '
          'the recipient in Review.';
    }
    if (_category != null && isSet(_business)) {
      final status = _business is Personal ? 'Personal' : 'Business';
      return 'Category and $status are set, so it saves as Reviewed.';
    }
    return 'Set a Category and Personal or Business to save it as Reviewed.';
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final lines = _lines;
    final left = _left;
    final account = _accountId == null ? null : state.account(_accountId!);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormHeader(
              title: 'New transaction',
              onClose: () => Navigator.of(context).pop(),
              onSave: lines == null || left == Money.zero ? _save : null,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        Segmented<_Kind>(
                          options: const [
                            (_Kind.outflow, 'Outflow'),
                            (_Kind.inflow, 'Inflow'),
                            (_Kind.transfer, 'Transfer'),
                          ],
                          selected: _kind,
                          onChanged: (kind) => setState(() {
                            _kind = kind;
                            _lines = null;
                            _transferError = null;
                          }),
                        ),
                        Semantics(
                          label: 'Amount',
                          child: TextField(
                            key: const ValueKey('transaction-amount'),
                            controller: _amount,
                            autofocus: true,
                            onChanged: (_) => setState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: amountStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              prefixText: _outflow ? '−' : '+',
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
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_transfer)
                            _Row(
                              label: 'Payee',
                              first: true,
                              child: TextField(
                                key: const ValueKey('transaction-payee'),
                                controller: _payee,
                                textAlign: TextAlign.end,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(fontSize: 15),
                                decoration: _bare(
                                  hint: 'Who was paid',
                                  error: _payeeError,
                                ),
                              ),
                            ),
                          _Row(
                            label: 'Date',
                            onTap: () async {
                              final picked = await pickDate(context, _date);
                              if (picked != null) {
                                setState(() => _date = picked);
                              }
                            },
                            child: Text(
                              formatDate(_date),
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          _Row(
                            label: _transfer ? 'From' : 'Account',
                            first: _transfer,
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
                          if (_transfer) ...[
                            _Row(
                              label: 'To',
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: PopupMenuButton<String>(
                                  tooltip: 'Choose account to transfer to',
                                  onSelected: (id) =>
                                      setState(() => _toAccountId = id),
                                  itemBuilder: (_) => [
                                    for (final a in state.accounts)
                                      if (a.id != _accountId)
                                        PopupMenuItem(
                                          value: a.id,
                                          child: Text(a.name),
                                        ),
                                  ],
                                  child: _Choice(
                                    _toAccountId == null
                                        ? 'Choose'
                                        : state.account(_toAccountId!)?.name ??
                                              'Choose',
                                  ),
                                ),
                              ),
                            ),
                            if (_transferNeedsCategory)
                              _Row(
                                label: 'Category',
                                onTap: _pickCategory,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _Choice(
                                    _category == null
                                        ? 'Choose'
                                        : categoryName(state, _category),
                                  ),
                                ),
                              ),
                            if (_transferError case final error?)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Text(
                                  error,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Palette.problemText,
                                  ),
                                ),
                              ),
                          ],
                          if (lines == null && !_transfer) ...[
                            _Row(
                              label: 'Category',
                              onTap: _pickCategory,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _Choice(
                                  _category == null
                                      ? 'Choose'
                                      : categoryName(state, _category),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                10,
                                16,
                                14,
                              ),
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Palette.divider),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 6,
                                children: [
                                  BusinessField(
                                    value: _business,
                                    onChanged: (status) =>
                                        setState(() => _business = status),
                                  ),
                                  if (_businessError case final error?)
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
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (lines != null) ...[
                    const SizedBox(height: 12),
                    SplitLinesCard(
                      state: state,
                      lines: lines,
                      left: left ?? Money.zero,
                      outflow: _outflow,
                      onEdit: _editLine,
                      onAdd: _addLine,
                    ),
                  ],
                  const SizedBox(height: 12),
                  CardBox(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                  const SizedBox(height: 4),
                  if (!_transfer)
                    Row(
                      children: [
                        Expanded(child: Hint(_reviewHint)),
                        if (lines == null)
                          TextButton(
                            onPressed: _split,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              foregroundColor: Palette.teal,
                            ),
                            child: const Text('Split'),
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

enum _Kind { outflow, inflow, transfer }

/// A borderless field for a row.
InputDecoration _bare({required String hint, String? error}) => InputDecoration(
  hintText: hint,
  errorText: error,
  filled: false,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
  contentPadding: const EdgeInsets.symmetric(vertical: 14),
);

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
