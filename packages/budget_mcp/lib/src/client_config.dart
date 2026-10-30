import 'dart:convert';

/// `/Applications/Budget.app/Contents/MacOS/budget-mcp`, the binary the DMG
/// ships next to the app (ticket 15).
const bundledMcpCommand = '/Applications/Budget.app/Contents/MacOS/budget-mcp';

/// The block Settings shows to paste into an MCP client's config (ticket 13).
String clientConfig({String command = bundledMcpCommand}) =>
    const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'budget': {'command': command, 'args': <String>[]},
      },
    });
