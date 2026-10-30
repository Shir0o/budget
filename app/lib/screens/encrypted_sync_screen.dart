import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../settings_widgets.dart';
import '../sync.dart';
import '../theme.dart';
import '../widgets.dart';

/// Encrypted sync (canvas: Settings → Encrypted sync). While it is off it
/// offers Turn on sync; once on it shows the devices and syncs by hand.
///
/// Everything it writes goes to Google Drive's hidden app data folder and is
/// sealed with the Budget Key, so Google sees random file names, sizes and
/// timing only (ADR 0002). There is no server of ours.
class EncryptedSyncScreen extends StatefulWidget {
  const EncryptedSyncScreen({
    super.key,
    required this.engine,
    required this.services,
  });

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<EncryptedSyncScreen> createState() => _EncryptedSyncScreenState();
}

class _EncryptedSyncScreenState extends State<EncryptedSyncScreen> {
  var _book = SyncBook.off;
  var _loaded = false;
  var _busy = false;
  var _message = <String>[];
  var _errors = <String>[];
  var _attention = <NeedsAttention>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final budget = widget.engine.state.budget;
    final book = budget == null
        ? SyncBook.off
        : await widget.services.prefs.readSyncBook(budget.id);
    if (!mounted) return;
    setState(() {
      _book = book;
      _loaded = true;
    });
    // Sync on open, as it does when the app starts (ticket 12).
    if (book.enabled) await _sync();
  }

  Future<void> _setEnabled(bool enabled) async {
    final budget = widget.engine.state.budget;
    if (budget == null) return;
    final book = _book.copyWith(enabled: enabled);
    await widget.services.prefs.writeSyncBook(budget.id, book);
    if (!mounted) return;
    setState(() {
      _book = book;
      _message = enabled ? [] : ['Sync is off on this device.'];
      _errors = [];
      _attention = [];
    });
    if (enabled) await _sync();
  }

  Future<void> _sync() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = [];
    });
    final outcome = await syncNow(
      engine: widget.engine,
      services: widget.services,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _book = outcome.book;
      _attention = outcome.needsAttention;
      _errors = [?outcome.error];
      if (outcome.error == null) {
        _message = [
          outcome.pulled == 0 && outcome.pushed == 0
              ? 'Everything is up to date.'
              : '${_events(outcome.pulled)} from ${_from(outcome.others)}, '
                    '${_events(outcome.pushed)} from this one.',
        ];
      }
    });
  }

  static String _events(int count) =>
      count == 1 ? '1 change' : '$count changes';

  /// `the Mac`, `the Android` or `your other devices`.
  static String _from(List<String> others) {
    if (others.isEmpty) return 'your other devices';
    return others.map((platform) => 'the ${_platform(platform)}').join(' and ');
  }

  static String _platform(String platform) => switch (platform) {
    'android' => 'Android',
    'mac' => 'Mac',
    _ => 'other device',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BackHeader(title: 'Encrypted sync'),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      if (_errors.isNotEmpty) ...[
                        _Banner(
                          key: const ValueKey('sync-errors'),
                          icon: Icons.error_outline,
                          background: Palette.problemPill,
                          foreground: Palette.problemText,
                          lines: _errors,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_book.enabled && _attention.isNotEmpty) ...[
                        _Banner(
                          key: const ValueKey('sync-attention'),
                          icon: Icons.report_outlined,
                          background: Palette.problemPill,
                          foreground: Palette.problemText,
                          lines: [
                            'Sync left something to check in Review:',
                            for (final item in _attention) item.message,
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_book.enabled) _on() else _off(),
                      if (_message.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _Banner(
                          key: const ValueKey('sync-message'),
                          icon: Icons.info_outline,
                          background: Palette.summary,
                          foreground: Palette.inkSoft,
                          lines: _message,
                        ),
                      ],
                      const SizedBox(height: 12),
                      const InfoNote(
                        'Google sees random file names, sizes and timing, '
                        'never a payee, an amount or a Category. The Budget '
                        'Key stays on your devices; no server of ours is '
                        'involved.',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );

  Widget _off() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      CardBox(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            const Text(
              'Turn on sync',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Text(
              'Your budget syncs between your own devices through Google '
              'Drive’s hidden app folder. Every file is sealed with this '
              'budget’s Budget Key before it leaves the device, so it works '
              'offline and catches up later.',
              style: TextStyle(
                fontSize: 14,
                color: Palette.inkSoft,
                height: 1.45,
              ),
            ),
            FilledButton(
              key: const ValueKey('turn-on-sync'),
              onPressed: _busy ? null : () => _setEnabled(true),
              child: Text(_busy ? 'Turning on…' : 'Turn on sync'),
            ),
          ],
        ),
      ),
      const InfoNote(
        'Sync is off by default. If you lose every device and the recovery '
        'phrase, the copy in Drive can’t be read again. That is deliberate: '
        'nobody else holds the key.',
      ),
    ],
  );

  Widget _on() {
    final lastSync = _book.lastSync;
    final rows = [
      SettingsRow(label: 'Status', value: 'On'),
      SettingsRow(
        label: 'Devices',
        value: _book.devices <= 1
            ? 'This device only'
            : '${_book.devices} devices',
      ),
      SettingsRow(
        label: 'Last sync',
        value: lastSync == null
            ? 'Not yet'
            : '${formatDate(CivilDate.fromDateTime(lastSync))}, '
                  '${formatTime(lastSync)}',
      ),
      SettingsRow(
        label: 'Budget',
        value: widget.engine.state.budget?.name ?? '',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        SettingsCard(
          section: SettingsSection(title: 'Sync', rows: rows),
        ),
        CardBox(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              FilledButton(
                key: const ValueKey('sync-now'),
                onPressed: _busy ? null : _sync,
                child: Text(_busy ? 'Syncing…' : 'Sync now'),
              ),
              OutlinedButton(
                key: const ValueKey('turn-off-sync'),
                onPressed: _busy ? null : () => _confirmOff(),
                child: const Text('Turn off sync'),
              ),
              const Hint(
                'Turning sync off stops this device. Nothing is removed from '
                'the budget or from Drive.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmOff() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off sync?'),
        content: const Text(
          'This device stops syncing. Nothing is removed from the budget, '
          'and the other device keeps its copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _setEnabled(false);
  }
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
