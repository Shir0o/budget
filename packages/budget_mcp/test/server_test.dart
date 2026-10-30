import 'dart:async';

import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:dart_mcp/client.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// A synthetic budget and a server over a loopback channel, so the stdio
/// protocol is exercised without touching the database.
Future<(ServerConnection, InMemoryMcpStore, String)> _connect() async {
  final log = InMemoryEventLog();
  final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  engine.execute(const CreateBudget(name: 'Home'));
  final id = engine.state.budget!.id;
  final store = InMemoryMcpStore([
    McpBudget(
      id: id,
      name: 'Home',
      store: 'budget-$id.db',
      book: const McpBook(mode: McpMode.readOnly),
    ),
  ]);
  final controller = StreamChannelController<String>(sync: true);
  BudgetMcpServer(
    controller.local,
    tools: BudgetTools(
      store: store,
      events: InMemoryEventSource({id: engine.events}),
      writes: InMemoryBudgetWrites({id: log}),
      now: () => DateTime(2026, 11, 20, 10, 30),
    ),
  );
  final client = MCPClient(
    Implementation(name: 'Test client', version: '1.0.0'),
  );
  final connection = client.connectServer(controller.foreign);
  await connection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: ClientCapabilities(),
      clientInfo: Implementation(name: 'Test client', version: '1.0.0'),
    ),
  );
  connection.notifyInitialized();
  return (connection, store, id);
}

void main() {
  test('lists the read and write tools and calls one', () async {
    final (connection, store, id) = await _connect();

    final listed = await connection.listTools();
    expect(listed.tools.map((tool) => tool.name), [
      for (final spec in BudgetTools.specs) spec.name,
      for (final spec in BudgetTools.writeSpecs) spec.name,
    ]);
    final readOnly = {for (final spec in BudgetTools.specs) spec.name};
    for (final tool in listed.tools) {
      expect(
        tool.toolAnnotations?.readOnlyHint,
        readOnly.contains(tool.name),
        reason: tool.name,
      );
    }
    // A Review or delete tool is never registered, so no client can see one.
    final registered = {for (final tool in listed.tools) tool.name};
    expect(registered.intersection(BudgetTools.neverToolNames), isEmpty);

    final result = await connection.callTool(
      CallToolRequest(name: 'list_budgets'),
    );
    expect(result.isError, isNot(true));
    expect((result.content.single as TextContent).text, contains('"Home"'));

    // A read records the client's own name for Settings.
    await connection.callTool(
      CallToolRequest(name: 'get_month', arguments: {'budgetId': id}),
    );
    expect((await store.read()).single.book.lastUsedBy, 'Test client');
  });

  test('a refusal comes back as a tool error, not a protocol error', () async {
    final (connection, _, _) = await _connect();
    final result = await connection.callTool(
      CallToolRequest(name: 'get_month', arguments: const {'budgetId': 'nope'}),
    );
    expect(result.isError, isTrue);
    expect(
      ((result.content.single as TextContent).text),
      contains('No budget'),
    );
  });
}
