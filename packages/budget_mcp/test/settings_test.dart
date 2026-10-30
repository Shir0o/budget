import 'dart:convert';
import 'dart:io';

import 'package:budget_mcp/budget_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpMode', () {
    test(
      'Off is the only mode that reads nothing, and only Read-write writes',
      () {
        expect(McpMode.off.allowsRead, isFalse);
        expect(McpMode.off.allowsWrite, isFalse);
        expect(McpMode.readOnly.allowsRead, isTrue);
        expect(McpMode.readOnly.allowsWrite, isFalse);
        expect(McpMode.readWrite.allowsRead, isTrue);
        expect(McpMode.readWrite.allowsWrite, isTrue);
        expect(McpMode.values.map((mode) => mode.label), [
          'Off',
          'Read-only',
          'Read-write',
        ]);
      },
    );

    test('a book round trips through JSON', () {
      final book = McpBook(
        mode: McpMode.readOnly,
        lastUsedBy: 'Claude Desktop',
        lastUsedAt: DateTime(2026, 11, 20, 10, 30),
      );
      expect(McpBook.fromJson(book.toJson()), book);
      expect(McpBook.fromJson(const {}), McpBook.off);
      expect(McpBook.fromJson(const {'mode': 'nonsense'}), McpBook.off);
    });
  });

  group('the registry', () {
    late Directory directory;
    late FileMcpStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('budget-mcp');
      store = FileMcpStore(directory.path);
      addTearDown(() => directory.delete(recursive: true));
    });

    test('a missing file is no budgets, so everything is Off', () async {
      expect(await store.read(), isEmpty);
    });

    test(
      'register keeps a setting and drops budgets the app removed',
      () async {
        await store.register([
          (id: 'one', name: 'Home', store: 'budget-one.db'),
          (id: 'two', name: 'Travel', store: 'budget-two.db'),
        ]);
        await store.setMode('one', McpMode.readOnly);

        // The app reloads and registers the same budget plus nothing else.
        await store.register([
          (id: 'one', name: 'Home', store: 'budget-one.db'),
        ]);

        final budgets = await store.read();
        expect(budgets, hasLength(1));
        expect(budgets.single.id, 'one');
        expect(budgets.single.book.mode, McpMode.readOnly);
      },
    );

    test(
      'setMode and recordUse write one budget, leaving the rest alone',
      () async {
        await store.register([
          (id: 'one', name: 'Home', store: 'budget-one.db'),
          (id: 'two', name: 'Travel', store: 'budget-two.db'),
        ]);
        await store.setMode('two', McpMode.readWrite);
        await store.recordUse('two', 'Claude Desktop', DateTime(2026, 11, 20));

        final budgets = await store.read();
        expect(budgets.first.book.mode, McpMode.off);
        expect(budgets.last.book.mode, McpMode.readWrite);
        expect(budgets.last.book.lastUsedBy, 'Claude Desktop');
        expect(await store.budget('nope'), isNull);
        expect((await store.budget('two'))!.name, 'Travel');
      },
    );

    test('the file holds no amounts, payees or keys', () async {
      await store.register([(id: 'one', name: 'Home', store: 'budget-one.db')]);
      final fields = (jsonDecode(await store.file.readAsString()) as Map)
          .cast<String, Object?>();
      expect(fields.keys, ['budgets']);
      expect(
        ((fields['budgets'] as List).single as Map).keys,
        containsAll(['id', 'name', 'store', 'book']),
      );
    });
  });

  test('clientConfig is a paste-ready block for the bundled binary', () {
    final config = jsonDecode(clientConfig()) as Map;
    final server = (config['mcpServers'] as Map)['budget'] as Map;
    expect(
      server['command'],
      '/Applications/Budget.app/Contents/MacOS/budget-mcp',
    );
    expect(server['args'], isEmpty);
    expect(
      clientConfig(command: '/tmp/budget-mcp'),
      contains('/tmp/budget-mcp'),
    );
  });
}
