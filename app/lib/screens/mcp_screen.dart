import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../budget_library.dart';
import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Settings → AI apps (MCP): Off, Read-only or Read-write for this budget,
/// the copy-paste client config, and the last client that read it
/// (ticket 13). macOS only: [AppServices.mcp] is null elsewhere.
class McpScreen extends StatefulWidget {
  const McpScreen({super.key, required this.engine, required this.services});

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<McpScreen> createState() => _McpScreenState();
}

class _McpScreenState extends State<McpScreen> {
  var _mode = McpMode.off;
  String? _lastUsedBy;
  DateTime? _lastUsedAt;
  var _read = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_read) return;
    _read = true;
    _load();
  }

  /// Registers this device's budgets with the server's registry, then reads
  /// this budget's setting.
  Future<void> _load() async {
    final mcp = widget.services.mcp;
    final budget = widget.engine.state.budget;
    if (mcp == null || budget == null) return;
    await mcp.register([
      for (final entry in BudgetLibraryScope.of(context).entries)
        (id: entry.id, name: entry.name, store: 'budget-${entry.id}.db'),
    ]);
    final book = (await mcp.budget(budget.id))?.book ?? McpBook.off;
    if (!mounted) return;
    setState(() {
      _mode = book.mode;
      _lastUsedBy = book.lastUsedBy;
      _lastUsedAt = book.lastUsedAt;
    });
  }

  Future<void> _setMode(McpMode mode) async {
    final mcp = widget.services.mcp;
    final budget = widget.engine.state.budget;
    if (mcp == null || budget == null) return;
    await mcp.setMode(budget.id, mode);
    if (!mounted) return;
    setState(() => _mode = mode);
  }

  String get _lastUsed => switch ((_lastUsedBy, _lastUsedAt)) {
    (final by?, final at?) =>
      'Last used by $by at ${formatDate(CivilDate.fromDateTime(at))} '
          '${formatTime(at)}',
    (final by?, null) => 'Last used by $by',
    _ => 'No AI app has read this budget yet.',
  };

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: clientConfig()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BackHeader(title: 'AI apps (MCP)'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Text(
                  'Let an AI app read this budget through a local server on '
                  'this Mac. It can’t change anything, delete anything, or '
                  'mark a line Reviewed.',
                  style: TextStyle(fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 16),
                LabeledField(
                  label: 'Access for this budget',
                  child: Segmented<McpMode>(
                    options: const [
                      (McpMode.off, 'Off'),
                      (McpMode.readOnly, 'Read-only'),
                      (McpMode.readWrite, 'Read-write'),
                    ],
                    selected: _mode,
                    onChanged: _setMode,
                  ),
                ),
                const SizedBox(height: 10),
                Hint(_modeExplanation),
                const SizedBox(height: 16),
                if (_mode != McpMode.off) ...[
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: FieldLabel('Client config')),
                            TextButton.icon(
                              key: const ValueKey('mcp-copy'),
                              onPressed: _copy,
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copy'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          clientConfig(),
                          style: const TextStyle(
                            fontFamily: monoFamily,
                            fontSize: 12,
                            height: 1.5,
                            color: Palette.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Hint(
                          'Paste it into your AI app’s MCP config, then '
                          'restart the app.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Hint(_lastUsed),
                  ),
                  const SizedBox(height: 12),
                ],
                InfoNote(
                  _mode == McpMode.off
                      ? 'Off is the default. Nothing leaves this Mac.'
                      : 'The server runs on this Mac only. Every card and '
                            'account number is redacted before a result leaves '
                            'the app, and account names keep at most the last '
                            'four digits.',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  String get _modeExplanation => switch (_mode) {
    McpMode.off => 'Nothing is shared.',
    McpMode.readOnly =>
      'AI apps can read, search and report. They can’t '
          'change anything.',
    McpMode.readWrite =>
      'Read-write shares the same read tools today; write '
          'tools arrive in a later update.',
  };
}
