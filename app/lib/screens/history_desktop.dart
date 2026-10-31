import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'history_screen.dart';

/// Change History in the desktop window (ticket 67): every change grouped by
/// day, each entry with its Actor's label, an Actor filter above, and Go back
/// to a date. The entries and their reversible behaviour are the phone's.
class DesktopHistoryScreen extends StatefulWidget {
  const DesktopHistoryScreen({
    super.key,
    required this.engine,
    required this.onGoBack,
    this.actor,
  });

  final BudgetEngine engine;

  /// Opens Go back to a date, which the history screen owns.
  final VoidCallback onGoBack;

  /// The Actor chip it opens on, such as MCP from Settings → AI apps.
  final ActorKind? actor;

  @override
  State<DesktopHistoryScreen> createState() => _DesktopHistoryScreenState();
}

class _DesktopHistoryScreenState extends State<DesktopHistoryScreen> {
  ActorKind? _actor;

  @override
  void initState() {
    super.initState();
    _actor = widget.actor;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Text(
                  'Change History',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onGoBack,
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: const Text('Go back to a date'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                      fontFamily: sansFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Wrap(
              spacing: 6,
              children: [
                for (final (kind, label) in actorChips)
                  KeyedSubtree(
                    key: ValueKey('history-filter-$label'),
                    child: SelectChip(
                      label: label,
                      selected: _actor == kind,
                      onTap: () => setState(() => _actor = kind),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  children: [
                    HistoryEntries(
                      engine: widget.engine,
                      filter: HistoryFilter(
                        actors: _actor == null ? null : {_actor!},
                      ),
                      onChanged: () => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
