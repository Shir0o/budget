import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Redact a field (canvas: Redact field, ticket 11): the one place a value
/// that got stored anyway can be replaced with `[redacted]` in every past
/// change and snapshot, on this device and the other one.
class RedactScreen extends StatefulWidget {
  const RedactScreen({super.key, required this.engine, required this.entity});

  final BudgetEngine engine;
  final EntityRef entity;

  @override
  State<RedactScreen> createState() => _RedactScreenState();
}

class _RedactScreenState extends State<RedactScreen> {
  late final List<RedactCandidate> _candidates = redactCandidates(
    widget.engine.state,
    widget.entity,
  );
  RedactTarget? _chosen;

  Future<void> _redact() async {
    final target = _chosen;
    if (target == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Redact this field?'),
            content: const Text(
              'The value is replaced with [redacted] everywhere it appears '
              'in Change History, and on your other devices. This can’t be '
              'undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Palette.problemText,
                ),
                child: const Text('Redact'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final result = widget.engine.execute(RedactField(targets: [target]));
    if (!mounted) return;
    switch (result) {
      case Rejected(:final reason):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (reason) {
              Rejection.personRequired ||
              Rejection.cannotRedact => 'That field can’t be redacted.',
              Rejection.noChange => 'That value is already gone.',
              _ => 'That field can’t be redacted.',
            }),
          ),
        );
      case Accepted():
        Navigator.of(context).pop(true);
    }
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
                const Expanded(
                  child: Text(
                    'Redact a field',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                CardBox(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 10,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: Palette.problemText,
                      ),
                      Expanded(
                        child: Text(
                          'Use this for a card or account number that got '
                          'stored by mistake. The value becomes '
                          '$redactedValue in every past change and on your '
                          'other devices. It can’t be undone.',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Palette.problemText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_candidates.isEmpty)
                  const CardBox(child: Hint('Nothing here can be redacted.'))
                else ...[
                  CardBox(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final candidate in _candidates)
                          _CandidateRow(
                            candidate: candidate,
                            selected: candidate.target == _chosen,
                            onTap: () =>
                                setState(() => _chosen = candidate.target),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Hint('Pick the field that holds the number.'),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              onPressed: _chosen == null ? null : _redact,
              style: FilledButton.styleFrom(
                backgroundColor: Palette.ink,
                foregroundColor: Palette.background,
                minimumSize: const Size(0, 48),
              ),
              child: const Text('Redact field'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// One field and its current value, chosen like a radio row.
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final RedactCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${candidate.label}, ${candidate.value}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            spacing: 12,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? Palette.teal : Palette.muted,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      candidate.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Palette.inkSoft,
                      ),
                    ),
                    Text(
                      candidate.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
