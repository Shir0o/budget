import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_register_screen.dart';
import 'add_account_screen.dart';
import 'settings_screen.dart';

/// Accounts (canvas: Accounts): net worth, then budget and tracking
/// accounts with their subtotals. A card's debt that its Card Payment
/// Category doesn't cover shows in orange. Bank sync and encrypted sync
/// arrive with tickets 10 and 12.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    setState(() {}); // The engine's state may have changed.
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final state = engine.state;
    final month = thisMonth();
    final budget = [
      for (final a in state.accounts)
        if (a.type.onBudget) a,
    ];
    final tracking = [
      for (final a in state.accounts)
        if (!a.type.onBudget) a,
    ];

    Widget section(String title, List<Account> accounts) => _Section(
      title: title,
      total: accounts.fold(
        Money.zero,
        (total, a) => total + state.balance(a.id),
      ),
      children: [
        for (final a in accounts)
          _AccountRow(
            name: a.name,
            balance: state.balance(a.id),
            detail: _detail(state, a, month),
            onTap: () =>
                _open(AccountRegisterScreen(engine: engine, accountId: a.id)),
          ),
      ],
    );

    return Scaffold(
      bottomNavigationBar: MainNav(engine: engine, current: MainTab.accounts),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Accounts',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _open(
                          SettingsScreen(
                            engine: engine,
                            services: AppServicesScope.of(context),
                          ),
                        ),
                        tooltip: 'Settings',
                        icon: const Icon(Icons.settings_outlined),
                        color: Palette.inkSoft,
                        iconSize: 22,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                      ),
                    ],
                  ),
                  Text.rich(
                    TextSpan(
                      text: 'Net worth ',
                      children: [
                        TextSpan(
                          text: state.netWorth.formatDollars(),
                          style: amountStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Palette.ink,
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13, color: Palette.muted),
                  ),
                ],
              ),
            ),
            if (budget.isNotEmpty) ...[
              section('Budget accounts', budget),
              const SizedBox(height: 12),
            ],
            if (tracking.isNotEmpty) ...[
              section('Tracking accounts', tracking),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: () => _open(AddAccountScreen(engine: engine)),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add account'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The line under an account's name.
({String text, bool problem}) _detail(
  BudgetState state,
  Account account,
  CalendarMonth month,
) {
  if (!account.type.onBudget) return (text: 'Net worth only', problem: false);
  final unfunded = state.unfundedDebt(account.id, month);
  if (unfunded.isPositive) {
    return (text: '${unfunded.format()} not funded', problem: true);
  }
  return (
    text: 'Cleared ${state.clearedBalance(account.id).format()}',
    problem: false,
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.total,
    required this.children,
  });

  final String title;
  final Money total;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Palette.muted,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Palette.card,
        border: Border.all(color: Palette.cardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: style),
                    ),
                  ),
                  Text(
                    total.format(),
                    style: amountStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.name,
    required this.balance,
    required this.detail,
    required this.onTap,
  });

  final String name;
  final Money balance;
  final ({String text, bool problem}) detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.divider)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 15)),
                Text(
                  detail.text,
                  style: TextStyle(
                    fontSize: 12,
                    color: detail.problem ? Palette.problemText : Palette.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(balance.format(), style: amountStyle()),
        ],
      ),
    ),
  );
}
