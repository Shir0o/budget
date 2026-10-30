import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Import & compare (ticket 14): load a YNAB export and hold it against the
/// imported Actual history. The four checks of ticket 14 are shown with the
/// expected differences labelled, and every YNAB-only item waits for a tap
/// before it is pulled in or skipped.
class ImportCompareScreen extends StatefulWidget {
  const ImportCompareScreen({
    super.key,
    required this.engine,
    required this.services,
  });

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<ImportCompareScreen> createState() => _ImportCompareScreenState();
}

class _ImportCompareScreenState extends State<ImportCompareScreen> {
  Uint8List? _bytes;
  YnabExport? _export;
  NamePairing? _pairing;
  YnabComparison? _comparison;
  final _decisions = <String, PullDecision>{};
  var _busy = false;
  var _error = '';
  ImportCommit? _lastCommit;

  BudgetState get _state => widget.engine.state;

  /// The comparison only means something once Actual's history is in.
  bool get _hasHistory => _state.accounts.isNotEmpty;

  Future<void> _choose() async {
    if (_busy || !_hasHistory) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final bytes = await widget.services.keepUnlocked(
        () => widget.services.loader.pick(extensions: ['zip']),
      );
      if (bytes == null) return;
      _bytes = bytes;
      _read();
    } on YnabExportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'Could not read that file. Is it a YNAB export zip?',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reading the zip happens when the file is chosen, never in build.
  void _read([YnabDateOrder? dateOrder]) {
    final bytes = _bytes;
    if (bytes == null) return;
    final export = YnabExport.read(YnabZip.decode(bytes, dateOrder: dateOrder));
    setState(() {
      _export = export;
      _pairing = proposePairs(ynab: export, actual: _state);
      _comparison = _compare(export, _pairing!);
      _lastCommit = null;
    });
  }

  YnabComparison _compare(YnabExport export, NamePairing pairing) =>
      compareWithYnab(ynab: export, actual: _state, pairing: pairing);

  void _setPair(NamePair pair, String? actualId) {
    final export = _export;
    if (export == null) return;
    final pairing = _pairing!.withPair(
      kind: pair.kind,
      ynabName: pair.ynabName,
      actualId: actualId,
      actualName: actualId == null ? null : _actualName(pair.kind, actualId),
    );
    setState(() {
      _pairing = pairing;
      _comparison = _compare(export, pairing);
    });
  }

  String? _actualName(PairKind kind, String id) => switch (kind) {
    PairKind.account => _state.account(id)?.name,
    PairKind.categoryGroup => _state.categoryGroup(id)?.name,
    PairKind.category => _state.category(id)?.name,
  };

  List<(String, String)> _candidates(PairKind kind) => switch (kind) {
    PairKind.account => [
      for (final account in _state.accounts) (account.id, account.name),
    ],
    PairKind.categoryGroup => [
      for (final group in _state.categoryGroups) (group.id, group.name),
    ],
    PairKind.category => [
      for (final category in _state.categories) (category.id, category.name),
    ],
  };

  void _decide(PullTarget target, PullDecision? decision) => setState(() {
    if (decision == null) {
      _decisions.remove(target.key);
    } else {
      _decisions[target.key] = decision;
    }
  });

  Future<void> _ignore(PullTarget target) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Why does it stay out?'),
        children: [
          for (final reason in const [
            'Already in the budget',
            'Not my transaction',
            'A typo in YNAB',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(reason),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(reason, style: const TextStyle(fontSize: 15)),
              ),
            ),
        ],
      ),
    );
    if (!mounted || reason == null) return;
    _decide(target, PullDecision.ignore(reason));
  }

  Future<void> _commit() async {
    final comparison = _comparison;
    if (_busy || comparison == null) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final batch = pullBatch(comparison: comparison, decisions: _decisions);
      final commit = commitYnabPull(widget.engine, batch);
      if (!mounted) return;
      setState(() {
        _lastCommit = commit;
        _decisions.clear();
        _comparison = _compare(comparison.ynab, _pairing!);
      });
    } on ImportBlocked {
      if (mounted) {
        setState(
          () => _error =
              'The pull-in was refused and nothing was written. That is a '
              'bug in the comparison; the file is untouched.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final export = _export;
    final comparison = _comparison;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Import & compare'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (_error.isNotEmpty) ...[
                    _Banner(
                      key: const ValueKey('ynab-error'),
                      background: Palette.problemPill,
                      foreground: Palette.problemText,
                      lines: [_error],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_lastCommit case final commit?) ...[
                    _Banner(
                      key: const ValueKey('ynab-done'),
                      background: Palette.positivePill,
                      foreground: Palette.positiveText,
                      lines: [
                        'Pulled in ${commit.transactions} '
                            '${commit.transactions == 1 ? 'transaction' : 'transactions'}'
                            ' and ${commit.assignments} '
                            '${commit.assignments == 1 ? 'assignment' : 'assignments'}'
                            ' as one group you can revert from Change History.',
                        'Every pulled-in line is in Review: only your tap marks '
                            'it Reviewed.',
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!_hasHistory)
                    _Banner(
                      key: const ValueKey('ynab-no-history'),
                      background: Palette.summary,
                      foreground: Palette.inkSoft,
                      lines: const [
                        'Import from Actual first. This compares a YNAB export '
                            'with the history already in this budget.',
                      ],
                    )
                  else if (export == null)
                    _picker()
                  else ...[
                    _summary(export),
                    if (export.dateOrderAmbiguous) ...[
                      const SizedBox(height: 12),
                      _dateOrder(export),
                    ],
                    if (comparison != null) ...[
                      const SizedBox(height: 12),
                      _pairs(comparison.pairing),
                      for (final check in ComparisonCheck.values) ...[
                        const SizedBox(height: 12),
                        _check(comparison, check),
                      ],
                      const SizedBox(height: 12),
                      _commitCard(comparison),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('ynab-choose-again'),
                      onPressed: _busy ? null : _choose,
                      child: const Text('Choose another file'),
                    ),
                    const SizedBox(height: 12),
                    const InfoNote(
                      'The file is read on this phone and never uploaded. '
                      'Nothing is merged without your tap, and a pulled-in '
                      'line still waits for Review.',
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

  Widget _picker() => CardBox(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const Text(
          'YNAB export',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const Hint(
          'In YNAB, choose Export budget, then pick the .zip here. It is '
          'compared with the history you imported, never uploaded.',
        ),
        FilledButton(
          key: const ValueKey('choose-ynab-export'),
          onPressed: _busy ? null : _choose,
          child: Text(_busy ? 'Reading…' : 'Choose file'),
        ),
      ],
    ),
  );

  Widget _summary(YnabExport export) {
    final first = export.firstMonth;
    final last = export.lastMonth;
    final rows = [
      ('Transactions', '${export.entries.length}'),
      (
        'Months',
        first == null || last == null
            ? 'No transactions'
            : first == last
            ? formatMonth(first)
            : '${formatMonth(first)} – ${formatMonth(last)}',
      ),
      ('Budgeted months', '${export.plan.length} category months'),
      (
        'Names',
        '${_pairing!.pairs.where((pair) => pair.isPaired).length} of '
            '${_pairing!.pairs.length} paired',
      ),
    ];
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (label, value)) in rows.indexed)
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(top: BorderSide(color: Palette.divider)),
              ),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Palette.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// YNAB writes dates in the user's own setting. When every sampled day is
  /// 12 or less the order is ambiguous, so the person answers (ticket 02).
  Widget _dateOrder(YnabExport export) => CardBox(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        const Text(
          'Date order',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const Hint(
          'Every date in this export reads either way. Which way does '
          '3/4/2024 read?',
        ),
        Segmented<YnabDateOrder>(
          key: const ValueKey('ynab-date-order'),
          selected: export.dateOrder,
          options: const [
            (YnabDateOrder.monthFirst, 'Month first'),
            (YnabDateOrder.dayFirst, 'Day first'),
          ],
          onChanged: (order) => _read(order),
        ),
      ],
    ),
  );

  Widget _pairs(NamePairing pairing) {
    final toConfirm = [
      for (final pair in pairing.pairs)
        if (pair.proposed || !pair.isPaired) pair,
    ];
    final exact = pairing.pairs.where((pair) => pair.isPaired).length;
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          const Text(
            'Names',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          Hint(
            toConfirm.isEmpty
                ? '$exact names pair exactly.'
                : 'Exact names pair first. These are the rest: confirm a name '
                      'or say it isn’t in this budget.',
          ),
          for (final pair in toConfirm) _pair(pair),
        ],
      ),
    );
  }

  Widget _pair(NamePair pair) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 4,
    children: [
      Text(
        '${_pairKindLabel(pair.kind)} · ${pair.ynabName}',
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: Palette.card,
          border: Border.all(color: Palette.fieldBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: ValueKey('ynab-pair-${pair.kind.name}-${pair.ynabName}'),
            value: pair.actualId ?? '',
            isExpanded: true,
            isDense: true,
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Not in this budget'),
              ),
              for (final (id, name) in _candidates(pair.kind))
                DropdownMenuItem(value: id, child: Text(name)),
            ],
            onChanged: _busy
                ? null
                : (value) => _setPair(
                    pair,
                    value == null || value.isEmpty ? null : value,
                  ),
          ),
        ),
      ),
    ],
  );

  Widget _check(YnabComparison comparison, ComparisonCheck check) {
    final tally = comparison.tallyFor(check);
    final items = comparison.itemsFor(check);
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            '(${check.letter}) ${check.title}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          Text(
            _tallyLine(tally),
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: tally.isClear && tally.expected == 0
                  ? Palette.teal
                  : Palette.inkSoft,
            ),
          ),
          if (items.isEmpty)
            const Hint('Nothing to look at.')
          else
            for (final item in items) _item(item),
        ],
      ),
    );
  }

  String _tallyLine(ComparisonTally tally) {
    final parts = <String>[
      if (tally.matched > 0) '${tally.matched} matched',
      if (tally.differs > 0) '${tally.differs} differ',
      if (tally.expected > 0) '${tally.expected} expected',
      if (tally.ynabOnly > 0) '${tally.ynabOnly} only in YNAB',
      if (tally.actualOnly > 0) '${tally.actualOnly} only in the budget',
    ];
    return parts.isEmpty ? 'Nothing to compare.' : parts.join(' · ');
  }

  Widget _item(ComparisonItem item) {
    final expected = item.status == ComparisonStatus.expected;
    final pull = item.pull;
    final decision = pull == null ? null : _decisions[pull.key];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Text(
            item.label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
          if (item.detail.isNotEmpty)
            Text(
              expected ? 'Expected · ${item.detail}' : item.detail,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: item.status == ComparisonStatus.differs
                    ? Palette.problemText
                    : Palette.muted,
              ),
            ),
          if (pull != null)
            if (decision == null)
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: FilledButton(
                      key: ValueKey('ynab-add-${pull.key}'),
                      onPressed: _busy
                          ? null
                          : () => _decide(pull, const PullDecision.add()),
                      child: const Text('Add to budget'),
                    ),
                  ),
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey('ynab-ignore-${pull.key}'),
                      onPressed: _busy ? null : () => _ignore(pull),
                      child: const Text('Ignore'),
                    ),
                  ),
                ],
              )
            else
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      decision.isAdd
                          ? 'Will be added'
                          : 'Ignored · ${decision.reason}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Palette.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    key: ValueKey('ynab-change-${pull.key}'),
                    onPressed: _busy ? null : () => _decide(pull, null),
                    child: const Text('Change'),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  Widget _commitCard(YnabComparison comparison) {
    final pulls = comparison.pullItems;
    final unresolved = comparison.unresolved(_decisions);
    final adds = _decisions.values.where((decision) => decision.isAdd).length;
    if (pulls.isEmpty) {
      return const CardBox(
        padding: EdgeInsets.all(16),
        child: Hint('Nothing is left to pull in.'),
      );
    }
    return CardBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text(
            unresolved.isEmpty
                ? 'Every YNAB-only item is decided.'
                : '${unresolved.length} of ${pulls.length} still to decide.',
            style: const TextStyle(fontSize: 13, color: Palette.inkSoft),
          ),
          FilledButton(
            key: const ValueKey('ynab-pull'),
            onPressed: _busy || unresolved.isNotEmpty || adds == 0
                ? null
                : _commit,
            child: Text(_busy ? 'Pulling in…' : 'Pull in and finish'),
          ),
        ],
      ),
    );
  }
}

String _pairKindLabel(PairKind kind) => switch (kind) {
  PairKind.account => 'Account',
  PairKind.categoryGroup => 'Category group',
  PairKind.category => 'Category',
};

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.background,
    required this.foreground,
    required this.lines,
  });

  final Color background;
  final Color foreground;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        for (final line in lines)
          Text(
            line,
            style: TextStyle(fontSize: 13, color: foreground, height: 1.4),
          ),
      ],
    ),
  );
}
