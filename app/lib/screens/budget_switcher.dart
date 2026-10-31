import 'package:flutter/material.dart';

import '../budget_library.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'welcome_screen.dart';

/// The desktop toolbar's budget name, which opens a popover of every Budget
/// with the open one checked, then New budget… and Manage budgets… (ticket
/// 68). It lists the same budgets and actions as the sheet.
class BudgetSwitcherMenu extends StatelessWidget {
  const BudgetSwitcherMenu({
    super.key,
    required this.name,
    required this.entries,
    required this.onOpen,
    required this.onNew,
    required this.onManage,
  });

  final String name;
  final List<BudgetEntry> entries;
  final ValueChanged<String> onOpen;
  final VoidCallback onNew;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      for (final entry in entries)
        Semantics(
          selected: entry.isOpen,
          child: MenuItemButton(
            key: ValueKey('budget-${entry.id}'),
            onPressed: () => onOpen(entry.id),
            leadingIcon: SizedBox(
              width: 16,
              height: 16,
              child: entry.isOpen
                  ? Icon(
                      Icons.check,
                      key: ValueKey('budget-check-${entry.id}'),
                      size: 16,
                      color: Palette.teal,
                    )
                  : null,
            ),
            child: SizedBox(
              width: 180,
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      const Divider(height: 9),
      MenuItemButton(onPressed: onNew, child: const Text('New budget…')),
      MenuItemButton(onPressed: onManage, child: const Text('Manage budgets…')),
    ],
    builder: (context, controller, _) => Semantics(
      button: true,
      label: 'Switch budget',
      child: InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The budget switcher (canvas: BudgetSwitcher), a bottom sheet over the
/// Budget screen. Picking a budget opens it; "New budget" goes through the
/// Welcome flow.
Future<void> showBudgetSwitcher(BuildContext context) async {
  final library = BudgetLibraryScope.of(context);
  // The window, not the content area: another budget is another app.
  final navigator = Navigator.of(context, rootNavigator: true);
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
      await library.switchTo(id);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const DesktopShell()),
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
