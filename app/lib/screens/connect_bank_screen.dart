import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:flutter/material.dart';

import '../bank_sync.dart';
import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'link_accounts_screen.dart';

/// Connect bank (canvas: Settings → Bank sync). It claims a setup token,
/// keeps the access URL in secure storage, and fetches by hand inside the
/// daily budget (ticket 10). Link accounts picks which app account each
/// bank account feeds.
class ConnectBankScreen extends StatefulWidget {
  const ConnectBankScreen({
    super.key,
    required this.engine,
    required this.services,
  });

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<ConnectBankScreen> createState() => _ConnectBankScreenState();
}

class _ConnectBankScreenState extends State<ConnectBankScreen> {
  final _token = TextEditingController();
  var _book = const SimpleFinBook();
  var _loaded = false;
  var _busy = false;
  var _message = <String>[];
  var _errors = <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final book = await widget.services.prefs.readSimpleFinBook();
    await syncBankSchedule(widget.services.scheduler, book);
    if (!mounted) return;
    setState(() {
      _book = book;
      _errors = [for (final error in book.errors) error.message];
      _loaded = true;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = [];
    });
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      setState(
        () => _message = ['Paste the setup token you copied from SimpleFIN.'],
      );
      return;
    }
    try {
      final access = await widget.services.simpleFin.claim(token);
      final book = _book.withAccess(access.value);
      await widget.services.prefs.writeSimpleFinBook(book);
      if (!mounted) return;
      _token.clear();
      setState(() => _book = book);
      // Re-linking keeps the links that are already made; only a first
      // connection needs Link accounts opened for it.
      await _fetch(openLinks: book.links.isEmpty);
    } on SimpleFinException catch (error) {
      if (mounted) setState(() => _message = [error.message]);
    } on Exception {
      if (mounted) {
        setState(() => _message = ['Couldn’t reach SimpleFIN. Try again.']);
      }
    }
  });

  /// Runs one hand fetch and shows what it did. [openLinks] opens Link
  /// accounts with the accounts the bridge just returned.
  Future<void> _fetch({bool openLinks = false}) async {
    final outcome = await fetchByHand(
      engine: widget.engine,
      client: widget.services.simpleFin,
      book: _book,
      today: today(),
      save: widget.services.prefs.writeSimpleFinBook,
    );
    if (!mounted) return;
    setState(() {
      _book = outcome.book;
      _message = [?outcome.message];
      _errors = outcome.errors;
    });
    await syncBankSchedule(widget.services.scheduler, outcome.book);
    if (openLinks && outcome.accounts.isNotEmpty) {
      await _openLinks(outcome.accounts);
    }
  }

  Future<void> _openLinks(List<ClaimedAccount> accounts) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinkAccountsScreen(
          engine: widget.engine,
          services: widget.services,
          book: _book,
          accounts: accounts,
          today: today(),
        ),
      ),
    );
    if (!mounted) return;
    final book = await widget.services.prefs.readSimpleFinBook();
    if (!mounted) return;
    setState(() => _book = book);
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect bank?'),
        content: const Text(
          'The access URL and the account links are removed from this '
          'device. Transactions already imported stay in the budget.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.services.prefs.writeSimpleFinBook(const SimpleFinBook());
      await syncBankSchedule(widget.services.scheduler, const SimpleFinBook());
      if (!mounted) return;
      setState(() {
        _book = const SimpleFinBook();
        _errors = const [];
        _message = ['Disconnected. Imported transactions stay in the budget.'];
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BackHeader(title: 'Bank sync'),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      if (_errors.isNotEmpty) ...[
                        _Banner(
                          key: const ValueKey('bank-sync-errors'),
                          icon: Icons.error_outline,
                          background: Palette.problemPill,
                          foreground: Palette.problemText,
                          lines: _errors,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_book.connected) _connected() else _connectForm(),
                      if (_book.connected && _book.automaticPaused) ...[
                        const SizedBox(height: 12),
                        _Banner(
                          key: const ValueKey('bank-sync-paused'),
                          icon: Icons.link_off,
                          background: Palette.problemPill,
                          foreground: Palette.problemText,
                          lines: const [
                            'SimpleFIN refused the access URL, so automatic '
                                'fetches are paused. Re-link your bank to '
                                'start them again.',
                          ],
                        ),
                        const SizedBox(height: 12),
                        _connectForm(relink: true),
                      ],
                      if (_message.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _Banner(
                          key: const ValueKey('bank-sync-message'),
                          icon: Icons.info_outline,
                          background: Palette.summary,
                          foreground: Palette.inkSoft,
                          lines: _message,
                        ),
                      ],
                      const SizedBox(height: 12),
                      const InfoNote(
                        'The access URL is kept in this phone’s secure '
                        'storage only. It is never written to the budget, to '
                        'your other devices, or to the Event log.',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );

  Widget _connectForm({bool relink = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      Hint(
        relink
            ? 'Paste a new setup token from SimpleFIN. Your account links '
                  'and the transactions already imported stay as they are.'
            : 'SimpleFIN Bridge reads your bank for you. At '
                  'beta-bridge.simplefin.org, connect a bank and copy its '
                  'setup token. A token can be claimed once.',
      ),
      CardBox(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            LabeledField(
              label: 'Setup token',
              child: TextField(
                key: const ValueKey('setup-token'),
                controller: _token,
                minLines: 3,
                maxLines: 5,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: monoFamily, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Paste the setup token',
                ),
              ),
            ),
            FilledButton(
              key: const ValueKey('connect-bank'),
              onPressed: _busy ? null : _connect,
              child: Text(
                _busy
                    ? 'Connecting…'
                    : relink
                    ? 'Re-link bank'
                    : 'Connect bank',
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _connected() {
    final state = widget.engine.state;
    final remaining = _book.requests.remaining(today());
    final linked = _book.linkedAccounts.length;
    final rows = [
      ('Status', 'Connected'),
      (
        'Linked accounts',
        linked == 0 ? 'None yet' : '$linked of ${_book.links.length} linked',
      ),
      ('Fetches left today', '$remaining of ${RequestCount.dailyLimit}'),
      (
        'Automatic fetch',
        _book.automaticPaused
            ? 'Paused until you re-link'
            : 'Every 6 hours, at most',
      ),
      (
        'Last fetch',
        _book.lastFetch == null ? 'Never' : formatDate(_book.lastFetch!),
      ),
      ('Budget', state.budget?.name ?? ''),
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
                key: const ValueKey('fetch-now'),
                onPressed: _busy || remaining == 0 ? null : () => _run(_fetch),
                child: Text(_busy ? 'Fetching…' : 'Fetch now'),
              ),
              OutlinedButton(
                key: const ValueKey('link-accounts'),
                onPressed: _busy
                    ? null
                    : () => _run(() => _fetch(openLinks: true)),
                child: const Text('Link accounts'),
              ),
              OutlinedButton(
                key: const ValueKey('disconnect-bank'),
                onPressed: _busy ? null : _disconnect,
                child: const Text('Disconnect'),
              ),
              if (remaining == 0)
                const Hint(
                  'The daily cap keeps SimpleFIN Bridge’s own limit '
                  'untouched. Fetches start again tomorrow.',
                ),
            ],
          ),
        ),
      ],
    );
  }
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
        Text(label, style: const TextStyle(fontSize: 15)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Palette.muted),
          ),
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
