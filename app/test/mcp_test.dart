import 'package:budget/app.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget, with its MCP settings in memory. [server] false is a
/// phone: no MCP binary runs there, so [AppServices.mcp] is null. Either way
/// one AI app change is in the log.
Future<(BudgetEngine, AppServices, InMemoryEventLog)> _home({
  bool server = true,
}) async {
  final log = InMemoryEventLog();
  final person = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  person.execute(const CreateBudget(name: 'Home'));
  person.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: const Money(421055),
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  final group = person.execute(const CreateCategoryGroup(name: 'Everyday'));
  final groupId =
      (group as Accepted).events.single.payload['categoryGroupId'] as String;

  // One AI app change, as the Mac's server writes it before the app opens.
  BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: const Actor.fromValue('mcp:Claude Desktop'),
  ).execute(CreateCategory(groupId: groupId, name: 'Coffee'));

  // The app replays the log, so it sees the AI app's change and sync would
  // bring it to a phone.
  final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  final services = server
      ? AppServices.inMemory()
      : AppServices(
          keys: InMemoryBudgetKeyStore(),
          prefs: InMemoryDevicePrefs(),
          saver: InMemoryFileSaver(),
          authenticator: FakeAuthenticator(),
        );
  if (server) {
    await services.mcp!.register([
      (id: engine.state.budget!.id, name: 'Home', store: 'budget-home.db'),
    ], deviceId: engine.deviceId);
  }
  return (engine, services, log);
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
    final (engine, services, _) = await _home();
    await _pump(tester, engine, services);
    await _openMcp(tester);

    expect(find.text('Nothing is shared.'), findsOneWidget);
    expect(find.text('Client config'), findsNothing);
    expect(find.text('No AI app has read this budget yet.'), findsNothing);
  });

  testWidgets('Read-only shows the client config and keeps the setting', (
    tester,
  ) async {
    final (engine, services, _) = await _home();
    await _pump(tester, engine, services);
    await _openMcp(tester);

    await tester.tap(find.text('Read-only'));
    await tester.pumpAndSettle();

    // The mode is written for the binary, not just held on screen.
    final budget = (await services.mcp!.read()).single;
    expect(budget.book.mode, McpMode.readOnly);
    expect(budget.store, 'budget-${engine.state.budget!.id}.db');
    // The registry knows which device's Events the binary writes, so sync
    // still uploads them.
    expect(budget.deviceId, engine.deviceId);
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

  testWidgets('Read-write says what AI apps may change', (tester) async {
    final (engine, services, _) = await _home();
    final id = engine.state.budget!.id;
    await services.mcp!.setMode(id, McpMode.readWrite);

    await _pump(tester, engine, services);
    await _openMcp(tester);

    expect(
      find.text(
        'AI apps can read and change this budget. Nothing is deleted, and '
        'only you mark a line Reviewed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows the last client that read the budget', (tester) async {
    final (engine, services, _) = await _home();
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
    final (engine, services, _) = await _home();
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

  testWidgets('MCP changes link opens Change History on the MCP Actor', (
    tester,
  ) async {
    final (engine, services, _) = await _home();
    await _pump(tester, engine, services);
    await _openMcp(tester);

    expect(find.text('Added category Coffee · Claude Desktop'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcp-history')));
    await tester.pumpAndSettle();

    expect(find.text('Change History'), findsOneWidget);
    expect(find.text('MCP · Claude Desktop'), findsOneWidget);
  });

  testWidgets('on a phone it shows access, the last client and the link', (
    tester,
  ) async {
    final (engine, services, _) = await _home(server: false);
    expect(services.mcp, isNull);
    await _pump(tester, engine, services);
    await _openMcp(tester);

    // No server here, so this device's access is Off, and the setting lives
    // on the Mac.
    expect(find.text('Off'), findsOneWidget);
    expect(
      find.text(
        'AI apps connect through the Mac app, where Off, Read-only or '
        'Read-write is chosen per budget. This device runs no server.',
      ),
      findsOneWidget,
    );
    // Last client, from what AI apps wrote and sync brought here.
    expect(
      find.textContaining('Last change by Claude Desktop at'),
      findsOneWidget,
    );
    expect(find.text('Added category Coffee · Claude Desktop'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mcp-history')));
    await tester.pumpAndSettle();
    expect(find.text('Change History'), findsOneWidget);
    expect(find.text('MCP · Claude Desktop'), findsOneWidget);
    expect(find.text('Added category Coffee'), findsOneWidget);
  });
}
