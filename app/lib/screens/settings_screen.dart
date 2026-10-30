import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
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
import 'mcp_screen.dart';
import 'schedules_screen.dart';

/// Settings (canvas: Settings). It lists only what exists today. A later
/// ticket adds its row to the matching section in [_sections].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.engine,
    required this.services,
  });

  final BudgetEngine engine;
  final AppServices services;

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
    // The App lock and Encrypted sync rows' values may have changed.
    await _readSyncBook();
    await _readMcpMode();
    if (mounted) setState(() {});
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
          onTap: () => _open(
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
        if (widget.services.mcp != null)
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
  Widget build(BuildContext context) => Scaffold(
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
