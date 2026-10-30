import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'business_parts.dart';

/// Business report (canvas: Business report): one tax year's Business Tags,
/// warnings, totals, every tagged line, and the two CSV files. The files are
/// made on the phone; nothing is uploaded.
class BusinessReportScreen extends StatefulWidget {
  const BusinessReportScreen({
    super.key,
    required this.engine,
    required this.services,
  });

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<BusinessReportScreen> createState() => _BusinessReportScreenState();
}

class _BusinessReportScreenState extends State<BusinessReportScreen> {
  late var _year = today().year;
  var _busy = false;

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

  String _warningText(BusinessWarning warning, int year) => switch (warning) {
    UnreviewedLines(:final count) =>
      '$count Unreviewed ${count == 1 ? 'line' : 'lines'} in $year. Review '
          '${count == 1 ? 'it' : 'them'} before relying on this report.',
    MissingBusinessUse(:final tag) =>
      'Set a business-use % for ${tag.name} in $year.',
    GiftWithoutRecipient(:final line) =>
      'A gift to '
          '${line.transaction.payee.isEmpty ? 'no payee' : line.transaction.payee} '
          'on ${formatDate(line.transaction.date)} has no recipient, so it '
          'doesn’t count.',
  };

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final report = state.businessReport(_year);
    final years = businessYears(state);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Business report'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Hint(
                      'Every line you tagged for business in the year, and '
                      'what each rule makes deductible.',
                    ),
                  ),
                  CardBox(
                    child: BusinessYearPicker(
                      years: years,
                      year: _year,
                      onChanged: (year) => setState(() => _year = year),
                    ),
                  ),
                  if (report.hasWarnings) ...[
                    const SizedBox(height: 12),
                    CardBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 10,
                        children: [
                          const Text(
                            'Warnings',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          for (final warning in report.warnings)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 8,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: Palette.problemText,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _warningText(warning, report.year),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 8,
                      children: [
                        _TotalRow(
                          label: 'Self-employment income',
                          amount: report.income,
                        ),
                        _TotalRow(
                          label: 'Deductible expenses',
                          amount: report.deductibleExpenses,
                        ),
                        const Divider(height: 8, color: Palette.divider),
                        _TotalRow(
                          label: 'Net',
                          amount: report.net,
                          strong: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _CardHeader('By tag'),
                        if (report.rows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                            child: Hint(
                              'No Business Tagged lines in this year.',
                            ),
                          ),
                        for (final row in report.rows) _SummaryRow(row: row),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _CardHeader('Detail'),
                        if (report.lines.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                            child: Hint('No tagged lines to list.'),
                          ),
                        for (final line in report.lines) _DetailRow(line: line),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey('business-summary-export'),
                    onPressed: _busy
                        ? null
                        : () => _save(
                            'business-summary-${report.year}.csv',
                            businessSummaryCsv(report),
                          ),
                    child: const Text('Save summary (CSV)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('business-detail-export'),
                    onPressed: _busy
                        ? null
                        : () => _save(
                            'business-detail-${report.year}.csv',
                            businessDetailCsv(report),
                          ),
                    child: const Text('Save detail (CSV)'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    businessReportFooter,
                    key: const ValueKey('business-footer'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Palette.muted,
      ),
    ),
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.row});

  final BusinessSummaryRow row;

  @override
  Widget build(BuildContext context) => Container(
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
              Text(row.tag.name, style: const TextStyle(fontSize: 15)),
              Text(
                '${scheduleCLineText(row.tag.line)} · ${row.tag.rule.label}',
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(row.gross.formatDollars(), style: amountStyle(fontSize: 15)),
            Text(
              'deductible ${row.deductible.formatDollars()}',
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.line});

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
                    line.tag.name,
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
