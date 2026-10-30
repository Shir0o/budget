import 'package:budget_core/budget_core.dart';

import 'tools.dart';

/// The newest MCP change in a budget's log (ticket 13): which AI app wrote
/// it, when, and the group Change History lists. The AI apps screen reads it
/// on a device that runs no MCP server, where Settings holds no last-used
/// line.
final class McpActivity {
  const McpActivity({
    required this.client,
    required this.time,
    required this.groupId,
    required this.summary,
  });

  /// The newest group an AI app wrote, or null when none has.
  static McpActivity? latest(Iterable<Event> events) {
    final entries = ChangeHistory.of(events)
        .entries(filter: const HistoryFilter(actors: {ActorKind.mcp}));
    for (final entry in entries) {
      // A revert MCP asked for reads as MCP's too.
      final name = entry.actor.mcpClient ?? entry.by?.mcpClient;
      if (name == null) continue;
      return McpActivity(
        client: McpClient(name),
        time: entry.time,
        groupId: entry.groupId,
        summary: entry.summary,
      );
    }
    return null;
  }

  final McpClient client;

  /// Local wall time of the group's first Event.
  final DateTime time;

  /// The group `revert_change` takes, and Change History lists.
  final String groupId;
  final String summary;
}
