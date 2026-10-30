import 'event.dart';

/// Where a budget's Events are kept. `budget_store` provides the encrypted
/// on-device implementation.
abstract interface class EventLog {
  /// Every Event, in HLC order.
  List<Event> readAll();

  /// Appends one Event group atomically.
  void append(List<Event> group);

  /// Replaces Events already in the log that have the same ids, as a
  /// redaction does (ticket 11). Nothing else changes, so order and clocks
  /// stay. A log that doesn't hold an Event skips it.
  void rewrite(List<Event> events);
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

  @override
  void rewrite(List<Event> events) {
    final byId = {for (final event in events) event.id: event};
    for (var i = 0; i < _events.length; i++) {
      final rewritten = byId[_events[i].id];
      if (rewritten != null) _events[i] = rewritten;
    }
  }
}
