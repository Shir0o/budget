import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'as_of_date_screen.dart';
import 'redact_screen.dart';
import 'revert_conflict_sheet.dart';

/// Change History (canvas: History): every change, newest first and
/// grouped by day, with Actor filter chips and Go back to a date.
/// [actor] picks the chip it opens on, such as MCP from Settings → AI apps.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.engine, this.actor});

  final BudgetEngine engine;
  final ActorKind? actor;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

const _actorChips = [
  (null, 'All'),
  (ActorKind.person, 'You'),
  (ActorKind.bankSync, 'Bank sync'),
  (ActorKind.automation, 'Automation'),
  (ActorKind.mcp, 'MCP'),
];

class _HistoryScreenState extends State<HistoryScreen> {
  ActorKind? _actor;

  @override
  void initState() {
    super.initState();
    _actor = widget.actor;
  }

  Future<void> _goBack() async {
    final now = today();
    final yesterday = CivilDate.fromDateTime(
      DateTime(now.year, now.month, now.day - 1),
    );
    final date = await pickDate(context, yesterday);
    if (date == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AsOfDateScreen(engine: widget.engine, date: date),
      ),
    );
    setState(() {}); // A restore may have changed history.
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: MainNav(
      current: Section.history,
      engine: widget.engine,
    ),
    body: SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Change History',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _goBack,
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: const Text('Go back to a date'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(
                          fontFamily: sansFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (kind, label) in _actorChips)
                      SelectChip(
                        label: label,
                        selected: _actor == kind,
                        onTap: () => setState(() => _actor = kind),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
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
        ],
      ),
    ),
  );
}

/// One transaction's or Category's Change History.
class EntityHistoryScreen extends StatefulWidget {
  const EntityHistoryScreen({
    super.key,
    required this.engine,
    required this.entity,
    required this.name,
  });

  final BudgetEngine engine;
  final EntityRef entity;

  /// Shown above the title, such as the payee.
  final String name;

  @override
  State<EntityHistoryScreen> createState() => _EntityHistoryScreenState();
}

class _EntityHistoryScreenState extends State<EntityHistoryScreen> {
  Future<void> _redact() async {
    final redacted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            RedactScreen(engine: widget.engine, entity: widget.entity),
      ),
    );
    if (redacted == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 4),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Palette.muted,
                        ),
                      ),
                      const Text(
                        'Change History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (redactCandidates(
                  widget.engine.state,
                  widget.entity,
                ).isNotEmpty)
                  TextButton(
                    onPressed: _redact,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: Palette.problemText,
                      textStyle: const TextStyle(
                        fontFamily: sansFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Redact a field'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              children: [
                HistoryEntries(
                  engine: widget.engine,
                  filter: HistoryFilter(entity: widget.entity),
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Change History entries matching [filter], under day headings, each with
/// its Revert or Redo button. Calls [onChanged] after a revert.
class HistoryEntries extends StatelessWidget {
  const HistoryEntries({
    super.key,
    required this.engine,
    required this.filter,
    required this.onChanged,
  });

  final BudgetEngine engine;
  final HistoryFilter filter;
  final VoidCallback onChanged;

  Future<void> _revert(BuildContext context, HistoryEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final plan = engine.history.planRevert(entry.groupId)!;
    if (plan.rejection case final reason?) {
      messenger.showSnackBar(SnackBar(content: Text(_rejection(reason))));
      return;
    }
    final command = plan.appliesRightAway
        ? RevertGroup(groupId: entry.groupId)
        : await showRevertConflicts(context, plan);
    if (command == null) return;
    final result = engine.execute(command);
    if (result case Rejected(:final reason)) {
      messenger.showSnackBar(SnackBar(content: Text(_rejection(reason))));
    }
    onChanged();
  }

  Future<void> _redact(BuildContext context, EntityRef entity) async {
    final redacted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RedactScreen(engine: engine, entity: entity),
      ),
    );
    if (redacted == true) onChanged();
  }

  /// The one entity of [entry] that still has a value worth redacting, or
  /// null when the entry touches several and the choice is the person's.
  EntityRef? _redactEntity(HistoryEntry entry) {
    final entity = entry.entity;
    if (entity == null) return null;
    return redactCandidates(engine.state, entity).isEmpty ? null : entity;
  }

  @override
  Widget build(BuildContext context) {
    final history = engine.history;
    final entries = history.entries(filter: filter);
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Hint('No changes yet.'),
      );
    }
    final children = <Widget>[];
    String? day;
    for (final entry in entries) {
      final heading = _dayHeading(entry.time);
      if (heading != day) {
        day = heading;
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(8, children.isEmpty ? 4 : 8, 8, 0),
            child: Text(
              heading.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                letterSpacing: 0.96,
                fontWeight: FontWeight.w600,
                color: Palette.muted,
              ),
            ),
          ),
        );
      }
      final redact = _redactEntity(entry);
      children.add(
        _EntryCard(
          entry: entry,
          history: history,
          onRevert: () => _revert(context, entry),
          onRedact: redact == null ? null : () => _redact(context, redact),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: children,
    );
  }
}

String _rejection(Rejection reason) => switch (reason) {
  Rejection.alreadyReverted =>
    'That change is already reverted. Redo it from its revert.',
  Rejection.noChange => 'Every field was skipped, so nothing changed.',
  _ => 'That change can’t be reverted.',
};

/// `Today`, `Yesterday`, `Nov 12`, or `Nov 12, 2025` in another year.
String _dayHeading(DateTime time) {
  final date = CivilDate.fromDateTime(time);
  final now = today();
  if (date == now) return 'Today';
  final yesterday = CivilDate.fromDateTime(
    DateTime(now.year, now.month, now.day - 1),
  );
  if (date == yesterday) return 'Yesterday';
  return date.year == now.year ? formatDay(date) : formatDate(date);
}

/// `4:12 PM` today, otherwise `Nov 12, 4:12 PM`.
String historyTime(DateTime time) {
  final date = CivilDate.fromDateTime(time);
  return date == today()
      ? formatTime(time)
      : '${formatDay(date)}, ${formatTime(time)}';
}

/// The Actor as a badge reads: `You`, `Bank sync`, `MCP · Claude
/// Desktop`, `Revert · by you`.
String actorLabel(HistoryEntry entry) => switch (entry.actor.kind) {
  ActorKind.person => 'You',
  ActorKind.bankSync => 'Bank sync',
  ActorKind.automation => 'Automation',
  ActorKind.import => 'Import',
  ActorKind.mcp => 'MCP · ${entry.actor.mcpClient}',
  ActorKind.revert => switch (entry.by?.kind) {
    ActorKind.person => 'Revert · by you',
    ActorKind.mcp => 'Revert · by MCP',
    _ => 'Revert',
  },
  ActorKind.other => entry.actor.value,
};

/// The Actor inside a sentence: `you`, `bank sync`.
String actorPhrase(HistoryEntry entry) => switch (entry.actor.kind) {
  ActorKind.person => 'you',
  ActorKind.mcp => 'MCP (${entry.actor.mcpClient})',
  ActorKind.revert => 'a revert',
  _ => actorLabel(entry).toLowerCase(),
};

/// An icon and a label for the Actor, never color alone.
class ActorBadge extends StatelessWidget {
  const ActorBadge(this.entry, {super.key});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, background, foreground) = switch (entry.actor.kind) {
      ActorKind.person => (Icons.person_outline, Palette.zeroPill, Palette.ink),
      ActorKind.bankSync => (
        Icons.account_balance_outlined,
        Palette.bankPill,
        Palette.bankText,
      ),
      ActorKind.automation => (
        Icons.bolt,
        Palette.positivePill,
        Palette.positiveText,
      ),
      ActorKind.import => (
        Icons.file_download_outlined,
        Palette.zeroPill,
        Palette.inkSoft,
      ),
      ActorKind.mcp => (Icons.code, Palette.mcpPill, Palette.mcpText),
      ActorKind.revert => (Icons.history, Palette.zeroPill, Palette.inkSoft),
      ActorKind.other => (
        Icons.help_outline,
        Palette.zeroPill,
        Palette.inkSoft,
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: foreground),
        ),
        Flexible(
          child: Text(
            actorLabel(entry),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Palette.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.history,
    required this.onRevert,
    required this.onRedact,
  });

  final HistoryEntry entry;
  final ChangeHistory history;
  final VoidCallback onRevert;

  /// Null when the entry's entity has no value left to redact.
  final VoidCallback? onRedact;

  @override
  Widget build(BuildContext context) {
    final device = switch (history.devicePlatform(entry.deviceId)) {
      'android' => 'Android · ',
      'mac' => 'Mac · ',
      _ => '',
    };
    final action = entry.isRevert
        ? (entry.isRedo ? 'Undo' : 'Redo')
        : entry.events.length > 1
        ? 'Revert group'
        : 'Revert';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Palette.card,
        border: Border.all(color: Palette.cardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(child: ActorBadge(entry)),
              Text(
                '$device${formatTime(entry.time)}',
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
            ],
          ),
          Text(entry.summary, style: const TextStyle(fontSize: 14)),
          for (final change in entry.changes) _ChangeLine(change),
          if (onRedact != null || entry.revertedBy != null || entry.canRevert)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 6,
              children: [
                if (onRedact != null)
                  TextButton(
                    onPressed: onRedact,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: Palette.problemText,
                      textStyle: const TextStyle(
                        fontFamily: sansFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Redact'),
                  ),
                if (entry.revertedBy != null)
                  const Hint('Reverted')
                else if (entry.canRevert)
                  OutlinedButton(
                    onPressed: onRevert,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: const TextStyle(
                        fontFamily: sansFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: Text(action),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// `Memo  empty → “Client lunch”`, the before struck through. A value that
/// lost to another device's is noted `overwritten by sync` (ticket 06).
class _ChangeLine extends StatelessWidget {
  const _ChangeLine(this.change);

  final HistoryChange change;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, color: Palette.inkSoft);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '${change.label}  '),
          if (change.before case final before?) ...[
            TextSpan(
              text: before,
              style: const TextStyle(
                color: Palette.muted,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const TextSpan(text: ' → '),
          ],
          TextSpan(text: change.after ?? ''),
          if (change.note case final note?)
            TextSpan(
              text: '  $note',
              style: const TextStyle(
                fontSize: 11,
                color: Palette.muted,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
