part of 'history.dart';

// Go back to a date (ticket 11) ------------------------------------------

/// The first local instant after [date]. The budget "as of" [date] is every
/// Event group that began before it.
DateTime endOfDay(CivilDate date) =>
    DateTime(date.year, date.month, date.day + 1);

/// The Events of every group that began before the end of [date]. A group
/// is never split.
List<Event> eventsAsOf(Iterable<Event> events, CivilDate date) {
  final cutoff = endOfDay(date).millisecondsSinceEpoch;
  final starts = <String, int>{};
  for (final event in events) {
    final ms = event.hlc.wallMs;
    starts.update(
      event.groupId,
      (start) => ms < start ? ms : start,
      ifAbsent: () => ms,
    );
  }
  return [
    for (final event in events)
      if (starts[event.groupId]! < cutoff) event,
  ];
}

/// The Events that put the budget back as it was at the end of [date]:
/// the full difference between then and now, after a
/// [EventType.restoredToDate] marker. [by] is the Actor asking.
Compensation restoreTo(
  Iterable<Event> events,
  CivilDate date, {
  required Actor by,
}) {
  Compensation rejected(Rejection reason) =>
      (rejection: reason, events: const []);
  final all = events.toList();
  final now = ChangeHistory.of(all);
  final then = ChangeHistory.of(eventsAsOf(all, date));

  // Restores first, so later writes find the entity, and deletes last,
  // latest created first.
  final restores = <PlannedEvent>[];
  final writes = <PlannedEvent>[];
  final deletes = <List<PlannedEvent>>[];
  bool write(
    List<PlannedEvent> into,
    EntityRef entity,
    Map<String, Object?> f,
  ) {
    final written = writeFields(entity, f);
    if (written == null) return false;
    into.addAll(written);
    return true;
  }

  bool delete(EntityRef entity) {
    final written = writeFields(entity, {deletedField: true});
    if (written == null) return false;
    deletes.add(written);
    return true;
  }

  for (final MapEntry(key: entity, value: current) in now._values.entries) {
    // Only entities something created have a deleted field.
    if (!current.containsKey(deletedField)) continue;
    final past = then._values[entity];
    if (past == null || !past.containsKey(deletedField)) {
      if (current[deletedField] != true && !delete(entity)) {
        return rejected(Rejection.cannotRevert);
      }
      continue;
    }
    final wasDeleted = past[deletedField] == true;
    final isDeleted = current[deletedField] == true;
    if (wasDeleted != isDeleted) {
      final ok = wasDeleted
          ? delete(entity)
          : write(restores, entity, {deletedField: false});
      if (!ok) return rejected(Rejection.cannotRevert);
    }
    final changed = {
      for (final field in {...past.keys, ...current.keys})
        if (field != deletedField && !_sameValue(past[field], current[field]))
          field: past[field],
    };
    if (changed.isNotEmpty && !write(writes, entity, changed)) {
      return rejected(Rejection.cannotRevert);
    }
  }

  final deltas = <PlannedEvent>[];
  for (final entity in {...now._totals.keys, ...then._totals.keys}) {
    final current = now._totals[entity] ?? const {};
    final past = then._totals[entity] ?? const {};
    for (final key in {...current.keys, ...past.keys}) {
      final cents = (past[key] ?? 0) - (current[key] ?? 0);
      if (cents == 0) continue;
      final written = writeDelta(entity, key, cents);
      if (written == null) return rejected(Rejection.cannotRevert);
      deltas.add(written);
    }
  }

  final compensating = [
    ...restores,
    ...writes,
    ...deltas,
    for (final events in deletes.reversed) ...events,
  ];
  if (compensating.isEmpty) return rejected(Rejection.noChange);
  return (
    rejection: null,
    events: [
      (EventType.restoredToDate, {'date': date.toIso(), 'by': by.value}),
      ...compensating,
    ],
  );
}

/// Deep equality of JSON-like values.
bool _sameValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _sameValue(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameValue(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
