part of 'engine.dart';

// Redaction (ticket 11) --------------------------------------------------

/// Redacts [targets] in the log, then appends the one Redacted Event that
/// records who, when and which Events.
CommandResult _redact(List<RedactTarget> targets, _Stamp stamp) {
  if (!stamp.actor.isPerson) return const Rejected(Rejection.personRequired);
  final unique = {...targets};
  if (unique.isEmpty || unique.any((target) => !canRedact(target))) {
    return const Rejected(Rejection.cannotRedact);
  }
  final engine = stamp._engine;
  final rewritten = <Event>[];
  final eventIds = <String>[];
  for (final event in engine._events) {
    final redacted = redactedEvent(event, unique);
    if (redacted == null) continue;
    rewritten.add(redacted);
    eventIds.add(event.id);
  }
  if (rewritten.isEmpty) return const Rejected(Rejection.noChange);
  // The value leaves the store before the audit Event lands, so a crash
  // can't leave a Redacted Event without the rewrite it records.
  engine._log.rewrite(rewritten);
  engine._replaceEvents(rewritten);
  return Accepted([
    stamp.event(EventType.redacted, {
      'targets': [for (final target in unique) target.toJson()],
      'eventIds': eventIds,
      'by': stamp.actor.value,
    }),
  ]);
}
