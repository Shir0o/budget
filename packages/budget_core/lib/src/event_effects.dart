import 'event.dart';

/// The kinds of thing an Event can change.
enum EntityKind {
  budget,
  account,
  categoryGroup,
  category,
  transaction,
  schedule,
  businessTag,
}

/// One budget, account, category group, Category, transaction or Scheduled
/// Transaction.
final class EntityRef {
  const EntityRef(this.kind, this.id);

  const EntityRef.account(this.id) : kind = EntityKind.account;
  const EntityRef.category(this.id) : kind = EntityKind.category;
  const EntityRef.transaction(this.id) : kind = EntityKind.transaction;
  const EntityRef.schedule(this.id) : kind = EntityKind.schedule;

  final EntityKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is EntityRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => '${kind.name}:$id';
}

/// What one Event does to one entity, in the terms Change History and
/// revert work in (ticket 11). Each Event type maps to effects in
/// [eventSpecs], so revert is generic over Event types.
sealed class Effect {
  const Effect(this.entity);

  final EntityRef entity;
}

/// [entity] came into being with [fields].
final class Creates extends Effect {
  const Creates(super.entity, this.fields);

  final Map<String, Object?> fields;
}

/// Sets each of [fields] on [entity], last writer wins per field. Lifecycle
/// changes are the [deletedField] and [archivedField] fields.
final class SetsFields extends Effect {
  const SetsFields(super.entity, this.fields);

  final Map<String, Object?> fields;
}

/// Adds [cents] to [entity]'s total under [key], as an Assignment does for
/// a month. Deltas add up, so they never conflict.
final class AddsDelta extends Effect {
  const AddsDelta(super.entity, this.key, this.cents);

  final String key;
  final int cents;
}

/// True once an entity is deleted, false again when it is restored.
const deletedField = 'deleted';

/// True while a Category is archived.
const archivedField = 'archived';

/// A Category's Target in its stored form, or null for none (ticket 08).
const targetField = 'target';

/// A Category's Automation Mode, or null for the default.
const automationModeField = 'automationMode';

/// The budget's priority order of Category ids.
const priorityField = 'priority';

/// A transaction's amount and lines together, as `{amountCents, lines}`.
/// The whole line set is last writer wins (ticket 06).
const splitField = 'split';

/// A Business Tag's business-use % for one tax year, stored as
/// `Business use % for <year>`. A null value, as a revert writes, unsets it.
const businessUseField = 'Business use % for ';

/// How Change History reads one Event type.
final class EventSpec {
  const EventSpec(this.effects, {this.references = _noReferences});

  final List<Effect> Function(Map<String, Object?> payload) effects;

  /// Other entities the Event needs to exist, such as a line's Category.
  /// A revert that removes one of them must revert the Event too.
  final List<EntityRef> Function(Map<String, Object?> payload) references;
}

List<EntityRef> _noReferences(Map<String, Object?> _) => const [];

/// An Event to append, before it is stamped with ids and a clock.
typedef PlannedEvent = (String type, Map<String, Object?> payload);

String _id(Map<String, Object?> p, String key) => p[key] as String;

Map<String, Object?> _split(Map<String, Object?> p) => {
  'amountCents': p['amountCents'],
  'lines': p['lines'],
};

List<EntityRef> _lineCategories(Map<String, Object?> p) => [
  for (final line in (p['lines'] as List).cast<Map>())
    if (line['category'] case final String category
        when category != readyToAssignCategory)
      EntityRef.category(category),
];

EventSpec _lifecycle(EntityKind kind, String key, String field, bool value) =>
    EventSpec(
      (p) => [
        SetsFields(EntityRef(kind, _id(p, key)), {field: value}),
      ],
    );

/// The effects of every Event type Change History understands. A type
/// missing here shows in history but can't be reverted. New Event types
/// add an entry here, and [writeFields] or [writeDelta] cases for the
/// Events that undo them.
final Map<String, EventSpec> eventSpecs = {
  EventType.budgetCreated: EventSpec(
    (p) => [
      Creates(const EntityRef(EntityKind.budget, ''), {'name': p['name']}),
    ],
  ),
  EventType.accountCreated: EventSpec(
    (p) => [
      Creates(EntityRef.account(_id(p, 'accountId')), {
        'name': p['name'],
        'accountType': p['accountType'],
      }),
    ],
  ),
  EventType.accountDeleted: _lifecycle(
    EntityKind.account,
    'accountId',
    deletedField,
    true,
  ),
  EventType.accountRestored: _lifecycle(
    EntityKind.account,
    'accountId',
    deletedField,
    false,
  ),
  EventType.transactionCreated: EventSpec(
    (p) => [
      Creates(EntityRef.transaction(_id(p, 'transactionId')), {
        'accountId': p['accountId'],
        'payee': p['payee'],
        'date': p['date'],
        'memo': p['memo'] ?? '',
        'cleared': p['cleared'] ?? 'uncleared',
        splitField: _split(p),
      }),
    ],
    references: (p) => [
      EntityRef.account(_id(p, 'accountId')),
      if (p['transferAccountId'] case final String other)
        EntityRef.account(other),
      ..._lineCategories(p),
    ],
  ),
  EventType.transactionFieldsSet: EventSpec(
    (p) => [
      SetsFields(
        EntityRef.transaction(_id(p, 'transactionId')),
        (p['fields'] as Map).cast<String, Object?>(),
      ),
    ],
  ),
  EventType.transactionSplitSet: EventSpec(
    (p) => [
      SetsFields(EntityRef.transaction(_id(p, 'transactionId')), {
        splitField: _split(p),
      }),
    ],
    references: _lineCategories,
  ),
  EventType.transactionDeleted: _lifecycle(
    EntityKind.transaction,
    'transactionId',
    deletedField,
    true,
  ),
  EventType.transactionRestored: _lifecycle(
    EntityKind.transaction,
    'transactionId',
    deletedField,
    false,
  ),
  EventType.categoryGroupCreated: EventSpec(
    (p) => [
      Creates(EntityRef(EntityKind.categoryGroup, _id(p, 'categoryGroupId')), {
        'name': p['name'],
      }),
    ],
  ),
  EventType.categoryGroupDeleted: _lifecycle(
    EntityKind.categoryGroup,
    'categoryGroupId',
    deletedField,
    true,
  ),
  EventType.categoryGroupRestored: _lifecycle(
    EntityKind.categoryGroup,
    'categoryGroupId',
    deletedField,
    false,
  ),
  EventType.categoryCreated: EventSpec(
    (p) => [
      Creates(EntityRef.category(_id(p, 'categoryId')), {
        'name': p['name'],
        'categoryGroupId': p['categoryGroupId'],
      }),
    ],
    references: (p) => [
      EntityRef(EntityKind.categoryGroup, _id(p, 'categoryGroupId')),
      if (p['cardAccountId'] case final String card) EntityRef.account(card),
    ],
  ),
  EventType.categoryArchived: _lifecycle(
    EntityKind.category,
    'categoryId',
    archivedField,
    true,
  ),
  EventType.categoryUnarchived: _lifecycle(
    EntityKind.category,
    'categoryId',
    archivedField,
    false,
  ),
  EventType.categoryDeleted: _lifecycle(
    EntityKind.category,
    'categoryId',
    deletedField,
    true,
  ),
  EventType.categoryRestored: _lifecycle(
    EntityKind.category,
    'categoryId',
    deletedField,
    false,
  ),
  EventType.assignmentChanged: EventSpec(
    (p) => [
      AddsDelta(
        EntityRef.category(_id(p, 'category')),
        p['month'] as String,
        p['deltaCents'] as int,
      ),
    ],
  ),
  EventType.groupReverted: EventSpec((_) => const []),
  EventType.restoredToDate: EventSpec((_) => const []),
  EventType.targetSet: EventSpec(
    (p) => [
      SetsFields(EntityRef.category(_id(p, 'categoryId')), {
        targetField: p['target'],
      }),
    ],
  ),
  EventType.targetCleared: EventSpec(
    (p) => [
      SetsFields(EntityRef.category(_id(p, 'categoryId')), {targetField: null}),
    ],
  ),
  EventType.automationModeSet: EventSpec(
    (p) => [
      SetsFields(EntityRef.category(_id(p, 'categoryId')), {
        automationModeField: p['mode'],
      }),
    ],
  ),
  EventType.prioritySet: EventSpec(
    (p) => [
      SetsFields(const EntityRef(EntityKind.budget, ''), {
        priorityField: p['categoryIds'],
      }),
    ],
  ),
  EventType.scheduleCreated: EventSpec(
    (p) => [
      Creates(EntityRef.schedule(_id(p, 'scheduleId')), {
        'accountId': p['accountId'],
        'payee': p['payee'],
        'memo': p['memo'] ?? '',
        'amountCents': p['amountCents'],
        'category': p['category'],
        'every': p['every'],
        'interval': p['interval'],
        'nextDue': p['nextDue'],
      }),
    ],
    references: (p) => [
      EntityRef.account(_id(p, 'accountId')),
      if (p['category'] case final String category
          when category != readyToAssignCategory)
        EntityRef.category(category),
    ],
  ),
  EventType.scheduleFieldsSet: EventSpec(
    (p) => [
      SetsFields(
        EntityRef.schedule(_id(p, 'scheduleId')),
        (p['fields'] as Map).cast<String, Object?>(),
      ),
    ],
    references: (p) => switch ((p['fields'] as Map)['category']) {
      final String category when category != readyToAssignCategory => [
        EntityRef.category(category),
      ],
      _ => const [],
    },
  ),
  EventType.scheduleDeleted: _lifecycle(
    EntityKind.schedule,
    'scheduleId',
    deletedField,
    true,
  ),
  EventType.scheduleRestored: _lifecycle(
    EntityKind.schedule,
    'scheduleId',
    deletedField,
    false,
  ),
  EventType.businessTagCreated: EventSpec(
    (p) => [
      Creates(EntityRef(EntityKind.businessTag, _id(p, 'name')), {
        'name': p['name'],
        'line': p['line'],
        'rule': p['rule'],
      }),
    ],
  ),
  EventType.businessUseSet: EventSpec(
    (p) => [
      SetsFields(EntityRef(EntityKind.businessTag, _id(p, 'tag')), {
        '$businessUseField${p['year']}': p['percent'],
      }),
    ],
  ),
};

/// The Events that set [fields] on [entity], or null when one of them
/// can't be written, so whatever needs it can't be reverted.
List<PlannedEvent>? writeFields(EntityRef entity, Map<String, Object?> fields) {
  final rest = Map.of(fields);
  final deleted = rest.containsKey(deletedField)
      ? rest.remove(deletedField) == true
      : null;
  final events = <PlannedEvent>[];

  PlannedEvent lifecycle(String deletedType, String restoredType, String key) =>
      (deleted! ? deletedType : restoredType, {key: entity.id});

  switch (entity.kind) {
    case EntityKind.transaction:
      final key = 'transactionId';
      if (rest.remove(splitField) case final Map<String, Object?> split) {
        events.add((EventType.transactionSplitSet, {key: entity.id, ...split}));
      }
      const writable = {
        'payee',
        'date',
        'memo',
        'cleared',
        'bankId',
        'pendingMatch',
      };
      if (!rest.keys.every(writable.contains)) return null;
      if (rest.isNotEmpty) {
        events.insert(0, (
          EventType.transactionFieldsSet,
          {key: entity.id, 'fields': rest},
        ));
      }
      if (deleted != null) {
        final event = lifecycle(
          EventType.transactionDeleted,
          EventType.transactionRestored,
          key,
        );
        deleted ? events.add(event) : events.insert(0, event);
      }
      return events;
    case EntityKind.category:
      final key = 'categoryId';
      if (rest.containsKey(archivedField)) {
        events.add((
          rest.remove(archivedField) == true
              ? EventType.categoryArchived
              : EventType.categoryUnarchived,
          {key: entity.id},
        ));
      }
      if (rest.containsKey(targetField)) {
        final target = rest.remove(targetField);
        events.add(
          target == null
              ? (EventType.targetCleared, {key: entity.id})
              : (EventType.targetSet, {key: entity.id, 'target': target}),
        );
      }
      if (rest.containsKey(automationModeField)) {
        events.add((
          EventType.automationModeSet,
          {key: entity.id, 'mode': rest.remove(automationModeField)},
        ));
      }
      if (rest.isNotEmpty) return null;
      if (deleted != null) {
        final event = lifecycle(
          EventType.categoryDeleted,
          EventType.categoryRestored,
          key,
        );
        deleted ? events.add(event) : events.insert(0, event);
      }
      return events;
    case EntityKind.account:
      if (rest.isNotEmpty || deleted == null) return null;
      return [
        lifecycle(
          EventType.accountDeleted,
          EventType.accountRestored,
          'accountId',
        ),
      ];
    case EntityKind.categoryGroup:
      if (rest.isNotEmpty || deleted == null) return null;
      return [
        lifecycle(
          EventType.categoryGroupDeleted,
          EventType.categoryGroupRestored,
          'categoryGroupId',
        ),
      ];
    case EntityKind.budget:
      if (deleted != null || rest.keys.any((k) => k != priorityField)) {
        return null;
      }
      return [
        (EventType.prioritySet, {'categoryIds': rest[priorityField] ?? []}),
      ];
    case EntityKind.schedule:
      final key = 'scheduleId';
      if (rest.isNotEmpty) {
        events.add((
          EventType.scheduleFieldsSet,
          {key: entity.id, 'fields': rest},
        ));
      }
      if (deleted == null) return events;
      final event = lifecycle(
        EventType.scheduleDeleted,
        EventType.scheduleRestored,
        key,
      );
      deleted ? events.add(event) : events.insert(0, event);
      return events;
    case EntityKind.businessTag:
      // A custom tag has no delete, so creating one can't be undone. Its
      // business-use % can.
      if (deleted != null || rest.isEmpty) return null;
      final percentEvents = <PlannedEvent>[];
      for (final MapEntry(key: field, value: percent) in rest.entries) {
        if (!field.startsWith(businessUseField)) return null;
        final year = int.tryParse(field.substring(businessUseField.length));
        if (year == null) return null;
        percentEvents.add((
          EventType.businessUseSet,
          {'tag': entity.id, 'year': year, 'percent': percent},
        ));
      }
      return percentEvents;
  }
}

/// The Event that adds [cents] to [entity]'s total under [key], or null
/// when the entity has no such total.
PlannedEvent? writeDelta(EntityRef entity, String key, int cents) =>
    switch (entity.kind) {
      EntityKind.category => (
        EventType.assignmentChanged,
        {'category': entity.id, 'month': key, 'deltaCents': cents},
      ),
      _ => null,
    };
