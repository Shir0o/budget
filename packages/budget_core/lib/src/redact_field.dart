import 'budget_state.dart';
import 'event.dart';
import 'event_effects.dart';

// Ticket 11: redaction is the one permitted rewrite of the Event log, for
// when a card or account number got stored anyway. These are pure
// functions, so the rewrite a device does is the rewrite every device does.

/// What a redacted value reads as, in every past Event and snapshot.
const redactedValue = '[redacted]';

/// One field of one entity a person asks to redact: a transaction's or
/// Scheduled Transaction's payee or memo, a line's memo, or an account's,
/// Category's or category group's name (ticket 11).
final class RedactTarget {
  const RedactTarget(this.entity, this.field, {this.lineId});

  factory RedactTarget.fromJson(Map<String, Object?> json) => RedactTarget(
    EntityRef(
      EntityKind.values.byName(json['entity'] as String),
      json['id'] as String,
    ),
    json['field'] as String,
    lineId: json['lineId'] as String?,
  );

  final EntityRef entity;

  /// `payee`, `memo`, `lineMemo` or `name`.
  final String field;

  /// The line whose memo this is, when [field] is `lineMemo`.
  final String? lineId;

  Map<String, Object?> toJson() => {
    'entity': entity.kind.name,
    'id': entity.id,
    'field': field,
    'lineId': ?lineId,
  };

  @override
  bool operator ==(Object other) =>
      other is RedactTarget &&
      other.entity == entity &&
      other.field == field &&
      other.lineId == lineId;

  @override
  int get hashCode => Object.hash(entity, field, lineId);
}

/// Whether this version can redact [target]. Budget creation and Business
/// Tags have no field a card or account number fits in.
bool canRedact(RedactTarget target) => switch (target.entity.kind) {
  EntityKind.transaction => switch (target.field) {
    'payee' || 'memo' => true,
    'lineMemo' => target.lineId != null,
    _ => false,
  },
  EntityKind.schedule => target.field == 'payee' || target.field == 'memo',
  EntityKind.account ||
  EntityKind.category ||
  EntityKind.categoryGroup => target.field == 'name',
  EntityKind.budget || EntityKind.businessTag => false,
};

/// One field of one entity that holds something a person may want gone,
/// with its current value, for the Redact field screen.
final class RedactCandidate {
  const RedactCandidate(this.target, this.label, this.value);

  final RedactTarget target;

  /// Such as `Payee` or `Line memo`.
  final String label;
  final String value;
}

/// The fields of [entity] that can be redacted now, with their current
/// values. Empty for an entity that doesn't exist or has no such value.
List<RedactCandidate> redactCandidates(BudgetState state, EntityRef entity) {
  switch (entity.kind) {
    case EntityKind.transaction:
      final transaction = state.transaction(entity.id);
      if (transaction == null) return const [];
      return [
        if (_holdsValue(transaction.payee))
          RedactCandidate(
            RedactTarget(entity, 'payee'),
            'Payee',
            transaction.payee,
          ),
        if (_holdsValue(transaction.memo))
          RedactCandidate(
            RedactTarget(entity, 'memo'),
            'Memo',
            transaction.memo,
          ),
        for (final line in transaction.lines)
          if (_holdsValue(line.memo))
            RedactCandidate(
              RedactTarget(entity, 'lineMemo', lineId: line.id),
              'Line memo',
              line.memo,
            ),
      ];
    case EntityKind.schedule:
      final schedule = state.schedule(entity.id);
      if (schedule == null) return const [];
      return [
        if (_holdsValue(schedule.payee))
          RedactCandidate(
            RedactTarget(entity, 'payee'),
            'Payee',
            schedule.payee,
          ),
        if (_holdsValue(schedule.memo))
          RedactCandidate(RedactTarget(entity, 'memo'), 'Memo', schedule.memo),
      ];
    case EntityKind.account:
      final name = state.account(entity.id)?.name;
      return [
        if (name != null && _holdsValue(name))
          RedactCandidate(RedactTarget(entity, 'name'), 'Name', name),
      ];
    case EntityKind.category:
      final name = state.category(entity.id)?.name;
      return [
        if (name != null && _holdsValue(name))
          RedactCandidate(RedactTarget(entity, 'name'), 'Name', name),
      ];
    case EntityKind.categoryGroup:
      final name = state.categoryGroup(entity.id)?.name;
      return [
        if (name != null && _holdsValue(name))
          RedactCandidate(RedactTarget(entity, 'name'), 'Name', name),
      ];
    case EntityKind.budget || EntityKind.businessTag:
      return const [];
  }
}

/// The [RedactTarget]s a [EventType.redacted] Event records.
List<RedactTarget> redactTargets(Event event) => [
  for (final target in (event.payload['targets'] as List).cast<Map>())
    RedactTarget.fromJson(target.cast<String, Object?>()),
];

/// [event] with every value [targets] name replaced by [redactedValue], or
/// null when it holds none of them, so a rewrite pass changes only what it
/// must. Ids, amounts and clocks are untouched, so the Event still sorts
/// where it did.
Event? redactedEvent(Event event, Iterable<RedactTarget> targets) {
  var payload = event.payload;
  var changed = false;

  for (final target in targets) {
    switch (event.type) {
      case EventType.transactionCreated:
        if (target.entity !=
            EntityRef.transaction(event.payload['transactionId'] as String)) {
          continue;
        }
        switch (target.field) {
          case 'payee' || 'memo':
            if (_holdsValue(payload[target.field])) {
              payload = {...payload, target.field: redactedValue};
              changed = true;
            }
          case 'lineMemo':
            final lines = _redactedLines(payload['lines'], target.lineId);
            if (lines != null) {
              payload = {...payload, 'lines': lines};
              changed = true;
            }
        }
      case EventType.transactionFieldsSet:
        if (target.entity !=
            EntityRef.transaction(event.payload['transactionId'] as String)) {
          continue;
        }
        if (target.field == 'payee' || target.field == 'memo') {
          final fields = (payload['fields'] as Map).cast<String, Object?>();
          if (_holdsValue(fields[target.field])) {
            payload = {
              ...payload,
              'fields': {...fields, target.field: redactedValue},
            };
            changed = true;
          }
        }
      case EventType.transactionSplitSet:
        if (target.entity !=
            EntityRef.transaction(event.payload['transactionId'] as String)) {
          continue;
        }
        if (target.field == 'lineMemo') {
          final lines = _redactedLines(payload['lines'], target.lineId);
          if (lines != null) {
            payload = {...payload, 'lines': lines};
            changed = true;
          }
        }
      case EventType.scheduleCreated:
        if (target.entity !=
            EntityRef.schedule(event.payload['scheduleId'] as String)) {
          continue;
        }
        if ((target.field == 'payee' || target.field == 'memo') &&
            _holdsValue(payload[target.field])) {
          payload = {...payload, target.field: redactedValue};
          changed = true;
        }
      case EventType.scheduleFieldsSet:
        if (target.entity !=
            EntityRef.schedule(event.payload['scheduleId'] as String)) {
          continue;
        }
        if (target.field == 'payee' || target.field == 'memo') {
          final fields = (payload['fields'] as Map).cast<String, Object?>();
          if (_holdsValue(fields[target.field])) {
            payload = {
              ...payload,
              'fields': {...fields, target.field: redactedValue},
            };
            changed = true;
          }
        }
      case EventType.accountCreated ||
          EventType.categoryCreated ||
          EventType.categoryGroupCreated:
        final kind = switch (event.type) {
          EventType.accountCreated => EntityKind.account,
          EventType.categoryCreated => EntityKind.category,
          _ => EntityKind.categoryGroup,
        };
        final idKey = switch (kind) {
          EntityKind.account => 'accountId',
          EntityKind.category => 'categoryId',
          _ => 'categoryGroupId',
        };
        if (target.entity != EntityRef(kind, event.payload[idKey] as String) ||
            target.field != 'name' ||
            !_holdsValue(payload['name'])) {
          continue;
        }
        payload = {...payload, 'name': redactedValue};
        changed = true;
    }
  }
  return changed ? event.withPayload(payload) : null;
}

/// [lines] with the memo of [lineId] replaced, or null when that line's
/// memo holds no value.
List<Object?>? _redactedLines(Object? lines, String? lineId) {
  if (lines is! List) return null;
  final rewritten = <Object?>[];
  var changed = false;
  for (final line in lines) {
    if (line is Map && line['lineId'] == lineId && _holdsValue(line['memo'])) {
      rewritten.add({...line, 'memo': redactedValue});
      changed = true;
    } else {
      rewritten.add(line);
    }
  }
  return changed ? rewritten : null;
}

/// Whether [value] is a text that still holds something to redact: a value
/// that is missing, empty or already [redactedValue] has none.
bool _holdsValue(Object? value) =>
    value is String && value.isNotEmpty && value != redactedValue;
