import 'dart:io';

import 'package:budget_mcp/app_store.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:dart_mcp/stdio.dart';

/// `budget-mcp`: ticket 13's read tools over stdio, launched by an MCP
/// client. It reads the budgets Settings registered in the app's support
/// folder; `--data-dir <path>` points it somewhere else.
void main(List<String> arguments) {
  final directory = switch (arguments.indexOf('--data-dir')) {
    -1 => appSupportDirectory,
    final index when index + 1 < arguments.length => arguments[index + 1],
    _ => null,
  };
  if (directory == null) {
    stderr.writeln('budget-mcp: --data-dir needs a path.');
    exitCode = 64;
    return;
  }
  BudgetMcpServer(
    stdioChannel(input: stdin, output: stdout),
    tools: BudgetTools(
      store: FileMcpStore(directory),
      events: AppEventSource(directory: directory),
    ),
  );
}
