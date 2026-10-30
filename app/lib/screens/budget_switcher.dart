import 'package:flutter/material.dart';

import '../budget_library.dart';
import '../theme.dart';
import '../widgets.dart';
import 'budget_screen.dart';
import 'welcome_screen.dart';

/// The budget switcher (canvas: BudgetSwitcher), a bottom sheet over the
/// Budget screen. Picking a budget opens it; "New budget" goes through the
/// Welcome flow.
Future<void> showBudgetSwitcher(BuildContext context) async {
  final library = BudgetLibraryScope.of(context);
  final navigator = Navigator.of(context);
  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    backgroundColor: Palette.card,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BudgetSwitcherSheet(entries: library.entries),
  );
  switch (choice) {
    case _Open(:final id):
      final engine = await library.switchTo(id);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => BudgetScreen(engine: engine)),
        (_) => false,
      );
    case _New():
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => WelcomeScreen(engine: library.startNew()),
        ),
      );
    case null:
  }
}

sealed class _Choice {
  const _Choice();
}

final class _Open extends _Choice {
  const _Open(this.id);
  final String id;
}

final class _New extends _Choice {
  const _New();
}

class _BudgetSwitcherSheet extends StatelessWidget {
  const _BudgetSwitcherSheet({required this.entries});

  final List<BudgetEntry> entries;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          const Text(
            'Budgets',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Column(
            children: [
              for (final (i, entry) in entries.indexed)
                _BudgetRow(
                  entry: entry,
                  first: i == 0,
                  onTap: () =>
                      Navigator.of(context)
                          .pop(entry.isOpen ? null : _Open(entry.id)),
                ),
            ],
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(const _New()),
            child: const Text('New budget'),
          ),
          const Hint('Each budget has its own accounts, key and sync.'),
        ],
      ),
    ),
  );
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.entry,
    required this.first,
    required this.onTap,
  });

  final BudgetEntry entry;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: entry.isOpen,
    child: InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: Palette.divider)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: entry.isOpen ? FontWeight.w600 : null,
                  ),
                ),
                Hint(entry.isOpen ? 'Open now' : 'This phone only'),
              ],
            ),
            if (entry.isOpen)
              const Icon(Icons.check, size: 20, color: Palette.teal),
          ],
        ),
      ),
    ),
  );
}
