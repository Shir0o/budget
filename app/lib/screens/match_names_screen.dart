import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';
import 'package:flutter/material.dart';

import '../import_draft.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'map_tags_screen.dart';

/// Import from Actual (ticket 14), step two: the names the import creates.
///
/// Pairing these names with a YNAB export happens on Import & compare; this
/// screen is where the person checks them first.
class MatchNamesScreen extends StatefulWidget {
  const MatchNamesScreen({
    super.key,
    required this.engine,
    required this.draft,
  });

  final BudgetEngine engine;
  final ImportDraft draft;

  @override
  State<MatchNamesScreen> createState() => _MatchNamesScreenState();
}

class _MatchNamesScreenState extends State<MatchNamesScreen> {
  Future<void> _mapTags() async {
    final commit = await Navigator.of(context).push<ImportCommit>(
      MaterialPageRoute(
        builder: (_) =>
            MapTagsScreen(engine: widget.engine, draft: widget.draft),
      ),
    );
    if (!mounted || commit == null) return;
    Navigator.of(context).pop(commit);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.draft.plan();
    final groups = {for (final group in plan.categoryGroups) group.id: group};
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Match names'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  const Hint(
                    'These are the names the import creates. Actual’s '
                    '“Credit Card Payments” Category is derived instead, one '
                    'per card.',
                  ),
                  const SizedBox(height: 12),
                  _section('Accounts', [
                    for (final account in plan.accounts)
                      (account.name, _accountTypeLabel(account.type)),
                  ]),
                  const SizedBox(height: 12),
                  _section('Category groups', [
                    for (final group in plan.categoryGroups) (group.name, ''),
                  ]),
                  const SizedBox(height: 12),
                  _section('Categories', [
                    for (final category in plan.categories)
                      (
                        category.name,
                        category.income
                            ? 'Ready to Assign'
                            : category.cardAccountId != null
                            ? 'Card payment'
                            : groups[category.groupId]?.name ?? 'Imported',
                      ),
                  ]),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      key: const ValueKey('import-map-tags'),
                      onPressed: _mapTags,
                      child: const Text('Map tags'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InfoNote(
                    '${plan.report.reviewedLines} earlier-year lines import '
                    'Reviewed. ${plan.report.unreviewedLines} lines from '
                    '${plan.currentTaxYear} import Unreviewed and pre-filled, '
                    'and wait for your tap.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<(String, String)> rows) => CardBox(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
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
        for (final (i, (label, value)) in rows.indexed)
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
                  style: const TextStyle(fontSize: 13, color: Palette.muted),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

String _accountTypeLabel(AccountType type) => switch (type) {
  AccountType.checking => 'Checking',
  AccountType.savings => 'Savings',
  AccountType.cash => 'Cash',
  AccountType.creditCard => 'Credit card',
  AccountType.tracking => 'Tracking',
};
