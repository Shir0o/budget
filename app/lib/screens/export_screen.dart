import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Export & backup (canvas: Export). Files are built on the phone and saved
/// where the person chooses.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.engine, required this.services});

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  CivilDate? _lastBackup;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    widget.services.prefs.readLastBackup().then((date) {
      if (mounted) setState(() => _lastBackup = date);
    });
  }

  /// Builds a file, offers it to the person, and says how it went.
  Future<bool> _export(
    String fileName,
    String mimeType,
    Future<Uint8List> Function() build,
  ) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await build();
      final saved = await widget.services.keepUnlocked(
        () => widget.services.saver.save(
          fileName: fileName,
          bytes: bytes,
          mimeType: mimeType,
        ),
      );
      if (saved) {
        messenger.showSnackBar(SnackBar(content: Text('Saved $fileName')));
      }
      return saved;
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save the file')),
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    final budget = widget.engine.state.budget;
    if (budget == null) return;
    final date = today();
    final saved = await _export(
      Backup.fileName(date.toIso()),
      'application/octet-stream',
      () async => Backup.seal(
        widget.engine.events,
        await widget.services.keys.keyFor(budget.id),
      ),
    );
    if (!saved) return;
    await widget.services.prefs.writeLastBackup(date);
    if (mounted) setState(() => _lastBackup = date);
  }

  Future<void> _text(
    String fileName,
    String mimeType,
    String Function(BudgetState) build,
  ) => _export(
    fileName,
    mimeType,
    () async => Uint8List.fromList(utf8.encode(build(widget.engine.state))),
  );

  @override
  Widget build(BuildContext context) {
    final date = today().toIso();
    final lastBackup = _lastBackup;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Export & backup'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Palette.card,
                      border: Border.all(color: Palette.cardBorder),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _ExportRow(
                          title: 'Encrypted backup',
                          hint: 'Full history, sealed with your Budget Key',
                          action: 'Save file',
                          first: true,
                          chipKey: const ValueKey('export-backup'),
                          onTap: _backup,
                        ),
                        _ExportRow(
                          title: 'Transactions (CSV)',
                          hint: 'Every transaction and split line',
                          action: 'Export',
                          chipKey: const ValueKey('export-transactions'),
                          onTap: () => _text(
                            'budget-transactions-$date.csv',
                            'text/csv',
                            transactionsCsv,
                          ),
                        ),
                        _ExportRow(
                          title: 'Monthly assignments (CSV)',
                          hint: 'Plan-style, one row per category and month',
                          action: 'Export',
                          chipKey: const ValueKey('export-assignments'),
                          onTap: () => _text(
                            'budget-assignments-$date.csv',
                            'text/csv',
                            assignmentsCsv,
                          ),
                        ),
                        _ExportRow(
                          title: 'Everything (JSON)',
                          hint: 'Full current state, not encrypted',
                          action: 'Export',
                          chipKey: const ValueKey('export-json'),
                          onTap: () => _text(
                            'budget-$date.json',
                            'application/json',
                            (state) => stateJson(state, month: thisMonth()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const InfoNote(
                    'Files are made on this phone and saved where you choose. '
                    'A plain CSV or JSON file isn’t encrypted, so keep it '
                    'somewhere safe.',
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Hint(
                      lastBackup == null
                          ? 'No backup yet'
                          : 'Last backup: ${formatDate(lastBackup)}',
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
}

class _ExportRow extends StatelessWidget {
  const _ExportRow({
    required this.title,
    required this.hint,
    required this.action,
    required this.onTap,
    required this.chipKey,
    this.first = false,
  });

  final String title;
  final Key chipKey;
  final String hint;
  final String action;
  final VoidCallback onTap;
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 64),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      border: first
          ? null
          : const Border(top: BorderSide(color: Palette.divider)),
    ),
    child: Row(
      spacing: 12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15)),
              Hint(hint),
            ],
          ),
        ),
        _ChipButton(
          key: chipKey,
          label: action,
          semanticLabel: title,
          onTap: onTap,
        ),
      ],
    ),
  );
}

/// An outlined pill, 36 px tall with a 44 px tap target.
class _ChipButton extends StatelessWidget {
  const _ChipButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label: $semanticLabel',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Center(
          widthFactor: 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Palette.card,
              border: Border.all(color: Palette.fieldBorder),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
    ),
  );
}
