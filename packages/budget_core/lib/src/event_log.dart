import 'event.dart';

/// Where a budget's Events are kept. `budget_store` provides the encrypted
/// on-device implementation.
abstract interface class EventLog {
  /// Every Event, in HLC order.
  List<Event> readAll();

  /// Appends one Event group atomically.
  void append(List<Event> group);
}

/// An [EventLog] held in memory, for tests and previews.
final class InMemoryEventLog implements EventLog {
  final _events = <Event>[];

  @override
  List<Event> readAll() => List.unmodifiable(
    _events.toList()..sort((a, b) => a.hlc.compareTo(b.hlc)),
  );

  @override
  void append(List<Event> group) => _events.addAll(group);
}
