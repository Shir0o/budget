import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'history_screen.dart';

/// Revert conflicts (canvas: RevertConflict): fields changed again later,
/// each reverted anyway or skipped, and later changes that depend on what
/// the group created. Returns the revert to run, or null on Cancel.
Future<RevertGroup?> showRevertConflicts(
  BuildContext context,
  RevertPlan plan,
) => showModalBottomSheet<RevertGroup>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Palette.card,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => _RevertConflictSheet(plan: plan),
);

class _RevertConflictSheet extends StatefulWidget {
  const _RevertConflictSheet({required this.plan});

  final RevertPlan plan;

  @override
  State<_RevertConflictSheet> createState() => _RevertConflictSheetState();
}

class _RevertConflictSheetState extends State<_RevertConflictSheet> {
  /// Skip is the default, so newer work is kept unless asked.
  late final _skip = {
    for (final conflict in widget.plan.fieldConflicts) conflict.ref,
  };

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final entry = plan.entry;
    final later = plan.fieldConflicts.length + plan.dependents.length;
    final who = entry.actor.kind == ActorKind.person
        ? 'your change'
        : actorPhrase(entry);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  'Revert $who from ${historyTime(entry.time)}?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Hint(
                  '${entry.summary}. $later '
                  '${later == 1 ? 'thing' : 'things'} changed after it.',
                ),
              ],
            ),
            for (final conflict in plan.fieldConflicts)
              _FieldConflictBox(
                conflict: conflict,
                skip: _skip.contains(conflict.ref),
                onChanged: (skip) => setState(
                  () => skip
                      ? _skip.add(conflict.ref)
                      : _skip.remove(conflict.ref),
                ),
              ),
            if (plan.dependents.isNotEmpty) _DependentsBox(plan.dependents),
            Row(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: const Text('Cancel'),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      RevertGroup(
                        groupId: entry.groupId,
                        skipFields: {..._skip},
                        includeDependents: plan.dependents.isNotEmpty,
                      ),
                    ),
                    child: Text(
                      plan.dependents.isEmpty ? 'Revert' : 'Revert these too',
                    ),
                  ),
                ),
              ],
            ),
            const Center(
              child: Hint(
                'Nothing is erased. Reverting adds new changes you can redo.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldConflictBox extends StatelessWidget {
  const _FieldConflictBox({
    required this.conflict,
    required this.skip,
    required this.onChanged,
  });

  final FieldConflict conflict;
  final bool skip;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final later = conflict.laterChange;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        border: Border.all(color: Palette.cardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          const Text(
            'Changed again later',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 14, height: 1.45),
              children: [
                TextSpan(text: '${conflict.description} was changed again by '),
                TextSpan(
                  text: actorLabel(later),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ' at ${historyTime(later.time)}: '),
                TextSpan(
                  text: '${conflict.laterBefore} → ${conflict.laterAfter}',
                ),
              ],
            ),
          ),
          _Choice(
            label: 'Revert anyway (restore ${conflict.restores})',
            selected: !skip,
            onTap: () => onChanged(false),
          ),
          _Choice(
            label: 'Skip this field',
            selected: skip,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

/// One of a pair of radio choices.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: selected,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          spacing: 10,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? Palette.teal : Palette.muted,
            ),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          ],
        ),
      ),
    ),
  );
}

class _DependentsBox extends StatelessWidget {
  const _DependentsBox(this.dependents);

  final List<HistoryEntry> dependents;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: Palette.problemPill,
      border: Border.all(color: Palette.problemBorder),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        const Text(
          'Depends on what this created',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Palette.problemText,
          ),
        ),
        Text(
          dependents.length == 1
              ? '1 later change uses it:'
              : '${dependents.length} later changes use it:',
          style: const TextStyle(fontSize: 14),
        ),
        for (final entry in dependents)
          Text(
            '${entry.summary} · ${actorLabel(entry)}',
            style: const TextStyle(fontSize: 13, color: Palette.inkSoft),
          ),
      ],
    ),
  );
}
