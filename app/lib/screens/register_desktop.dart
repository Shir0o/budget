import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../theme.dart';
import '../widgets.dart';
import 'new_transaction_screen.dart';
import 'reconcile_screen.dart';
import 'transaction_parts.dart';
import 'transaction_screen.dart';

/// One account's register in the desktop window (ticket 65): the working,
/// cleared and uncleared balances and the last reconcile above a wide table
/// of transactions with a running balance. A credit card also shows its Card
/// Payment Category's Available and Record payment, and Reconcile opens as a
/// sheet so the sidebar stays where it is. The phone's register is unchanged.
class DesktopAccountRegister extends StatefulWidget {
  const DesktopAccountRegister({
    super.key,
    required this.engine,
    required this.accountId,
  });

  final BudgetEngine engine;
  final String accountId;

  @override
  State<DesktopAccountRegister> createState() => _DesktopAccountRegisterState();
}

/// The table's columns, shared by the header and the rows so they line up.
const _dateColumn = 64.0;
const _categoryColumn = 120.0;
const _outflowColumn = 84.0;
const _inflowColumn = 84.0;
const _clearedColumn = 86.0;
const _balanceColumn = 100.0;

const _columnLabel = TextStyle(
  fontSize: 11,
  letterSpacing: 0.88,
  color: Palette.muted,
);

class _DesktopAccountRegisterState extends State<DesktopAccountRegister> {
  BudgetState get _state => widget.engine.state;

  /// Opens one of the short flows, which are sheets above the desktop
  /// breakpoint (ticket 63), then shows the new numbers.
  Future<void> _openFlow(Widget screen) async {
    await openFlow<void>(context, builder: (_) => screen);
    if (mounted) setState(() {});
  }

  Future<void> _openTransaction(Transaction transaction) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionScreen(
          engine: widget.engine,
          transactionId: transaction.id,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final account = state.account(widget.accountId);
    if (account == null) return const SizedBox.shrink();
    final id = account.id;
    final transactions = state.register(id);
    final running = _runningBalances(transactions);
    final working = state.balance(id);
    final cleared = state.clearedBalance(id);
    final last = state.lastReconcile(id);
    final card = account.type == AccountType.creditCard
        ? state.cardPaymentCategory(id)
        : null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 20, 10),
              child: Row(
                spacing: 8,
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
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (card != null)
                    OutlinedButton(
                      onPressed: () => _openFlow(
                        _RecordPaymentSheet(
                          engine: widget.engine,
                          card: account,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('Record payment'),
                    ),
                  OutlinedButton(
                    onPressed: () => _openFlow(
                      ReconcileScreen(engine: widget.engine, accountId: id),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Reconcile'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openFlow(
                      NewTransactionScreen(
                        engine: widget.engine,
                        accountId: id,
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New transaction'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    CardBox(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 10,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _Figure(
                                  label: 'Working',
                                  amount: working,
                                  valueKey: 'register-working',
                                  strong: true,
                                ),
                              ),
                              Expanded(
                                child: _Figure(
                                  label: 'Cleared',
                                  amount: cleared,
                                  valueKey: 'register-cleared',
                                ),
                              ),
                              Expanded(
                                child: _Figure(
                                  label: 'Uncleared',
                                  amount: working - cleared,
                                  valueKey: 'register-uncleared',
                                ),
                              ),
                            ],
                          ),
                          Text(
                            last == null
                                ? 'Not reconciled yet'
                                : 'Last reconciled ${formatDay(last.date)} · '
                                      '${last.bankBalance.format()}',
                            key: const ValueKey('register-last-reconcile'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (card != null)
                      _CardPaymentCard(
                        state: state,
                        category: card,
                        cardName: account.name,
                      ),
                    CardBox(
                      padding: EdgeInsets.zero,
                      child: Column(
                        key: const ValueKey('register-table'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _TableHeader(),
                          for (final transaction in transactions)
                            _RegisterTableRow(
                              state: state,
                              transaction: transaction,
                              runningBalance: running[transaction.id]!,
                              onTap: () => _openTransaction(transaction),
                            ),
                          if (transactions.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Hint('No transactions yet.'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Each transaction's balance up to and including it, oldest first. The
/// newest one is the account's working balance.
Map<String, Money> _runningBalances(List<Transaction> newestFirst) {
  var total = Money.zero;
  final running = <String, Money>{};
  for (final transaction in newestFirst.reversed) {
    total += transaction.amount;
    running[transaction.id] = total;
  }
  return running;
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.amount,
    required this.valueKey,
    this.strong = false,
  });

  final String label;
  final Money amount;

  /// The key on the amount, so the register's figures can be read apart.
  final String valueKey;
  final bool strong;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Hint(label),
      Text(
        amount.format(),
        key: ValueKey(valueKey),
        style: amountStyle(
          fontSize: 20,
          fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
          color: strong ? Palette.ink : Palette.inkSoft,
        ),
      ),
    ],
  );
}

/// A card's Card Payment Category and what it holds (ticket 07), with the
/// debt it doesn't cover in orange.
class _CardPaymentCard extends StatelessWidget {
  const _CardPaymentCard({
    required this.state,
    required this.category,
    required this.cardName,
  });

  final BudgetState state;
  final Category category;
  final String cardName;

  @override
  Widget build(BuildContext context) {
    final month = thisMonth();
    final unfunded = state.unfundedDebt(category.cardAccountId!, month);
    return CardBox(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                const Text('CARD PAYMENT', style: _columnLabel),
                Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  unfunded.isPositive
                      ? '${unfunded.format()} of $cardName’s debt not funded'
                      : 'Available to pay $cardName',
                  style: TextStyle(
                    fontSize: 12,
                    color: unfunded.isPositive
                        ? Palette.problemText
                        : Palette.muted,
                  ),
                ),
              ],
            ),
          ),
          AvailablePill(
            state.available(category.id, month),
            key: const ValueKey('register-card-available'),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
    child: Row(
      children: [
        const SizedBox(
          width: _dateColumn,
          child: Text('DATE', style: _columnLabel),
        ),
        const Expanded(child: Text('PAYEE', style: _columnLabel)),
        const SizedBox(
          width: _categoryColumn,
          child: Text('CATEGORY', style: _columnLabel),
        ),
        const SizedBox(
          width: _outflowColumn,
          child: Text(
            'OUTFLOW',
            style: _columnLabel,
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(
          width: _inflowColumn,
          child: Text(
            'INFLOW',
            style: _columnLabel,
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(
          width: _clearedColumn,
          child: Text('CLEARED', style: _columnLabel),
        ),
        const SizedBox(
          width: _balanceColumn,
          child: Text(
            'BALANCE',
            style: _columnLabel,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

class _RegisterTableRow extends StatelessWidget {
  const _RegisterTableRow({
    required this.state,
    required this.transaction,
    required this.runningBalance,
    required this.onTap,
  });

  final BudgetState state;
  final Transaction transaction;
  final Money runningBalance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final unreviewed = t.lines.any((line) => !line.reviewed);
    return InkWell(
      key: ValueKey('register-row-${t.id}'),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Palette.divider)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _dateColumn,
              child: Text(
                formatDay(t.date),
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
            ),
            Expanded(
              child: Text(
                _payeeLabel(state, t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: unreviewed ? Palette.problemText : Palette.ink,
                ),
              ),
            ),
            SizedBox(
              width: _categoryColumn,
              child: Text(
                _categoryLabel(state, t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
            ),
            SizedBox(
              width: _outflowColumn,
              child: Text(
                t.amount.isNegative ? (-t.amount).format() : '',
                textAlign: TextAlign.right,
                style: amountStyle(fontSize: 13),
              ),
            ),
            SizedBox(
              width: _inflowColumn,
              child: Text(
                t.amount.isPositive ? t.amount.format() : '',
                textAlign: TextAlign.right,
                style: amountStyle(fontSize: 13),
              ),
            ),
            SizedBox(
              width: _clearedColumn,
              child: Text(
                clearedLabel(t.cleared),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: _clearedColor(t.cleared)),
              ),
            ),
            SizedBox(
              width: _balanceColumn,
              child: Text(
                runningBalance.format(),
                key: ValueKey('register-running-${t.id}'),
                textAlign: TextAlign.right,
                style: amountStyle(fontSize: 13, color: Palette.inkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _clearedColor(ClearedStatus status) => switch (status) {
  ClearedStatus.uncleared => Palette.muted,
  ClearedStatus.cleared => Palette.inkSoft,
  ClearedStatus.reconciled => Palette.positiveText,
};

String _payeeLabel(BudgetState state, Transaction t) => t.isTransfer
    ? 'Transfer ${t.amount.isNegative ? 'to' : 'from'} '
          '${state.account(t.transferAccountId!)?.name}'
    : t.payee.isEmpty
    ? 'No payee'
    : t.payee;

String _categoryLabel(BudgetState state, Transaction t) {
  if (t.lines.any((line) => !line.reviewed)) return 'Unreviewed';
  if (t.isTransfer && t.lines.single.category == null) return 'Transfer';
  if (t.isSplit) return 'Split · ${t.lines.length}';
  return categoryName(state, t.lines.single.category);
}

/// Record payment: a transfer from a cash account to the card, which spends
/// the Card Payment Category (ticket 07). It starts at what the Category
/// holds, so a fully funded card is paid off in one tap.
class _RecordPaymentSheet extends StatefulWidget {
  const _RecordPaymentSheet({required this.engine, required this.card});

  final BudgetEngine engine;
  final Account card;

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  BudgetState get _state => widget.engine.state;

  /// The account the money comes from: the first cash one.
  late String? _fromId = _state.accounts
      .where((a) => a.type.onBudget && a.type != AccountType.creditCard)
      .firstOrNull
      ?.id;

  late final _amount = TextEditingController(text: _availableText());

  String? _error;

  /// The Card Payment Category's Available, which is what the card can be
  /// paid from the budget today.
  String _availableText() {
    final payment = _state.cardPaymentCategory(widget.card.id);
    final available = payment == null
        ? Money.zero
        : _state.available(payment.id, thisMonth());
    return available.isPositive ? available.format() : '';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _record() {
    final amount = Money.tryParse(_amount.text);
    final from = _fromId;
    if (amount == null || !amount.isPositive) {
      setState(() => _error = 'Enter an amount above 0.00');
      return;
    }
    if (from == null) {
      setState(() => _error = 'Choose the account the money comes from');
      return;
    }
    final result = widget.engine.execute(
      CreateTransfer(
        fromAccountId: from,
        toAccountId: widget.card.id,
        amount: amount,
        date: today(),
      ),
    );
    if (result is Rejected) {
      setState(() => _error = 'That payment could not be recorded');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final from = _fromId == null ? null : _state.account(_fromId!);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 4),
              child: Row(
                spacing: 4,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.close, size: 22, color: Palette.ink),
                  ),
                  Expanded(
                    child: Text(
                      'Record a payment to ${widget.card.name}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PaymentRow(
                          label: 'From',
                          first: true,
                          child: PopupMenuButton<String>(
                            tooltip: 'Choose account to pay from',
                            onSelected: (id) => setState(() => _fromId = id),
                            itemBuilder: (_) => [
                              for (final account in _state.accounts)
                                if (account.type.onBudget &&
                                    account.type != AccountType.creditCard)
                                  PopupMenuItem(
                                    value: account.id,
                                    child: Text(account.name),
                                  ),
                            ],
                            child: _Choice(from?.name ?? 'Choose'),
                          ),
                        ),
                        _PaymentRow(
                          label: 'Amount',
                          child: TextField(
                            key: const ValueKey('payment-amount'),
                            controller: _amount,
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() => _error = null),
                            style: amountStyle(fontSize: 16),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              errorText: _error,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Hint(
                    'The payment moves money from the account into '
                    '${widget.card.name} and spends its Card Payment '
                    'Category’s Available.',
                  ),
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
                onPressed: _record,
                child: const Text('Record payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.child,
    this.first = false,
  });

  final String label;
  final Widget child;
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 56),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      border: first
          ? null
          : const Border(top: BorderSide(color: Palette.divider)),
    ),
    child: Row(
      spacing: 12,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, color: Palette.inkSoft),
          ),
        ),
        Flexible(
          child: Align(alignment: Alignment.centerRight, child: child),
        ),
      ],
    ),
  );
}

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
