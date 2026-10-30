import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'transaction_parts.dart';

/// Possible match (ticket 10, step 4): a bank charge that looks like a line
/// someone entered by hand or from a schedule. Confirming links the two,
/// keeping the line's Category, business status and memo; rejecting enters
/// the bank charge as a new Unreviewed line. Nothing merges until a person
/// chooses, and the line is not in Review while it waits.
class PossibleMatchScreen extends StatefulWidget {
  const PossibleMatchScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<PossibleMatchScreen> createState() => _PossibleMatchScreenState();
}

class _PossibleMatchScreenState extends State<PossibleMatchScreen> {
  BudgetState get _state => widget.engine.state;

  void _resolve(Command command) {
    widget.engine.execute(command);
    if (!mounted) return;
    // The last answer closes the screen.
    if (_state.proposedMatches.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final matches = _state.proposedMatches;
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
                    tooltip: 'Back',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.chevron_left, color: Palette.ink),
                  ),
                  const Expanded(
                    child: Text(
                      'Possible match',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (matches.length > 1)
                    Text(
                      '${matches.length} waiting',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Palette.muted,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (matches.isEmpty)
                    const CardBox(
                      padding: EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          Text(
                            'Nothing to match',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Every bank charge has been sorted out.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Palette.muted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final (i, transaction) in matches.indexed) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _MatchCard(
                        state: _state,
                        transaction: transaction,
                        onConfirm: () => _resolve(
                          ConfirmBankMatch(transactionId: transaction.id),
                        ),
                        onReject: () => _resolve(
                          RejectBankMatch(transactionId: transaction.id),
                        ),
                      ),
                    ],
                  if (matches.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Hint(
                      'Nothing changes until you choose. A confirmed match '
                      'keeps the category, business status and memo you gave '
                      'the line, and later fetches update it in place.',
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

/// One bank charge beside the line it looks like.
class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.state,
    required this.transaction,
    required this.onConfirm,
    required this.onReject,
  });

  final BudgetState state;
  final Transaction transaction;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final match = transaction.pendingMatch!;
    final line = transaction.lines.first;
    final account = state.account(transaction.accountId)?.name ?? '';
    final what = transaction.isSplit
        ? 'Split · ${transaction.lines.length}'
        : line.reviewed
        ? categoryName(state, line.category)
        : 'Unreviewed';
    return CardBox(
      key: const ValueKey('possible-match'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          _Side(
            label: 'Bank charge',
            payee: match.description.isEmpty ? 'No payee' : match.description,
            detail: '${formatDay(match.date)} · $account',
            amount: match.amount,
          ),
          const Divider(height: 1, color: Palette.divider),
          _Side(
            label: 'You entered',
            payee: transaction.payee.isEmpty ? 'No payee' : transaction.payee,
            detail: '${formatDay(transaction.date)} · $what',
            amount: transaction.amount,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('confirm-match'),
                onPressed: onConfirm,
                child: const Text('Same transaction'),
              ),
              OutlinedButton(
                key: const ValueKey('reject-match'),
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Not the same'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One side of a possible match: what the bank says, or what the line says.
class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.payee,
    required this.detail,
    required this.amount,
  });

  final String label;
  final String payee;
  final String detail;
  final Money amount;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 2,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Palette.muted,
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  payee,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 13, color: Palette.muted),
                ),
              ],
            ),
          ),
          Text(
            formatSigned(amount),
            style: amountStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ],
  );
}
