import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'history_screen.dart';
import 'new_transaction_screen.dart';
import 'transaction_parts.dart';
import 'transaction_screen.dart';

/// One account's register (canvas: AccountRegister): its balance and
/// cleared balance, then a Transactions tab with its transactions, newest
/// first, and a History tab with its Change History. Reconcile arrives with
/// ticket 06.
class AccountRegisterScreen extends StatefulWidget {
  const AccountRegisterScreen({
    super.key,
    required this.engine,
    required this.accountId,
  });

  final BudgetEngine engine;
  final String accountId;

  @override
  State<AccountRegisterScreen> createState() => _AccountRegisterScreenState();
}

class _AccountRegisterScreenState extends State<AccountRegisterScreen> {
  var _showHistory = false;

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    setState(() {}); // The engine's state may have changed.
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.engine.state;
    final id = widget.accountId;
    final transactions = state.register(id);
    return Scaffold(
      floatingActionButton: _showHistory
          ? null
          : FloatingActionButton(
              onPressed: () => _open(
                NewTransactionScreen(engine: widget.engine, accountId: id),
              ),
              tooltip: 'New transaction',
              backgroundColor: Palette.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.add, size: 24),
            ),
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
                    tooltip: 'Back',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.chevron_left, color: Palette.ink),
                  ),
                  Expanded(
                    child: Text(
                      state.account(id)?.name ?? '',
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  CardBox(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _Figure(
                            label: 'Balance',
                            amount: state.balance(id),
                            strong: true,
                          ),
                        ),
                        Expanded(
                          child: _Figure(
                            label: 'Cleared',
                            amount: state.clearedBalance(id),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Segmented(
                    options: const [(false, 'Transactions'), (true, 'History')],
                    selected: _showHistory,
                    onChanged: (history) =>
                        setState(() => _showHistory = history),
                  ),
                  const SizedBox(height: 12),
                  if (_showHistory)
                    HistoryEntries(
                      engine: widget.engine,
                      filter: HistoryFilter(entity: EntityRef.account(id)),
                      onChanged: () => setState(() {}),
                    )
                  else
                    CardBox(
                      padding: EdgeInsets.zero,
                      child: Material(
                        color: Colors.transparent,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, t) in transactions.indexed)
                              _RegisterRow(
                                state: state,
                                transaction: t,
                                first: i == 0,
                                onTap: () => _open(
                                  TransactionScreen(
                                    engine: widget.engine,
                                    transactionId: t.id,
                                  ),
                                ),
                              ),
                            if (transactions.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Hint('No transactions yet.'),
                              ),
                          ],
                        ),
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

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.amount,
    this.strong = false,
  });

  final String label;
  final Money amount;
  final bool strong;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Hint(label),
      Text(
        amount.format(),
        style: amountStyle(
          fontSize: 20,
          fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
          color: strong ? Palette.ink : Palette.inkSoft,
        ),
      ),
    ],
  );
}

class _RegisterRow extends StatelessWidget {
  const _RegisterRow({
    required this.state,
    required this.transaction,
    required this.first,
    required this.onTap,
  });

  final BudgetState state;
  final Transaction transaction;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final unreviewed = t.lines.any((line) => !line.reviewed);
    final what = unreviewed
        ? 'Unreviewed'
        : t.isTransfer && t.lines.single.category == null
        ? 'Transfer'
        : t.isSplit
        ? 'Split · ${t.lines.length}'
        : categoryName(state, t.lines.single.category);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: Palette.divider)),
        ),
        child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.isTransfer
                        ? 'Transfer ${t.amount.isNegative ? 'to' : 'from'} '
                              '${state.account(t.transferAccountId!)?.name}'
                        : t.payee.isEmpty
                        ? 'No payee'
                        : t.payee,
                    style: const TextStyle(fontSize: 15),
                  ),
                  Text(
                    '${formatDay(t.date)} · $what · ${clearedLabel(t.cleared)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: unreviewed ? Palette.problemText : Palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            Text(formatSigned(t.amount), style: amountStyle()),
          ],
        ),
      ),
    );
  }
}
