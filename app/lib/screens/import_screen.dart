import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';
import 'package:flutter/material.dart';

import '../import_draft.dart';
import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'match_names_screen.dart';

/// Import from Actual (ticket 14), step one: pick the export and see what is
/// in it. The zip is read here and nothing is written until the commit on
/// Map tags, so the wizard can be backed out of at any step.
class ImportActualScreen extends StatefulWidget {
  const ImportActualScreen({
    super.key,
    required this.engine,
    required this.services,
  });

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<ImportActualScreen> createState() => _ImportActualScreenState();
}

class _ImportActualScreenState extends State<ImportActualScreen> {
  ImportDraft? _draft;
  ImportCommit? _commit;
  var _busy = false;
  var _error = '';

  /// The import is one time per budget (ticket 14): a second run would
  /// duplicate every account and transaction.
  bool get _canImport =>
      widget.engine.state.accounts.isEmpty &&
      widget.engine.state.transactions.isEmpty;

  Future<void> _choose() async {
    if (_busy || !_canImport) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final bytes = await widget.services.keepUnlocked(
        () => widget.services.loader.pick(extensions: ['zip']),
      );
      if (bytes == null) return;
      final export = _read(bytes);
      if (!mounted) return;
      setState(() {
        _draft = ImportDraft(
          export: export,
          tags: defaultTagMappings(export),
          today: today(),
        );
        _commit = null;
      });
    } on ActualExportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Could not read that file. Is it an Actual '
              'export zip?',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reading the database happens when a file is chosen, never in build.
  ActualExport _read(Uint8List bytes) =>
      ActualExport.read(ActualZip.decode(bytes));

  Future<void> _matchNames() async {
    final draft = _draft;
    if (draft == null) return;
    final commit = await Navigator.of(context).push<ImportCommit>(
      MaterialPageRoute(
        builder: (_) => MatchNamesScreen(engine: widget.engine, draft: draft),
      ),
    );
    if (!mounted || commit == null) return;
    setState(() {
      _commit = commit;
      _draft = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final commit = _commit;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Import from Actual'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (_error.isNotEmpty) ...[
                    _Banner(
                      key: const ValueKey('import-error'),
                      icon: Icons.error_outline,
                      background: Palette.problemPill,
                      foreground: Palette.problemText,
                      lines: [_error],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (commit != null) ...[
                    _Banner(
                      key: const ValueKey('import-done'),
                      icon: Icons.check_circle_outline,
                      background: Palette.positivePill,
                      foreground: Palette.positiveText,
                      lines: [
                        'Imported ${commit.transactions} transactions as one '
                            'group you can revert from Change History.',
                        'Earlier years are Reviewed; the current tax year is '
                            'in Review.',
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (draft == null)
                    if (_canImport)
                      _picker()
                    else
                      _Banner(
                        key: const ValueKey('import-not-empty'),
                        icon: Icons.info_outline,
                        background: Palette.summary,
                        foreground: Palette.inkSoft,
                        lines: const [
                          'This budget already has history. An import is one '
                              'time per budget, so start a new budget to bring '
                              'Actual’s history in.',
                        ],
                      )
                  else
                    _summary(draft),
                  const SizedBox(height: 12),
                  const InfoNote(
                    'The file is read on this phone and never uploaded. '
                    'Actual’s rules are listed, not imported: nothing '
                    'categorizes a transaction for you.',
                  ),
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
          'Actual export',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const Hint(
          'In Actual, choose Close file → Export, then pick the .zip here. '
          'The whole history becomes one import you can revert.',
        ),
        FilledButton(
          key: const ValueKey('choose-actual-export'),
          onPressed: _busy ? null : _choose,
          child: Text(_busy ? 'Reading…' : 'Choose file'),
        ),
      ],
    ),
  );

  Widget _summary(ImportDraft draft) {
    final plan = draft.plan();
    final report = plan.report;
    final rows = [
      ('Accounts', '${report.accounts}'),
      ('Category groups', '${report.categoryGroups}'),
      (
        'Categories',
        report.incomeCategories == 0
            ? '${report.categories}'
            : '${report.categories} + ${report.incomeCategories} income',
      ),
      ('Transactions', '${report.transactions} (${report.lines} lines)'),
      ('Months', '${report.months}'),
      ('Scheduled transactions', '${report.schedules}'),
      ('Rules not imported', '${report.rules}'),
      (
        'Through',
        report.lastTransactionDate == null
            ? 'No transactions'
            : formatDate(report.lastTransactionDate!),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        CardBox(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (label, value)) in rows.indexed)
                _Row(label: label, value: value, first: i == 0),
            ],
          ),
        ),
        CardBox(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              FilledButton(
                key: const ValueKey('import-match-names'),
                onPressed: _busy ? null : _matchNames,
                child: const Text('Match names'),
              ),
              OutlinedButton(
                key: const ValueKey('import-choose-again'),
                onPressed: _busy ? null : _choose,
                child: const Text('Choose another file'),
              ),
            ],
          ),
        ),
        if (report.warnings.isNotEmpty) _warnings(report.warnings),
      ],
    );
  }

  Widget _warnings(List<String> warnings) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Palette.summary,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        for (final warning in warnings)
          Text(
            warning,
            style: const TextStyle(
              fontSize: 13,
              color: Palette.inkSoft,
              height: 1.4,
            ),
          ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.first});

  final String label;
  final String value;
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    decoration: BoxDecoration(
      border: first
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
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.lines,
  });

  final IconData icon;
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
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: foreground),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              for (final line in lines)
                Text(
                  line,
                  style: TextStyle(
                    fontSize: 13,
                    color: foreground,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
