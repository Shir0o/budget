import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';
import 'package:flutter/material.dart';

import '../import_draft.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Import from Actual (ticket 14), step three: map each Actual `#tag` and
/// used Category to a Business Tag or nothing, then commit the whole plan as
/// one group. A line that maps to two tags goes to Review instead.
class MapTagsScreen extends StatefulWidget {
  const MapTagsScreen({super.key, required this.engine, required this.draft});

  final BudgetEngine engine;
  final ImportDraft draft;

  @override
  State<MapTagsScreen> createState() => _MapTagsScreenState();
}

class _MapTagsScreenState extends State<MapTagsScreen> {
  late final List<TagMapping> _tags = List.of(widget.draft.tags);
  var _busy = false;
  var _error = '';

  List<String> get _tagNames => [
    for (final tag in widget.engine.state.businessTags) tag.name,
  ];

  void _setTag(int index, String? tag) {
    setState(() {
      _tags[index] = _tags[index].withTag(tag);
      widget.draft.tags
        ..clear()
        ..addAll(_tags);
    });
  }

  Future<void> _commit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final commit = commitImport(widget.engine, widget.draft.plan());
      if (mounted) Navigator.of(context).pop(commit);
    } on ImportBlocked catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.reason) {
            Rejection.importBalanceMismatch =>
              'An account doesn’t match Actual to the cent, so nothing was '
                  'imported. That is a bug in the importer; the file is '
                  'untouched.',
            _ => 'The import was refused and nothing was written.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.draft.plan();
    final report = plan.report;
    final tags = _tags.where((m) => m.source == TagSource.tag).toList();
    final categories = _tags
        .where((m) => m.source == TagSource.category)
        .toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Map tags'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (_error.isNotEmpty) ...[
                    Container(
                      key: const ValueKey('import-blocked'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Palette.problemPill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _error,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Palette.problemText,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Hint(
                    'Each tag and Category becomes one Business Tag, or '
                    'nothing. Tags stay in the memo either way.',
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _tagSection('Actual #tags', tags),
                  ],
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _tagSection('Categories used', categories),
                  ],
                  const SizedBox(height: 12),
                  _summary(plan, report),
                  if (report.warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _warnings(report.warnings),
                  ],
                  if (!report.balancesMatch) ...[
                    const SizedBox(height: 12),
                    _warnings([
                      for (final mismatch in report.balanceMismatches)
                        '$mismatch',
                    ]),
                  ],
                  const SizedBox(height: 12),
                  CardBox(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      key: const ValueKey('import-commit'),
                      onPressed: _busy || !report.balancesMatch
                          ? null
                          : _commit,
                      child: Text(_busy ? 'Importing…' : 'Import'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagSection(String title, List<TagMapping> mappings) => CardBox(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Palette.muted,
              letterSpacing: 0.72,
            ),
          ),
        ),
        for (final (i, mapping) in mappings.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : const Border(top: BorderSide(color: Palette.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Text(
                        mapping.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    Text(
                      '${mapping.count}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Palette.muted,
                      ),
                    ),
                  ],
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
                      key: ValueKey(
                        'tag-map-${mapping.source.name}-${mapping.key}',
                      ),
                      value: mapping.tag ?? '',
                      isExpanded: true,
                      isDense: true,
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Nothing'),
                        ),
                        for (final name in _tagNames)
                          DropdownMenuItem(value: name, child: Text(name)),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => _setTag(
                              _tags.indexOf(mapping),
                              value == null || value.isEmpty ? null : value,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _summary(ImportPlan plan, ImportReport report) => CardBox(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (label, value)) in [
          ('Transactions', '${report.transactions}'),
          ('Lines', '${report.lines}'),
          ('Reviewed', '${report.reviewedLines}'),
          ('To Review', '${report.unreviewedLines}'),
          ('Assignments', '${plan.assignments.length}'),
          ('Scheduled transactions', '${plan.schedules.length}'),
          ('Targets', '${plan.targets.length}'),
          ('Rules not imported', '${report.rules}'),
          (
            'Balances',
            report.balancesMatch
                ? 'Every account matches Actual'
                : '${report.balanceMismatches.length} off',
          ),
        ].indexed)
          Container(
            constraints: const BoxConstraints(minHeight: 44),
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
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    color: label == 'Balances' && report.balancesMatch
                        ? Palette.teal
                        : Palette.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

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
