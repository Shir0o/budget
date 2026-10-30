import 'dart:async';

import 'package:dart_mcp/server.dart';

import 'tools.dart';

/// The `budget-mcp` server: ticket 13's read and write tools over stdio. The
/// mode gate, redaction and the one group per call live in [BudgetTools], so
/// the protocol layer only forwards calls.
final class BudgetMcpServer extends MCPServer with ToolsSupport {
  BudgetMcpServer(super.channel, {required this.tools})
    : super.fromStreamChannel(
        implementation: Implementation(name: 'budget-mcp', version: '1.0.0'),
        instructions: _instructions,
      ) {
    for (final spec in [...BudgetTools.specs, ...BudgetTools.writeSpecs]) {
      registerTool(
        Tool(
          name: spec.name,
          description: spec.description,
          inputSchema: ObjectSchema.fromMap(spec.inputSchema),
          annotations: ToolAnnotations(
            readOnlyHint: !spec.writes,
            // A write tool only adds or edits; nothing is deleted.
            destructiveHint: false,
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
      client: McpClient(ready ? clientInfo.name : ''),
    );
    return CallToolResult(
      content: [TextContent(text: result.text)],
      isError: result.isError ? true : null,
    );
  }
}

const _instructions =
    'Access to one local budget, as far as Settings allows: Off, Read-only or '
    'Read-write. Every string is redacted: card and account numbers never '
    'leave the device, and account names carry at most a last-4 suffix. '
    'Nothing here deletes anything or marks a line Reviewed; a person does '
    'both in the app. Each write is one Event group with actor mcp:<client>, '
    'revertable with revert_change or from Change History.';
