import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'app_lock_screen.dart';
import 'business_report_screen.dart';
import 'business_tags_screen.dart';
import 'categories_screen.dart';
import 'connect_bank_screen.dart';
import 'encrypted_sync_screen.dart';
import 'export_screen.dart';
import 'forecast_screen.dart';
import 'import_compare_screen.dart';
import 'import_screen.dart';
import 'join_screen.dart';
import 'mcp_screen.dart';
import 'recovery_phrase_screen.dart';
import 'schedules_screen.dart';
import 'settings_desktop.dart';

/// Settings (canvas: Settings). On a phone it is one scrolling list. In the
/// desktop window it is a pane sidebar beside the chosen pane (ticket 66),
/// built from the same rows and screens. A later ticket adds its row to the
/// matching section in [_sections].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.engine,
    required this.services,
    this.onOpenBudget,
    this.onNewBudget,
  });

  final BudgetEngine engine;
  final AppServices services;

  /// Opens another Budget in the desktop window, from the Budgets pane.
  final ValueChanged<String>? onOpenBudget;

  /// Starts a new Budget, from the Budgets pane.
  final VoidCallback? onNewBudget;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  var _syncBook = SyncBook.off;
  var _mcpMode = McpMode.off;

  @override
  void initState() {
    super.initState();
    _readSyncBook();
    _readMcpMode();
  }

  Future<void> _readSyncBook() async {
    final budget = widget.engine.state.budget;
    if (budget == null) return;
    final book = await widget.services.prefs.readSyncBook(budget.id);
    if (mounted) setState(() => _syncBook = book);
  }

  Future<void> _readMcpMode() async {
    final mcp = widget.services.mcp;
    final budget = widget.engine.state.budget;
    if (mcp == null || budget == null) return;
    final book = (await mcp.budget(budget.id))?.book ?? McpBook.off;
    if (mounted) setState(() => _mcpMode = book.mode);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    await _afterOpen();
  }

  /// Opens one of the short flows (ticket 60).
  Future<void> _openFlow(Widget screen) async {
    await openFlow<void>(context, builder: (_) => screen);
    await _afterOpen();
  }

  Future<void> _afterOpen() async {
    // The App lock and Encrypted sync rows' values may have changed.
    await _readSyncBook();
    await _readMcpMode();
    if (mounted) setState(() {});
  }

  /// Opens the phrase screen, which asks for the phone's check before it
  /// spells the key out (ticket 12).
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

  List<SettingsSection> _sections() => [
    SettingsSection(
      title: 'Budget',
      rows: [
        SettingsRow(
          label: 'Name',
          value: widget.engine.state.budget?.name ?? '',
        ),
        SettingsRow(
          label: 'Category priority',
          value: '${widget.engine.state.priority.length} categories',
          onTap: () => _open(CategoriesScreen(engine: widget.engine)),
        ),
        SettingsRow(
          label: 'Scheduled transactions',
          value: '${widget.engine.state.schedules.length} scheduled',
          onTap: () => _open(SchedulesScreen(engine: widget.engine)),
        ),
        SettingsRow(
          label: 'Forecast',
          value: 'Next 12 months',
          onTap: () => _open(ForecastScreen(engine: widget.engine)),
        ),
        SettingsRow(
          label: 'Business tags',
          value: '${widget.engine.state.businessTags.length} tags',
          onTap: () => _open(BusinessTagsScreen(engine: widget.engine)),
        ),
        SettingsRow(
          label: 'Business report',
          value: 'Yearly, CSV',
          onTap: () => _open(
            BusinessReportScreen(
              engine: widget.engine,
              services: widget.services,
            ),
          ),
        ),
      ],
    ),
    SettingsSection(
      title: 'Data',
      rows: [
        SettingsRow(
          label: 'Bank sync',
          value: 'SimpleFIN',
          onTap: () => _openFlow(
            ConnectBankScreen(engine: widget.engine, services: widget.services),
          ),
        ),
        SettingsRow(
          label: 'Export & backup',
          value: 'CSV, JSON, backup',
          onTap: () => _open(
            ExportScreen(engine: widget.engine, services: widget.services),
          ),
        ),
        SettingsRow(
          label: 'App lock',
          value: widget.services.appLockEnabled.value ? 'On' : 'Off',
          onTap: () => _open(AppLockScreen(services: widget.services)),
        ),
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
        SettingsRow(
          label: 'AI apps (MCP)',
          value: _mcpMode.label,
          onTap: () => _open(
            McpScreen(engine: widget.engine, services: widget.services),
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
  ];

  @override
  Widget build(BuildContext context) {
    // Inside the desktop window's content area, Settings is the pane window.
    if (DesktopWindowScope.maybeOf(context) != null) {
      return DesktopSettingsView(
        engine: widget.engine,
        services: widget.services,
        onOpenBudget: widget.onOpenBudget,
        onNewBudget: widget.onNewBudget,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Settings'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  for (final section in _sections()) ...[
                    SettingsCard(section: section),
                    const SizedBox(height: 12),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'No telemetry. Your data stays on your devices.',
                      style: TextStyle(fontSize: 12, color: Palette.muted),
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
