import 'package:budget/app.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget, with its MCP settings in memory.
Future<(BudgetEngine, AppServices)> _home() async {
  final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  engine.execute(const CreateBudget(name: 'Home'));
  engine.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: const Money(421055),
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  final services = AppServices.inMemory();
  await services.mcp!.register([
    (id: engine.state.budget!.id, name: 'Home', store: 'budget-home.db'),
  ]);
  return (engine, services);
}

Future<void> _pump(
  WidgetTester tester,
  BudgetEngine engine,
  AppServices services,
) async {
  // Tall enough for the whole screen, so the config and last-used line build.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BudgetApp(engine: engine, services: services));
  await tester.pumpAndSettle();
}

Future<void> _openMcp(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  final row = find.text('AI apps (MCP)');
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('is Off by default and shares nothing', (tester) async {
    final (engine, services) = await _home();
    await _pump(tester, engine, services);
    await _openMcp(tester);

    expect(find.text('Nothing is shared.'), findsOneWidget);
    expect(find.text('Client config'), findsNothing);
    expect(find.text('No AI app has read this budget yet.'), findsNothing);
  });

  testWidgets('Read-only shows the client config and keeps the setting', (
    tester,
  ) async {
    final (engine, services) = await _home();
    await _pump(tester, engine, services);
    await _openMcp(tester);

    await tester.tap(find.text('Read-only'));
    await tester.pumpAndSettle();

    // The mode is written for the binary, not just held on screen.
    final budget = (await services.mcp!.read()).single;
    expect(budget.book.mode, McpMode.readOnly);
    expect(budget.store, 'budget-${engine.state.budget!.id}.db');
    // The config names the bundled binary, and the last-used line shows.
    final config = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(
      config,
      contains('/Applications/Budget.app/Contents/MacOS/budget-mcp'),
    );
    expect(config, contains('"budget"'));
    expect(find.text('No AI app has read this budget yet.'), findsOneWidget);

    // Copy puts that block on the clipboard.
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('mcp-copy')));
    await tester.pumpAndSettle();
    expect(clipboard.single, config);
    expect(find.text('Copied'), findsOneWidget);

    // Settings shows the new mode after going back.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Read-only'), findsOneWidget);
  });

  testWidgets('shows the last client that read the budget', (tester) async {
    final (engine, services) = await _home();
    final id = engine.state.budget!.id;
    await services.mcp!.recordUse(
      id,
      'Claude Desktop',
      DateTime(2026, 11, 20, 10, 30),
    );
    await services.mcp!.setMode(id, McpMode.readOnly);

    await _pump(tester, engine, services);
    await _openMcp(tester);

    expect(
      find.text('Last used by Claude Desktop at Nov 20, 2026 10:30 AM'),
      findsOneWidget,
    );
  });

  testWidgets('turning it Off hides the config again', (tester) async {
    final (engine, services) = await _home();
    final id = engine.state.budget!.id;
    await services.mcp!.setMode(id, McpMode.readWrite);

    await _pump(tester, engine, services);
    await _openMcp(tester);
    expect(find.text('Client config'), findsOneWidget);

    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();

    expect(find.text('Client config'), findsNothing);
    expect((await services.mcp!.read()).single.book.mode, McpMode.off);
  });
}
