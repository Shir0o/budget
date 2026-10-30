import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Reconcile an account (canvas: Reconcile) against the balance the bank
/// shows. When the cleared balance matches, the cleared transactions become
/// reconciled. On a mismatch, an adjustment for the difference can be added
/// first; it goes to Ready to Assign and waits in Review. The bank sync
/// default arrives with ticket 12, so the field starts empty.
class ReconcileScreen extends StatefulWidget {
  const ReconcileScreen({
    super.key,
    required this.engine,
    required this.accountId,
  });

  final BudgetEngine engine;
  final String accountId;

  @override
  State<ReconcileScreen> createState() => _ReconcileScreenState();
}

class _ReconcileScreenState extends State<ReconcileScreen> {
  final _balance = TextEditingController();

  BudgetState get _state => widget.engine.state;

  @override
  void dispose() {
    _balance.dispose();
    super.dispose();
  }

  void _reconcile(Money bank, {required bool adjust}) {
    final result = widget.engine.execute(
      Reconcile(
        accountId: widget.accountId,
        date: today(),
        bankBalance: bank,
        addAdjustment: adjust,
      ),
    );
    if (result is Accepted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.accountId;
    // The same as-of date _reconcile passes, so the numbers match.
    final asOf = today();
    final cleared = _state.clearedBalance(id, asOf: asOf);
    final count = _state
        .register(id)
        .where(
          (t) =>
              t.cleared == ClearedStatus.cleared && t.date.compareTo(asOf) <= 0,
        )
        .length;
    final noun = count == 1 ? 'transaction' : 'transactions';
    final bank = Money.tryParse(_balance.text);
    final difference = bank == null ? null : bank - cleared;
    final matches = difference == Money.zero;

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
                  Expanded(
                    child: Text(
                      'Reconcile ${_state.account(id)?.name ?? ''}',
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
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: LabeledField(
                      label: 'Balance your bank shows',
                      child: TextField(
                        key: const ValueKey('reconcile-balance'),
                        controller: _balance,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        style: amountStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: '0.00',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _Row(label: 'Cleared in the app', value: cleared),
                        if (bank != null) ...[
                          _Row(label: 'Bank balance', value: bank),
                          _Row(
                            label: 'Difference',
                            value: difference!,
                            problem: !matches,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Semantics(
                      button: true,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Check $count cleared $noun',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Palette.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Hint(
                    'When it matches, the $count cleared $noun become '
                    'reconciled, and editing them later asks you to confirm '
                    'first.',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: bank == null
                        ? null
                        : () => _reconcile(bank, adjust: !matches),
                    child: Text(
                      bank == null || matches
                          ? 'Reconcile'
                          : 'Add ${difference!.format()} adjustment and '
                                'reconcile',
                    ),
                  ),
                  if (bank != null && !matches)
                    const Center(
                      child: Hint(
                        'The adjustment goes to Ready to Assign and waits in '
                        'Review.',
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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.problem = false});

  final String label;
  final Money value;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    final color = problem ? Palette.problemText : null;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: problem ? Palette.problemPill : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: problem ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ),
          Text(
            value.format(),
            style: amountStyle(
              fontWeight: problem ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
