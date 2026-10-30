import 'package:budget_core/budget_core.dart';
import 'package:flutter/widgets.dart';

import 'services.dart';

/// Where each budget's Event log lives: its own store file, sealed with its
/// own store key. The real one is SQLCipher files plus Keystore-backed keys.
abstract interface class BudgetStorage {
  /// The log for [budgetId], created on first use.
  Future<EventLog> openLog(String budgetId);
}

/// Logs held in memory, for tests and previews.
final class InMemoryBudgetStorage implements BudgetStorage {
  final _logs = <String, InMemoryEventLog>{};

  @override
  Future<EventLog> openLog(String budgetId) async =>
      _logs.putIfAbsent(budgetId, InMemoryEventLog.new);
}

/// One line of the budget switcher.
final class BudgetEntry {
  const BudgetEntry({
    required this.id,
    required this.name,
    required this.isOpen,
  });

  final String id;
  final String name;
  final bool isOpen;
}

/// The budgets on this device and which one is open. Each has its own
/// budgetId, store file, store key and Budget Key, so they never mix.
///
/// A new budget is a draft held in memory until its first account is saved
/// ([commit]); backing out of the Welcome flow leaves no file or key behind.
final class BudgetLibrary {
  BudgetLibrary._({
    required this.storage,
    required this.prefs,
    required this.deviceId,
    required this.actor,
    required this._engines,
    required this._current,
    this._adopted,
  });

  /// Opens every budget the device knows and picks the last one opened. A
  /// device with none starts a draft.
  static Future<BudgetLibrary> load({
    required BudgetStorage storage,
    required DevicePrefs prefs,
    required String deviceId,
    required Actor actor,
  }) async {
    BudgetEngine engineFor(EventLog log) =>
        BudgetEngine(log: log, deviceId: deviceId, actor: actor);
    final engines = <String, BudgetEngine>{
      for (final id in await prefs.readBudgetIds())
        id: engineFor(await storage.openLog(id)),
    };
    final lastId = await prefs.readLastBudgetId();
    final current =
        engines[lastId] ??
        (engines.isEmpty
            ? engineFor(InMemoryEventLog())
            : engines.values.first);
    return BudgetLibrary._(
      storage: storage,
      prefs: prefs,
      deviceId: deviceId,
      actor: actor,
      engines: engines,
      current: current,
    );
  }

  /// A library around one [engine], which keeps its own log. For tests and
  /// previews.
  factory BudgetLibrary.single(BudgetEngine engine, {DevicePrefs? prefs}) {
    final id = engine.state.budget?.id;
    return BudgetLibrary._(
      storage: InMemoryBudgetStorage(),
      prefs: prefs ?? InMemoryDevicePrefs(),
      deviceId: engine.deviceId,
      actor: engine.actor,
      engines: {?id: engine},
      current: engine,
      adopted: engine,
    );
  }

  final BudgetStorage storage;
  final DevicePrefs prefs;
  final String deviceId;
  final Actor actor;
  final Map<String, BudgetEngine> _engines;
  BudgetEngine _current;
  final BudgetEngine? _adopted;

  /// The open budget. Holds no budget yet while a draft is open.
  BudgetEngine get current => _current;

  /// Every saved budget, in the order they were made.
  List<BudgetEntry> get entries => [
    for (final MapEntry(:key, :value) in _engines.entries)
      BudgetEntry(
        id: key,
        name: value.state.budget!.name,
        isOpen: identical(value, _current),
      ),
  ];

  /// Opens the saved budget [id] and remembers it as the last opened.
  Future<BudgetEngine> switchTo(String id) async {
    final engine = _engines[id]!;
    _current = engine;
    await prefs.writeLastBudgetId(id);
    return engine;
  }

  /// An empty budget for the Welcome flow. Nothing is stored until [commit].
  BudgetEngine startNew() =>
      BudgetEngine(log: InMemoryEventLog(), deviceId: deviceId, actor: actor);

  /// Stores a [draft] whose budget has been created: opens its own store file
  /// and key, moves its Events there, and makes it the open budget.
  Future<BudgetEngine> commit(BudgetEngine draft) async {
    final id = draft.state.budget!.id;
    final BudgetEngine engine;
    if (identical(draft, _adopted)) {
      engine = draft;
    } else {
      final log = await storage.openLog(id);
      log.append(draft.events);
      engine = BudgetEngine(log: log, deviceId: deviceId, actor: actor);
    }
    _engines[id] = engine;
    _current = engine;
    await prefs.writeBudgetIds(_engines.keys.toList());
    await prefs.writeLastBudgetId(id);
    return engine;
  }
}

/// Gives every screen below it the device's [BudgetLibrary].
class BudgetLibraryScope extends InheritedWidget {
  const BudgetLibraryScope({
    super.key,
    required this.library,
    required super.child,
  });

  final BudgetLibrary library;

  static BudgetLibrary of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BudgetLibraryScope>()!.library;

  @override
  bool updateShouldNotify(BudgetLibraryScope old) => library != old.library;
}
