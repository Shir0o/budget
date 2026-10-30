import 'dart:async';

import 'package:dart_mcp/server.dart';

import 'tools.dart';

/// The `budget-mcp` server: ticket 13's read tools over stdio. The mode gate
/// and redaction live in [BudgetTools], so the protocol layer only forwards
/// calls.
final class BudgetMcpServer extends MCPServer with ToolsSupport {
  BudgetMcpServer(super.channel, {required this.tools})
    : super.fromStreamChannel(
        implementation: Implementation(name: 'budget-mcp', version: '1.0.0'),
        instructions: _instructions,
      ) {
    for (final spec in BudgetTools.specs) {
      registerTool(
        Tool(
          name: spec.name,
          description: spec.description,
          inputSchema: ObjectSchema.fromMap(spec.inputSchema),
          annotations: ToolAnnotations(
            readOnlyHint: true,
            openWorldHint: false,
          ),
        ),
        (request) => _call(spec.name, request),
      );
    }
  }

  final BudgetTools tools;

  Future<CallToolResult> _call(String name, CallToolRequest request) async {
    final result = await tools.call(
      ToolRequest(name, request.arguments ?? const {}),
      client: ready ? clientInfo.name : 'unknown',
    );
    return CallToolResult(
      content: [TextContent(text: result.text)],
      isError: result.isError ? true : null,
    );
  }
}

const _instructions =
    'Read-only access to one local budget. Every string is redacted: card '
    'and account numbers never leave the device, and account names carry at '
    'most a last-4 suffix. Nothing here marks a line Reviewed or deletes '
    'anything; a person does both in the app.';
