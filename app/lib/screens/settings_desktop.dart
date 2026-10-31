import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';

import '../budget_library.dart';
import '../flows.dart';
import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'app_lock_screen.dart';
import 'business_tags_screen.dart';
import 'connect_bank_screen.dart';
import 'encrypted_sync_screen.dart';
import 'export_screen.dart';
import 'import_compare_screen.dart';
import 'import_screen.dart';
import 'join_screen.dart';
import 'mcp_screen.dart';
import 'pair_device_screen.dart';
import 'recovery_phrase_screen.dart';
import 'redact_screen.dart';

/// One pane of the desktop Settings window (ticket 66). The labels follow the
/// macOS mock-up, and each pane opens the existing settings screen it names.
enum SettingsPane {
  budgets('Budgets', Icons.account_balance_wallet_outlined),
  bank('Bank connection', Icons.account_balance_outlined),
  sync('Encrypted sync', Icons.cloud_outlined),
  devices('Devices and recovery phrase', Icons.devices_outlined),
  businessTags('Business Tags', Icons.sell_outlined),
  importExport('Import and export', Icons.import_export),
  aiApps('AI apps', Icons.smart_toy_outlined),
  appLock('App lock', Icons.lock_outline),
  redact('Redact a value', Icons.visibility_off_outlined);

  const SettingsPane(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Settings on a Mac: a pane sidebar beside the chosen pane, in place of the
/// phone's single scrolling list. Every pane reads the same settings screens
/// and flows the phone uses, so the two layouts can't drift apart.
class DesktopSettingsView extends StatefulWidget {
  const DesktopSettingsView({
    super.key,
    required this.engine,
    required this.services,
    this.onOpenBudget,
    this.onNewBudget,
  });

  final BudgetEngine engine;
  final AppServices services;

  /// Opens another Budget in the window, from the Budgets pane.
  final ValueChanged<String>? onOpenBudget;

  /// Starts a new Budget through the Welcome flow, from the Budgets pane.
  final VoidCallback? onNewBudget;

  @override
  State<DesktopSettingsView> createState() => _DesktopSettingsViewState();
}

class _DesktopSettingsViewState extends State<DesktopSettingsView> {
  var _pane = SettingsPane.budgets;
  var _syncBook = SyncBook.off;
  var _bankBook = const SimpleFinBook();
  var _mcpMode = McpMode.off;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final budget = widget.engine.state.budget;
    final bank = await widget.services.prefs.readSimpleFinBook();
    final sync = budget == null
        ? SyncBook.off
        : await widget.services.prefs.readSyncBook(budget.id);
    final mcp = widget.services.mcp;
    final mode = budget == null || mcp == null
        ? McpMode.off
        : (await mcp.budget(budget.id))?.book.mode ?? McpMode.off;
    if (!mounted) return;
    setState(() {
      _bankBook = bank;
      _syncBook = sync;
      _mcpMode = mode;
      _loaded = true;
    });
  }

  /// Opens an existing settings screen as a desktop sheet, then rereads the
  /// values the panes show.
  Future<void> _open(Widget screen) async {
    await openFlow<void>(context, builder: (_) => screen);
    await _load();
  }

  void _newBudget() {
    final callback = widget.onNewBudget;
    if (callback == null) return;
    // Welcome fills the window, so Settings goes away first.
    Navigator.of(context).pop();
    callback();
  }

  Future<void> _openPhrase() async {
    final budget = widget.engine.state.budget;
    if (budget == null) return;
    final key = await widget.services.keys.existingKey(budget.id);
    if (!mounted) return;
    if (key == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No recovery phrase yet. Turn on Encrypted sync to create one.',
          ),
        ),
      );
      return;
    }
    await _open(
      RecoveryPhraseScreen(services: widget.services, budgetKey: key),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaneSidebar(
            pane: _pane,
            onChoose: (pane) => setState(() => _pane = pane),
          ),
          const VerticalDivider(width: 1, color: Palette.cardBorder),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    key: const ValueKey('settings-pane-content'),
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 12,
                            children: [
                              Text(
                                _pane.label,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              ..._content(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _content() => switch (_pane) {
    SettingsPane.budgets => _budgets(),
    SettingsPane.bank => _bank(),
    SettingsPane.sync => _sync(),
    SettingsPane.devices => _devices(),
    SettingsPane.businessTags => _businessTags(),
    SettingsPane.importExport => _importExport(),
    SettingsPane.aiApps => _aiApps(),
    SettingsPane.appLock => _appLock(),
    SettingsPane.redact => _redact(),
  };

  List<Widget> _budgets() {
    final entries = BudgetLibraryScope.of(context).entries;
    final onOpen = widget.onOpenBudget;
    return [
      SettingsCard(
        section: SettingsSection(
          title: 'Budgets',
          rows: [
            for (final entry in entries)
              SettingsRow(
                label: entry.name,
                value: entry.isOpen ? 'Current' : 'Open',
                onTap: entry.isOpen || onOpen == null
                    ? null
                    : () => onOpen(entry.id),
              ),
          ],
        ),
      ),
      if (widget.onNewBudget != null)
        FilledButton(
          key: const ValueKey('settings-new-budget'),
          onPressed: _newBudget,
          child: const Text('New budget'),
        ),
      const Hint('Each budget has its own accounts, key and sync.'),
    ];
  }

  List<Widget> _bank() {
    final book = _bankBook;
    final problems = [
      for (final error in book.errors) error.message,
      if (book.automaticPaused)
        'SimpleFIN refused the access URL, so automatic fetches are paused.',
    ];
    return [
      if (problems.isNotEmpty)
        _ProblemCard(
          key: const ValueKey('settings-bank-problem'),
          lines: problems,
          onFix: _openBank,
        ),
      SettingsCard(
        section: SettingsSection(
          title: 'SimpleFIN Bridge',
          rows: [
            SettingsRow(
              label: 'Status',
              value: book.connected ? 'Connected' : 'Not connected',
            ),
            if (book.connected) ...[
              SettingsRow(
                label: 'Linked accounts',
                value: book.linkedAccounts.isEmpty
                    ? 'None yet'
                    : '${book.linkedAccounts.length} of '
                          '${book.links.length} linked',
              ),
              SettingsRow(
                label: 'Last fetch',
                value: book.lastFetch == null
                    ? 'Never'
                    : formatDate(book.lastFetch!),
              ),
              SettingsRow(
                label: 'Automatic fetch',
                value: book.automaticPaused
                    ? 'Paused until you re-link'
                    : 'Every 6 hours, at most',
              ),
            ],
          ],
        ),
      ),
      SettingsCard(
        section: SettingsSection(
          title: 'Connection',
          rows: [
            SettingsRow(
              label: 'Connect bank',
              value: book.connected ? 'Re-link' : 'SimpleFIN',
              onTap: _openBank,
            ),
          ],
        ),
      ),
      const Hint(
        'The access URL is kept in this Mac’s secure storage only. It is '
        'never written to the budget, your other devices, or the Event log.',
      ),
    ];
  }

  List<Widget> _sync() {
    final last = _syncBook.lastSync;
    return [
      SettingsCard(
        section: SettingsSection(
          title: 'Sync',
          rows: [
            SettingsRow(
              label: 'Status',
              value: _syncBook.enabled ? 'On' : 'Off',
            ),
            SettingsRow(
              label: 'Devices',
              value: _syncBook.devices <= 1
                  ? 'This device only'
                  : '${_syncBook.devices} devices',
            ),
            SettingsRow(
              label: 'Last sync',
              value: last == null
                  ? 'Not yet'
                  : '${formatDate(CivilDate.fromDateTime(last))}, '
                        '${formatTime(last)}',
            ),
          ],
        ),
      ),
      SettingsCard(
        section: SettingsSection(
          title: 'Encrypted sync',
          rows: [
            SettingsRow(
              label: 'Encrypted sync',
              value: _syncBook.enabled ? 'On' : 'Off',
              onTap: () => _open(
                EncryptedSyncScreen(
                  engine: widget.engine,
                  services: widget.services,
                ),
              ),
            ),
          ],
        ),
      ),
      const Hint(
        'Everything synced is sealed with this budget’s Budget Key before it '
        'leaves the device.',
      ),
    ];
  }

  List<Widget> _devices() => [
    SettingsCard(
      section: SettingsSection(
        title: 'Devices',
        rows: [
          SettingsRow(label: 'Sync', value: _syncBook.enabled ? 'On' : 'Off'),
          SettingsRow(
            label: 'Devices with the Budget Key',
            value: _syncBook.devices <= 1
                ? 'This device only'
                : '${_syncBook.devices} devices',
          ),
        ],
      ),
    ),
    SettingsCard(
      section: SettingsSection(
        title: 'Pairing and recovery',
        rows: [
          SettingsRow(
            label: 'Pair a device',
            value: 'QR code',
            onTap: () => _open(
              PairDeviceScreen(
                engine: widget.engine,
                services: widget.services,
              ),
            ),
          ),
          SettingsRow(
            label: 'Recovery phrase',
            value: '24 words',
            onTap: _openPhrase,
          ),
          SettingsRow(
            label: 'Join a device’s budget',
            value: 'Pairing code',
            onTap: () => _open(JoinScreen(services: widget.services)),
          ),
        ],
      ),
    ),
    const Hint(
      'The Budget Key moves between devices only by QR code or recovery '
      'phrase. Rotate it from Encrypted sync if a device is lost.',
    ),
  ];

  List<Widget> _businessTags() => [
    SettingsCard(
      section: SettingsSection(
        title: 'Business',
        rows: [
          SettingsRow(
            label: 'Business tags',
            value: '${widget.engine.state.businessTags.length} tags',
            onTap: () => _open(BusinessTagsScreen(engine: widget.engine)),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _importExport() => [
    SettingsCard(
      section: SettingsSection(
        title: 'Data',
        rows: [
          SettingsRow(
            label: 'Export & backup',
            value: 'CSV, JSON, backup',
            onTap: () => _open(
              ExportScreen(engine: widget.engine, services: widget.services),
            ),
          ),
          SettingsRow(
            label: 'Import from Actual',
            onTap: () => _open(
              ImportActualScreen(
                engine: widget.engine,
                services: widget.services,
              ),
            ),
          ),
          SettingsRow(
            label: 'Import & compare',
            onTap: () => _open(
              ImportCompareScreen(
                engine: widget.engine,
                services: widget.services,
              ),
            ),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _aiApps() => [
    SettingsCard(
      section: SettingsSection(
        title: 'AI apps',
        rows: [
          SettingsRow(
            label: 'AI apps (MCP)',
            value: _mcpMode.label,
            onTap: () => _open(
              McpScreen(engine: widget.engine, services: widget.services),
            ),
          ),
        ],
      ),
    ),
    const Hint(
      'AI apps never delete anything, never mark a line Reviewed, and see '
      'card numbers redacted.',
    ),
  ];

  List<Widget> _appLock() => [
    SettingsCard(
      section: SettingsSection(
        title: 'Privacy',
        rows: [
          SettingsRow(
            label: 'App lock',
            value: widget.services.appLockEnabled.value ? 'On' : 'Off',
            onTap: () => _open(AppLockScreen(services: widget.services)),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _redact() {
    final rows = _redactions();
    return [
      const Hint(
        'Use this for a card or account number that got stored by mistake. '
        'The value becomes [redacted] everywhere it appears, on this device '
        'and the others. It can’t be undone.',
      ),
      if (rows.isEmpty)
        const Hint('Nothing here can be redacted.')
      else
        SettingsCard(
          section: SettingsSection(
            title: 'Values',
            rows: [
              for (final row in rows)
                SettingsRow(
                  label: row.label,
                  value: row.value,
                  onTap: () => _open(
                    RedactScreen(
                      engine: widget.engine,
                      entity: row.target.entity,
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  /// Every field in the budget that holds something a person may want gone.
  List<({String label, RedactTarget target, String value})> _redactions() {
    final state = widget.engine.state;
    final rows = <({String label, RedactTarget target, String value})>[];
    void add(String owner, List<RedactCandidate> candidates) {
      for (final candidate in candidates) {
        rows.add((
          label: '$owner · ${candidate.label}',
          target: candidate.target,
          value: candidate.value,
        ));
      }
    }

    for (final account in state.accounts) {
      add(account.name, redactCandidates(state, EntityRef.account(account.id)));
    }
    for (final category in state.categories) {
      add(
        category.name,
        redactCandidates(state, EntityRef.category(category.id)),
      );
    }
    for (final group in state.categoryGroups) {
      add(
        group.name,
        redactCandidates(state, EntityRef(EntityKind.categoryGroup, group.id)),
      );
    }
    for (final transaction in state.transactions) {
      add(
        transaction.payee,
        redactCandidates(state, EntityRef.transaction(transaction.id)),
      );
    }
    for (final schedule in state.schedules) {
      add(
        schedule.payee,
        redactCandidates(state, EntityRef.schedule(schedule.id)),
      );
    }
    return rows;
  }

  Future<void> _openBank() => _open(
    ConnectBankScreen(engine: widget.engine, services: widget.services),
  );
}

/// The pane list on the left of the Settings window.
class _PaneSidebar extends StatelessWidget {
  const _PaneSidebar({required this.pane, required this.onChoose});

  final SettingsPane pane;
  final ValueChanged<SettingsPane> onChoose;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('settings-panes'),
    width: 240,
    color: Palette.card,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
          child: Row(
            spacing: 2,
            children: [
              // A section in the desktop window's content area has nothing to
              // pop; Settings does.
              if (Navigator.canPop(context))
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back',
                  icon: const Icon(Icons.chevron_left, size: 20),
                  color: Palette.ink,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
              const Expanded(
                child: Text(
                  'Settings',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
            children: [
              for (final item in SettingsPane.values)
                Semantics(
                  button: true,
                  selected: item == pane,
                  child: InkWell(
                    key: ValueKey('settings-pane-${item.label}'),
                    onTap: () => onChoose(item),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: item == pane ? Palette.summary : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        spacing: 10,
                        children: [
                          Icon(item.icon, size: 18, color: Palette.inkSoft),
                          Expanded(
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: item == pane
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
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
}

/// A bank error or paused fetch, as a problem card with a way to fix it.
class _ProblemCard extends StatelessWidget {
  const _ProblemCard({super.key, required this.lines, required this.onFix});

  final List<String> lines;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
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
            Icons.error_outline,
            size: 18,
            color: Palette.problemText,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              for (final line in lines)
                Text(
                  line,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Palette.problemText,
                    height: 1.4,
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onFix,
                  style: TextButton.styleFrom(
                    foregroundColor: Palette.problemText,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text('Fix'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
