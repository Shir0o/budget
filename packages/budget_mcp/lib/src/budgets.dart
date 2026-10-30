import 'package:budget_core/budget_core.dart' show Event;

import 'book.dart';

/// One budget the MCP server may open: where its encrypted store is, its
/// setting, and the last client that used it (ticket 13).
final class McpBudget {
  const McpBudget({
    required this.id,
    required this.name,
    required this.store,
    this.book = McpBook.off,
  });

  static McpBudget fromJson(Map<String, Object?> json) => McpBudget(
    id: json['id'] as String,
    name: json['name'] as String,
    store: json['store'] as String,
    book: McpBook.fromJson(
      (json['book'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
  );

  final String id;
  final String name;

  /// The store file's name, inside the app's support directory.
  final String store;
  final McpBook book;

  McpBudget withBook(McpBook book) =>
      McpBudget(id: id, name: name, store: store, book: book);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'store': store,
    'book': book.toJson(),
  };
}

/// A budget as the app registers it, before it has an MCP setting. The file
/// name is `budget-<id>.db`, the app's store per budget.
typedef StoredBudget = ({String id, String name, String store});

/// The budgets on this device and their MCP settings, shared by the app and
/// `budget-mcp` (ticket 13). It holds no amounts, payees or keys.
abstract interface class McpStore {
  Future<List<McpBudget>> read();
  Future<void> write(List<McpBudget> budgets);
}

extension McpStoreChanges on McpStore {
  /// The budget with [id], or null when the app doesn't have it.
  Future<McpBudget?> budget(String id) async {
    for (final budget in await read()) {
      if (budget.id == id) return budget;
    }
    return null;
  }

  /// Sets [id]'s mode, keeping the rest of its book. Unknown ids are ignored.
  Future<void> setMode(String id, McpMode mode) =>
      _change(id, (budget) => budget.withBook(budget.book.withMode(mode)));

  /// Notes that [client] used [id] at [at], as Settings shows it.
  Future<void> recordUse(String id, String client, DateTime at) =>
      _change(id, (budget) => budget.withBook(budget.book.usedBy(client, at)));

  /// Adds or updates the app's budgets, keeping each one's setting, and
  /// drops budgets the app no longer has. A budget this device has never
  /// seen starts Off.
  Future<void> register(Iterable<StoredBudget> budgets) async {
    final stored = {for (final budget in await read()) budget.id: budget};
    final next = <McpBudget>[];
    final seen = <String>{};
    for (final (:id, :name, :store) in budgets) {
      if (!seen.add(id)) continue;
      final existing = stored[id];
      next.add(
        McpBudget(
          id: id,
          name: name,
          store: store,
          book: existing?.book ?? McpBook.off,
        ),
      );
    }
    await write(next);
  }

  Future<void> _change(String id, McpBudget Function(McpBudget) change) async {
    final budgets = await read();
    final index = budgets.indexWhere((budget) => budget.id == id);
    if (index < 0) return;
    budgets[index] = change(budgets[index]);
    await write(budgets);
  }
}

/// An [McpStore] held in memory, for tests and previews.
final class InMemoryMcpStore implements McpStore {
  InMemoryMcpStore([Iterable<McpBudget> budgets = const []])
    : _budgets = List.of(budgets);

  List<McpBudget> _budgets;

  @override
  Future<List<McpBudget>> read() async => List.of(_budgets);

  @override
  Future<void> write(List<McpBudget> budgets) async =>
      _budgets = List.of(budgets);
}

/// Where the server gets a budget's Events. The app and `budget-mcp` open the
/// SQLCipher store; tests keep logs in memory.
abstract interface class EventSource {
  Future<List<Event>> events(McpBudget budget);
}

/// An [EventSource] from [logs] by budget id, for tests.
final class InMemoryEventSource implements EventSource {
  InMemoryEventSource([Map<String, List<Event>> logs = const {}])
    : _logs = {...logs};

  final Map<String, List<Event>> _logs;

  @override
  Future<List<Event>> events(McpBudget budget) async =>
      List.of(_logs[budget.id] ?? const []);
}
