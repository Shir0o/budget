import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_account_screen.dart';
import 'record_income_screen.dart';
import 'settings_screen.dart';

/// The Budget screen (canvas: Main), showing Ready to Assign. Categories,
/// Assign, Review and the bottom navigation arrive with later tickets.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    setState(() {}); // The engine's state may have changed.
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.engine.state;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 14,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          state.budget?.name ?? '',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              formatMonth(today()),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            IconButton(
                              onPressed: () => _open(
                                SettingsScreen(
                                  engine: widget.engine,
                                  services: AppServicesScope.of(context),
                                ),
                              ),
                              tooltip: 'Settings',
                              icon: const Icon(Icons.settings_outlined),
                              color: Palette.ink,
                              iconSize: 22,
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _ReadyToAssignCard(amount: state.readyToAssign),
                ],
              ),
            ),
            const Spacer(),
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
                    onPressed: () =>
                        _open(RecordIncomeScreen(engine: widget.engine)),
                    child: const Text('Record income'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _open(AddAccountScreen(engine: widget.engine)),
                    child: const Text('Add account'),
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

class _ReadyToAssignCard extends StatelessWidget {
  const _ReadyToAssignCard({required this.amount});

  final Money amount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
    decoration: BoxDecoration(
      color: Palette.ink,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        const Text(
          'READY TO ASSIGN',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 0.96,
            color: Palette.heroLabel,
          ),
        ),
        Text(
          amount.formatDollars(),
          style: amountStyle(
            fontSize: 34,
            fontWeight: FontWeight.w600,
            color: Palette.background,
          ).copyWith(letterSpacing: -0.68),
        ),
      ],
    ),
  );
}
