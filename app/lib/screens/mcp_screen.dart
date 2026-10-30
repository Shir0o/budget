import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../budget_library.dart';
import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'history_screen.dart';

/// Settings → AI apps (MCP): Off, Read-only or Read-write for this budget,
/// the copy-paste client config, the last client that used it, and a link to
/// what AI apps changed (ticket 13). The server is macOS only, so on a phone
/// this is the status screen: [AppServices.mcp] is null there.
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
  McpActivity? _activity;
  var _read = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_read) return;
    _read = true;
    _load();
  }

  /// Registers this device's budgets with the server's registry, then reads
  /// this budget's setting and the newest MCP change in its log.
  Future<void> _load() async {
    final mcp = widget.services.mcp;
    final budget = widget.engine.state.budget;
    if (budget != null && mcp != null) {
      await mcp.register([
        for (final entry in BudgetLibraryScope.of(context).entries)
          (id: entry.id, name: entry.name, store: 'budget-${entry.id}.db'),
      ], deviceId: widget.engine.deviceId);
    }
    final book = budget == null || mcp == null
        ? McpBook.off
        : (await mcp.budget(budget.id))?.book ?? McpBook.off;
    final activity = McpActivity.latest(widget.engine.events);
    if (!mounted) return;
    setState(() {
      _mode = book.mode;
      _lastUsedBy = book.lastUsedBy;
      _lastUsedAt = book.lastUsedAt;
      _activity = activity;
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

  /// Opens Change History on the MCP Actor, where each tool call is one
  /// revertable group.
  void _openHistory() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          HistoryScreen(engine: widget.engine, actor: ActorKind.mcp),
    ),
  );

  /// The device's last-used line, or on a phone the newest MCP change that
  /// synced here.
  String get _lastUsed => switch ((widget.services.mcp, _activity)) {
    (null, final activity?) =>
      'Last change by ${activity.client.name} at '
          '${formatDate(CivilDate.fromDateTime(activity.time))} '
          '${formatTime(activity.time)}',
    (null, null) => 'No AI app has changed this budget yet.',
    (_, _) => switch ((_lastUsedBy, _lastUsedAt)) {
      (final by?, final at?) =>
        'Last used by $by at ${formatDate(CivilDate.fromDateTime(at))} '
            '${formatTime(at)}',
      (final by?, null) => 'Last used by $by',
      _ => 'No AI app has read this budget yet.',
    },
  };

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: clientConfig()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final onThisMac = widget.services.mcp != null;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'AI apps (MCP)'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    onThisMac
                        ? 'Let an AI app read this budget and, in Read-write, '
                              'add and change transactions and Assignments '
                              'through a local server on this Mac. It can’t '
                              'delete anything or mark a line Reviewed.'
                        : 'AI apps reach this budget only through the local '
                              'server on a Mac. This screen shows their access '
                              'and what they changed.',
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  LabeledField(
                    label: 'Access for this budget',
                    child: onThisMac
                        ? Segmented<McpMode>(
                            options: const [
                              (McpMode.off, 'Off'),
                              (McpMode.readOnly, 'Read-only'),
                              (McpMode.readWrite, 'Read-write'),
                            ],
                            selected: _mode,
                            onChanged: _setMode,
                          )
                        : Text(
                            McpMode.off.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Hint(_modeExplanation),
                  const SizedBox(height: 16),
                  if (onThisMac && _mode != McpMode.off) ...[
                    CardBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: FieldLabel('Client config'),
                              ),
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
                  ],
                  if (!onThisMac || _mode != McpMode.off) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Hint(_lastUsed),
                    ),
                    const SizedBox(height: 12),
                  ],
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: FieldLabel('MCP changes')),
                            TextButton.icon(
                              key: const ValueKey('mcp-history'),
                              onPressed: _openHistory,
                              icon: const Icon(Icons.history, size: 16),
                              label: const Text('Change History'),
                            ),
                          ],
                        ),
                        if (_activity case final activity?) ...[
                          const SizedBox(height: 4),
                          Hint('${activity.summary} · ${activity.client.name}'),
                        ] else ...[
                          const SizedBox(height: 4),
                          const Hint('No AI app has changed this budget yet.'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InfoNote(
                    !onThisMac
                        ? 'The server runs on a Mac only. Every card and '
                              'account number is redacted before a result '
                              'leaves it, and account names keep at most the '
                              'last four digits.'
                        : _mode == McpMode.off
                        ? 'Off is the default. Nothing leaves this Mac.'
                        : 'The server runs on this Mac only. Every card and '
                              'account number is redacted before a result '
                              'leaves the app, and account names keep at most '
                              'the last four digits.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _modeExplanation {
    if (widget.services.mcp == null) {
      return 'AI apps connect through the Mac app, where Off, Read-only or '
          'Read-write is chosen per budget. This device runs no server.';
    }
    return switch (_mode) {
      McpMode.off => 'Nothing is shared.',
      McpMode.readOnly =>
        'AI apps can read, search and report. They can’t change anything.',
      McpMode.readWrite =>
        'AI apps can read and change this budget. Nothing is deleted, and '
            'only you mark a line Reviewed.',
    };
  }
}
