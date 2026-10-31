import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'business_parts.dart';
import 'business_report_screen.dart';

/// Business report in the desktop window (ticket 67): the year's totals and a
/// total per Business Tag on the left, the selected tag's lines beside them,
/// a flag for lines still waiting for Review, and Export CSV. The CSV files
/// are made on the device; nothing is uploaded.
class DesktopBusinessReportScreen extends StatefulWidget {
  const DesktopBusinessReportScreen({
    super.key,
    required this.engine,
    required this.services,
  });

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<DesktopBusinessReportScreen> createState() =>
      _DesktopBusinessReportScreenState();
}

/// Below this content width the tag's lines wrap under the totals.
const _besideWidth = 940.0;
const _summaryWidth = 420.0;

class _DesktopBusinessReportScreenState
    extends State<DesktopBusinessReportScreen> {
  late var _year = today().year;
  var _busy = false;

  /// The Business Tag whose lines are shown. Null picks the first row.
  String? _tag;

  BudgetState get _state => widget.engine.state;

  Future<void> _save(String fileName, String text) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await widget.services.keepUnlocked(
        () => widget.services.saver.save(
          fileName: fileName,
          bytes: Uint8List.fromList(utf8.encode(text)),
          mimeType: 'text/csv',
        ),
      );
      if (saved) {
        messenger.showSnackBar(SnackBar(content: Text('Saved $fileName')));
      }
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save the file')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _state.businessReport(_year);
    final years = businessYears(_state);
    final selected =
        report.rows.where((row) => row.tag.name == _tag).firstOrNull ??
        report.rows.firstOrNull;
    final lines = [
      for (final line in report.lines)
        if (line.tag.name == selected?.tag.name) line,
    ];
    final unreviewed = [
      for (final warning in report.warnings)
        if (warning is UnreviewedLines) warning,
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              // The year and the two exports sit on the title's line, or
              // under it when the window is narrow.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text(
                    'Business report',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 200,
                        child: BusinessYearPicker(
                          years: years,
                          year: _year,
                          onChanged: (year) => setState(() {
                            _year = year;
                            _tag = null;
                          }),
                        ),
                      ),
                      OutlinedButton(
                        key: const ValueKey('business-export-detail'),
                        onPressed: _busy
                            ? null
                            : () => _save(
                                'business-detail-${report.year}.csv',
                                businessDetailCsv(report),
                              ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: const Text('Export detail CSV'),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('business-export'),
                        onPressed: _busy
                            ? null
                            : () => _save(
                                'business-summary-${report.year}.csv',
                                businessSummaryCsv(report),
                              ),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Export CSV'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (report.hasWarnings)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _Warnings(
                  key: unreviewed.isEmpty
                      ? null
                      : const ValueKey('business-review-flag'),
                  warnings: report.warnings,
                  year: report.year,
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final summary = _Summary(
                    report: report,
                    selected: selected?.tag.name,
                    onSelect: (tag) => setState(() => _tag = tag),
                  );
                  final detail = _TagLines(
                    year: report.year,
                    summary: selected,
                    lines: lines,
                  );
                  if (constraints.maxWidth < _besideWidth) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: [summary, detail],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        SizedBox(
                          width: _summaryWidth,
                          child: SingleChildScrollView(child: summary),
                        ),
                        Expanded(child: SingleChildScrollView(child: detail)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The warnings that would make the report wrong, in one strip.
class _Warnings extends StatelessWidget {
  const _Warnings({super.key, required this.warnings, required this.year});

  final List<BusinessWarning> warnings;
  final int year;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: Palette.problemPill,
      border: Border.all(color: Palette.problemBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Palette.problemText,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              for (final warning in warnings)
                Text(
                  businessWarningText(warning, year),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Palette.problemText,
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

/// The year's totals and one selectable row per Business Tag.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.report,
    required this.selected,
    required this.onSelect,
  });

  final BusinessReport report;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            const Text(
              'TOTALS',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.88,
                color: Palette.muted,
              ),
            ),
            _TotalRow(label: 'Self-employment income', amount: report.income),
            _TotalRow(
              label: 'Deductible expenses',
              amount: report.deductibleExpenses,
            ),
            const Divider(height: 8, color: Palette.divider),
            _TotalRow(label: 'Net', amount: report.net, strong: true),
          ],
        ),
      ),
      CardBox(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'By tag',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (report.rows.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Hint('No Business Tagged lines in this year.'),
              ),
            for (final row in report.rows)
              _TagRow(
                row: row,
                selected: row.tag.name == selected,
                onTap: () => onSelect(row.tag.name),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          businessReportFooter,
          key: const ValueKey('business-footer'),
          style: const TextStyle(fontSize: 12, color: Palette.muted),
        ),
      ),
    ],
  );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    this.strong = false,
  });

  final String label;
  final Money amount;
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 12,
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: strong ? 15 : 14,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
      Text(
        amount.formatDollars(),
        style: amountStyle(
          fontSize: strong ? 20 : 15,
          fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ],
  );
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final BusinessSummaryRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('business-tag-row-${row.tag.name}'),
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? Palette.zeroPill : null,
        border: const Border(top: BorderSide(color: Palette.divider)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.tag.name, style: const TextStyle(fontSize: 14)),
                Text(
                  row.tag.rule.label,
                  style: const TextStyle(fontSize: 11, color: Palette.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(row.gross.formatDollars(), style: amountStyle(fontSize: 14)),
              Text(
                'deductible ${row.deductible.formatDollars()}',
                style: const TextStyle(fontSize: 11, color: Palette.muted),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// The selected Business Tag's lines for the year.
class _TagLines extends StatelessWidget {
  const _TagLines({
    required this.year,
    required this.summary,
    required this.lines,
  });

  final int year;
  final BusinessSummaryRow? summary;
  final List<BusinessLine> lines;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    return CardBox(
      key: const ValueKey('business-tag-lines'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Text(
                    summary == null ? 'Lines' : summary.tag.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (summary != null)
                  Text(
                    '${lines.length == 1 ? '1 line' : '${lines.length} lines'} '
                    '· $year',
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
              ],
            ),
          ),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Hint('No lines for this tag.'),
            ),
          for (final line in lines) _LineRow(line: line),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final BusinessLine line;

  @override
  Widget build(BuildContext context) {
    final transaction = line.transaction;
    final recipient = line.line.recipient?.trim() ?? '';
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.divider)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.payee.isEmpty ? 'No payee' : transaction.payee,
                  style: const TextStyle(fontSize: 15),
                ),
                Text(
                  [
                    formatDate(transaction.date),
                    line.account,
                    if (recipient.isNotEmpty) recipient,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: Palette.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatSigned(line.line.amount),
                style: amountStyle(fontSize: 15),
              ),
              Text(
                'deductible ${line.deductible.formatDollars()}',
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
