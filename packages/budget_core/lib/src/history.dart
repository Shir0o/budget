import 'actor.dart';
import 'civil_date.dart';
import 'commands.dart';
import 'event.dart';
import 'event_effects.dart';
import 'hlc.dart';
import 'money.dart';
import 'target.dart';

part 'history_restore.dart';

/// One before → after value in a Change History entry, ready to show.
/// [before] is null for something new; [after] is null when there is no
/// single after value to show.
final class HistoryChange {
  const HistoryChange(this.label, {this.before, this.after, this.note});

  /// What changed, such as `Memo` or `Groceries · Nov 2026`.
  final String label;
  final String? before;
  final String? after;

  /// Why this value lost, such as [overwrittenBySync]. Null when it stands.
  final String? note;

  @override
  String toString() =>
      '$label: $before → $after${note == null ? '' : ' ($note)'}';
}

/// The note on a value another device's Event replaced (ticket 06).
const overwrittenBySync = 'overwritten by sync';

/// One Event group in Change History (ticket 11).
final class HistoryEntry {
  HistoryEntry._({
    required this.groupId,
    required this.events,
    required this.summary,
    required this.changes,
    required this.entities,
    required this.reverts,
    required this.by,
    required this.canRevert,
    required this.isRedo,
  });

  final String groupId;

  /// The group's Events, in HLC order.
  final List<Event> events;

  /// A plain-language summary, such as `Moved $40.00 Dining out →
  /// Groceries`.
  final String summary;

  /// Before and after values, in Event order.
  final List<HistoryChange> changes;

  /// Everything the group touched, for per-entity history: what it changed,
  /// what it refers to, and a transaction's account and Categories.
  final Set<EntityRef> entities;

  /// For a revert group, the groups it reverts, the chosen one first.
  /// Empty otherwise.
  final List<String> reverts;

  /// For a revert or Restore to a date group, the Actor who asked for it.
  final Actor? by;

  /// Whether compensating Events can be written for it. Budget creation and
  /// Event types this version doesn't know can't be reverted.
  final bool canRevert;

  /// The revert group currently undoing this one, or null. A redo clears
  /// it.
  String? get revertedBy => _revertedBy;
  String? _revertedBy;

  Actor get actor => events.first.actor;
  String get deviceId => events.first.deviceId;
  Hlc get hlc => events.first.hlc;

  /// Local wall time of the group's first Event.
  DateTime get time => DateTime.fromMillisecondsSinceEpoch(hlc.wallMs);

  bool get isRevert => reverts.isNotEmpty;

  /// A revert group that redoes: it reverts a revert.
  final bool isRedo;
}

/// Which entries [ChangeHistory.entries] lists. Null fields don't filter.
final class HistoryFilter {
  const HistoryFilter({
    this.entity,
    this.actors,
    this.from,
    this.until,
    this.types,
  });

  /// Only entries that touched this entity.
  final EntityRef? entity;

  /// Only entries made by these kinds of Actor. A revert counts for the
  /// Actor who asked for it too.
  final Set<ActorKind>? actors;

  /// Only entries at or after [from] and before [until].
  final DateTime? from;
  final DateTime? until;

  /// Only entries with an Event of one of these [EventType]s.
  final Set<String>? types;

  bool matches(HistoryEntry entry) {
    if (entity case final entity? when !entry.entities.contains(entity)) {
      return false;
    }
    if (actors case final actors?
        when !actors.contains(entry.actor.kind) &&
            !actors.contains(entry.by?.kind)) {
      return false;
    }
    if (from case final from? when entry.time.isBefore(from)) return false;
    if (until case final until? when !entry.time.isBefore(until)) return false;
    if (types case final types?
        when !entry.events.any((e) => types.contains(e.type))) {
      return false;
    }
    return true;
  }
}

/// A field a revert would restore that was set again later.
typedef FieldRef = ({EntityRef entity, String field});

/// "Field changed again later by X. Revert anyway (restore old value) or
/// skip this field?" (ticket 11).
final class FieldConflict {
  const FieldConflict._({
    required this.ref,
    required this.description,
    required this.laterChange,
    required this.laterBefore,
    required this.laterAfter,
    required this.restores,
  });

  /// Pass it in [RevertGroup.skipFields] to skip this field.
  final FieldRef ref;

  /// Such as `Memo of Corner Bistro −48.20`.
  final String description;

  /// The latest later change to the field.
  final HistoryEntry laterChange;
  final String laterBefore;
  final String laterAfter;

  /// The value "Revert anyway" restores.
  final String restores;
}

/// What reverting a group would run into, from [ChangeHistory.planRevert].
/// Run it before [RevertGroup] so the prompts can be shown.
final class RevertPlan {
  const RevertPlan._({
    required this.entry,
    required this.rejection,
    required this.fieldConflicts,
    required this.dependents,
  });

  final HistoryEntry entry;

  /// Why it can't be reverted at all, or null.
  final Rejection? rejection;

  /// Fields set again later. Each is reverted anyway unless skipped.
  final List<FieldConflict> fieldConflicts;

  /// Later groups that depend on something this group created. The revert
  /// needs [RevertGroup.includeDependents] to revert them too.
  final List<HistoryEntry> dependents;

  /// Nothing conflicts, so the revert can apply right away.
  bool get appliesRightAway =>
      rejection == null && fieldConflicts.isEmpty && dependents.isEmpty;
}

/// The Events a revert appends after its [EventType.groupReverted] marker,
/// or why it can't.
typedef Compensation = ({Rejection? rejection, List<PlannedEvent> events});

/// Change History: every Event group, with summaries, before and after
/// values, and revert (ticket 11). A pure function of the Event log.
final class ChangeHistory {
  factory ChangeHistory.of(Iterable<Event> events) {
    final history = ChangeHistory._();
    final ordered = events.toList()..sort((a, b) => a.hlc.compareTo(b.hlc));
    for (final event in ordered) {
      history._record(event);
    }
    history._markOverwritten();
    for (final group in history._groups.values) {
      history._entries[group.id] = history._entry(group);
    }
    history._settleReverts();
    return history;
  }

  ChangeHistory._();

  final _groups = <String, _Group>{};
  final _entries = <String, HistoryEntry>{};
  final _records = <_Record>[];
  final _platforms = <String, String>{};

  /// Each entity's current fields, as the Events so far set them.
  final _values = <EntityRef, Map<String, Object?>>{};

  /// Running totals of [AddsDelta] effects, by entity then key.
  final _totals = <EntityRef, Map<String, int>>{};

  /// Entries newest first.
  List<HistoryEntry> entries({HistoryFilter filter = const HistoryFilter()}) =>
      [
        for (final entry in _entries.values.toList().reversed)
          if (filter.matches(entry)) entry,
      ];

  HistoryEntry? entry(String groupId) => _entries[groupId];

  /// The platform (`android` or `mac`) of the person who used [deviceId],
  /// or null if no person has.
  String? devicePlatform(String deviceId) => _platforms[deviceId];

  /// The field conflicts and dependents reverting [groupId] runs into.
  /// Null for an unknown group.
  RevertPlan? planRevert(String groupId) {
    final entry = _entries[groupId];
    if (entry == null) return null;
    final rejection = _whyNot(groupId);
    if (rejection != null) {
      return RevertPlan._(
        entry: entry,
        rejection: rejection,
        fieldConflicts: const [],
        dependents: const [],
      );
    }
    final set = _revertSet(groupId);
    final dependents = [for (final group in set.skip(1)) _entries[group.id]!];
    return RevertPlan._(
      entry: entry,
      rejection: dependents.any((d) => !d.canRevert)
          ? Rejection.cannotRevert
          : null,
      fieldConflicts: _conflicts(set),
      dependents: dependents,
    );
  }

  /// The Events that revert as [command] asks, [by] the Actor asking.
  Compensation compensate(RevertGroup command, {required Actor by}) {
    Compensation rejected(Rejection reason) =>
        (rejection: reason, events: const []);
    if (!_entries.containsKey(command.groupId)) {
      return rejected(Rejection.unknownGroup);
    }
    if (_whyNot(command.groupId) case final reason?) return rejected(reason);
    final set = _revertSet(command.groupId);
    if (set.length > 1 && !command.includeDependents) {
      return rejected(Rejection.hasDependents);
    }
    final events = _compensations(set, skip: command.skipFields);
    if (events == null) return rejected(Rejection.cannotRevert);
    if (events.isEmpty) return rejected(Rejection.noChange);
    return (
      rejection: null,
      events: [
        (
          EventType.groupReverted,
          {
            'groupIds': [for (final group in set) group.id],
            'by': by.value,
          },
        ),
        ...events,
      ],
    );
  }

  // Recording -------------------------------------------------------------

  void _record(Event event) {
    if (event.actor.isPerson) {
      _platforms[event.deviceId] = event.actor.value.substring('user@'.length);
    }
    final group = _groups.putIfAbsent(
      event.groupId,
      () => _Group(event.groupId),
    );
    final spec = eventSpecs[event.type];
    if (spec == null) {
      final record = _Record(event, null, const {}, const {});
      group.records.add(record);
      _records.add(record);
      return;
    }
    final applied = <_Applied>[];
    final implied = <EntityRef>{};
    for (final effect in spec.effects(event.payload)) {
      final entity = effect.entity;
      final values = _values.putIfAbsent(entity, () => {});
      final snapshot = {...values};
      switch (effect) {
        case Creates(:final fields):
          applied.add(_Applied(effect, const {}, values: snapshot));
          values
            ..addAll(fields)
            ..[deletedField] = false;
        case SetsFields(:final fields):
          final before = {
            for (final field in fields.keys) field: values[field],
          };
          applied.add(_Applied(effect, before, values: snapshot));
          values.addAll(fields);
        case AddsDelta(:final key, :final cents):
          final totals = _totals.putIfAbsent(entity, () => {});
          final total = totals[key] ?? 0;
          applied.add(
            _Applied(effect, const {}, values: snapshot, total: total),
          );
          totals[key] = total + cents;
      }
      if (entity.kind == EntityKind.transaction) {
        if (values['accountId'] case final String account) {
          implied.add(EntityRef.account(account));
        }
        implied
          ..addAll(_splitCategories(snapshot[splitField]))
          ..addAll(_splitCategories(values[splitField]));
      }
    }
    final record = _Record(
      event,
      applied,
      spec.references(event.payload).toSet(),
      implied,
    );
    group.records.add(record);
    _records.add(record);
  }

  /// For each record, the fields a later Event from another device replaced.
  final _overwritten = <_Record, Set<String>>{};

  /// Marks every value another device's Event replaced, so the losing value
  /// reads as [overwrittenBySync] (ticket 06). The rule is the merge rule
  /// itself: per field the highest HLC wins, and a write on another device
  /// means the value came from sync rather than from this device's hand.
  void _markOverwritten() {
    final last = <(EntityRef, String), _Record>{};
    for (final record in _records) {
      for (final applied in record.applied ?? const <_Applied>[]) {
        switch (applied.effect) {
          case Creates(:final entity, :final fields):
            for (final field in fields.keys) {
              last[(entity, field)] = record;
            }
          case SetsFields(:final entity, :final fields):
            for (final MapEntry(key: field, value: _) in fields.entries) {
              final previous = last[(entity, field)];
              if (previous != null &&
                  previous.event.deviceId != record.event.deviceId) {
                (_overwritten[previous] ??= {}).add(field);
              }
              last[(entity, field)] = record;
            }
          // Deltas add up instead of replacing, so nothing is overwritten.
          case AddsDelta():
        }
      }
    }
  }

  String? _note(_Record record, String field) =>
      _overwritten[record]?.contains(field) == true ? overwrittenBySync : null;

  /// Builds [group]'s entry. Groups it reverts were built before it.
  HistoryEntry _entry(_Group group) {
    final described = [for (final record in group.records) ?_describe(record)];
    Event? find(String type) => group.records
        .map((r) => r.event)
        .where((e) => e.type == type)
        .firstOrNull;
    final marker = find(EventType.groupReverted);
    final restore = find(EventType.restoredToDate);
    final reverts = [
      ...?(marker?.payload['groupIds'] as List?)?.cast<String>(),
    ];
    final entities = <EntityRef>{
      for (final record in group.records) ...record.entities,
    };
    final canRevert =
        group.records.every((r) => r.applied != null) &&
        _compensations([group]) != null;
    final (target, undo) = _undone(reverts);
    return HistoryEntry._(
      groupId: group.id,
      events: [for (final record in group.records) record.event],
      summary: restore != null
          ? 'Restored to ${_date(restore.payload['date'] as String)}'
          : reverts.isEmpty
          ? _summarize(group, described)
          : '${undo ? 'Undid' : 'Redid'} “${target?.summary ?? 'a change'}”'
                '${_more(reverts.length - 1, 'later change')}',
      changes: [for (final d in described) ...d.changes],
      entities: entities,
      reverts: reverts,
      by: switch ((marker ?? restore)?.payload['by']) {
        final String by => Actor.fromValue(by),
        _ => null,
      },
      canRevert: canRevert,
      isRedo: reverts.isNotEmpty && !undo,
    );
  }

  /// The original change at the end of a chain of reverts, and whether
  /// reverting [reverts] undoes it (rather than redoing it).
  (HistoryEntry?, bool) _undone(List<String> reverts) {
    if (reverts.isEmpty) return (null, false);
    var target = _entries[reverts.first];
    var undo = true;
    while (target != null && target.isRevert) {
      undo = !undo;
      target = _entries[target.reverts.first];
    }
    return (target, undo);
  }

  // Reverts ---------------------------------------------------------------

  /// For each group, the revert group that last named it.
  final _namedBy = <String, String>{};
  final _reverted = <String, bool>{};

  void _settleReverts() {
    for (final entry in _entries.values) {
      for (final target in entry.reverts) {
        _namedBy[target] = entry.groupId;
      }
    }
    for (final entry in _entries.values) {
      entry._revertedBy = _isReverted(entry.groupId)
          ? _namedBy[entry.groupId]
          : null;
    }
  }

  /// Reverted by a revert group that is not itself reverted.
  bool _isReverted(String groupId) =>
      _reverted[groupId] ??= switch (_namedBy[groupId]) {
        final by? => !_isReverted(by),
        null => false,
      };

  /// A group whose effect is cancelled out: reverted, or a revert in force
  /// (whose target is then reverted). Settled groups never conflict.
  bool _settled(String groupId) =>
      _isReverted(groupId) || _entries[groupId]!.isRevert;

  Rejection? _whyNot(String groupId) {
    if (_isReverted(groupId)) return Rejection.alreadyReverted;
    if (!_entries[groupId]!.canRevert) return Rejection.cannotRevert;
    return null;
  }

  /// [groupId], then every later live group that depends on an entity one
  /// of them created or restored, in HLC order.
  List<_Group> _revertSet(String groupId) {
    final first = _groups[groupId]!;
    final set = [first];
    final ids = {groupId};
    final born = {for (final record in first.records) ...record.born};
    final start = _records.indexOf(first.records.first);
    for (final record in _records.skip(start)) {
      final id = record.event.groupId;
      if (ids.contains(id) || _settled(id)) continue;
      if (!record.touches.any(born.contains)) continue;
      final group = _groups[id]!;
      set.add(group);
      ids.add(id);
      for (final r in group.records) {
        born.addAll(r.born);
      }
    }
    return set;
  }

  /// For each in-set field write, the later writes outside [set] to the
  /// same field that are still in force. Keyed by the in-set record, then
  /// the field.
  Map<_Record, Map<FieldRef, _Record>> _laterWrites(List<_Group> set) {
    final ids = {for (final group in set) group.id};
    final result = <_Record, Map<FieldRef, _Record>>{};
    final pending = <FieldRef, List<_Record>>{};
    for (final record in _records) {
      final inSet = ids.contains(record.event.groupId);
      for (final applied in record.applied ?? const <_Applied>[]) {
        if (applied.effect case SetsFields(:final entity, :final fields)) {
          for (final field in fields.keys) {
            final ref = (entity: entity, field: field);
            if (inSet) {
              (pending[ref] ??= []).add(record);
              continue;
            }
            for (final earlier in pending[ref] ?? const <_Record>[]) {
              if (_cancelledSince(record.event.groupId, earlier.event.hlc)) {
                continue;
              }
              (result[earlier] ??= {})[ref] = record;
            }
          }
        }
      }
    }
    return result;
  }

  /// Whether [groupId]'s effect is cancelled by Events after [since]: it
  /// was reverted (later still), or it is a revert in force of groups that
  /// all came after [since].
  bool _cancelledSince(String groupId, Hlc since) {
    if (_isReverted(groupId)) return true;
    final reverts = _entries[groupId]!.reverts;
    return reverts.isNotEmpty &&
        reverts.every(
          (t) => _groups[t]!.records.first.event.hlc.compareTo(since) > 0,
        );
  }

  List<FieldConflict> _conflicts(List<_Group> set) {
    final later = _laterWrites(set);
    final byRef = <FieldRef, (_Record earliest, _Record latest)>{};
    for (final MapEntry(key: record, value: refs) in later.entries) {
      for (final MapEntry(key: ref, value: write) in refs.entries) {
        final found = byRef[ref];
        byRef[ref] = (
          found == null || record.event.hlc.compareTo(found.$1.event.hlc) < 0
              ? record
              : found.$1,
          found == null || write.event.hlc.compareTo(found.$2.event.hlc) > 0
              ? write
              : found.$2,
        );
      }
    }
    return [
      for (final MapEntry(key: ref, value: (earliest, latest)) in byRef.entries)
        _conflict(ref, earliest, latest),
    ];
  }

  FieldConflict _conflict(FieldRef ref, _Record earliest, _Record latest) {
    _Applied write(_Record record) => record.applied!.firstWhere(
      (a) =>
          a.effect is SetsFields &&
          a.effect.entity == ref.entity &&
          (a.effect as SetsFields).fields.containsKey(ref.field),
    );
    final restored = write(earliest);
    final later = write(latest);
    final laterAfter = (later.effect as SetsFields).fields[ref.field];
    return FieldConflict._(
      ref: ref,
      description:
          '${_fieldName(ref.field)} of '
          '${_label(ref.entity, restored.values)}',
      laterChange: _entries[latest.event.groupId]!,
      laterBefore: _show(ref.field, later.before[ref.field]),
      laterAfter: _show(ref.field, laterAfter),
      restores: _show(ref.field, restored.before[ref.field]),
    );
  }

  /// Undoes [set]'s Events, latest first. Null if one can't be undone.
  List<PlannedEvent>? _compensations(
    List<_Group> set, {
    Set<FieldRef> skip = const {},
  }) {
    final later = skip.isEmpty ? const {} : _laterWrites(set);
    final records = [for (final group in set) ...group.records]
      ..sort((a, b) => b.event.hlc.compareTo(a.event.hlc));
    final events = <PlannedEvent>[];
    for (final record in records) {
      final applied = record.applied;
      if (applied == null) return null;
      for (final a in applied.reversed) {
        final entity = a.effect.entity;
        switch (a.effect) {
          case Creates():
            final written = writeFields(entity, {deletedField: true});
            if (written == null) return null;
            events.addAll(written);
          case SetsFields():
            final conflicting = later[record] ?? const {};
            final before = {
              for (final MapEntry(:key, :value) in a.before.entries)
                if (!(skip.contains((entity: entity, field: key)) &&
                    conflicting.containsKey((entity: entity, field: key))))
                  key: value,
            };
            if (before.isEmpty) continue;
            final written = writeFields(entity, before);
            if (written == null) return null;
            events.addAll(written);
          case AddsDelta(:final key, :final cents):
            final written = writeDelta(entity, key, -cents);
            if (written == null) return null;
            events.add(written);
        }
      }
    }
    return events;
  }

  // Summaries -------------------------------------------------------------

  _Described? _describe(_Record record) {
    final applied = record.applied;
    if (applied == null || applied.isEmpty) return null;
    final a = applied.first;
    final entity = a.effect.entity;
    final values = a.values;
    final label = _label(entity, {...values, ...a.before});
    switch (a.effect) {
      case Creates():
        final what = switch (entity.kind) {
          EntityKind.budget => 'budget',
          EntityKind.account => 'account',
          EntityKind.categoryGroup => 'category group',
          EntityKind.category => 'category',
          EntityKind.transaction => null,
          EntityKind.schedule => 'scheduled transaction',
          EntityKind.businessTag => 'business tag',
        };
        final created = _label(entity, (a.effect as Creates).fields);
        return _Described(
          what == null ? 'Added $created' : 'Added $what $created',
          [
            if (entity.kind == EntityKind.transaction)
              HistoryChange(
                'Lines',
                after: _show(
                  splitField,
                  (a.effect as Creates).fields[splitField],
                ),
              ),
          ],
        );
      case SetsFields(:final fields):
        if (fields.length == 1 &&
            (fields.containsKey(deletedField) ||
                fields.containsKey(archivedField))) {
          final value = fields.values.single == true;
          final verb = fields.containsKey(archivedField)
              ? (value ? 'Archived' : 'Unarchived')
              : (value ? 'Deleted' : 'Restored');
          final what = switch (entity.kind) {
            EntityKind.account => 'account ',
            EntityKind.categoryGroup => 'category group ',
            _ => '',
          };
          return _Described('$verb $what$label', const []);
        }
        if (fields.containsKey(splitField)) {
          return _describeSplit(
            label,
            a.before[splitField],
            fields[splitField],
            note: _note(record, splitField),
          );
        }
        final names = [for (final field in fields.keys) field];
        return _Described(
          names.length == 1
              ? 'Set ${names.single} of $label'
              : 'Changed ${_list(names)} of $label',
          [
            for (final field in names)
              HistoryChange(
                _fieldName(field),
                before: _show(field, a.before[field]),
                after: _show(field, fields[field]),
                note: _note(record, field),
              ),
          ],
        );
      case AddsDelta(:final key, :final cents):
        return _Described(
          cents >= 0
              ? 'Assigned ${Money(cents).formatDollars()} to $label'
              : 'Removed ${Money(-cents).formatDollars()} from $label',
          [
            HistoryChange(
              '$label · ${_month(key)}',
              before: Money(a.total).format(),
              after: Money(a.total + cents).format(),
            ),
          ],
        );
    }
  }

  _Described _describeSplit(
    String label,
    Object? before,
    Object? after, {
    String? note,
  }) {
    final b = before as Map?;
    final a = after as Map;
    final bLines = (b?['lines'] as List?)?.cast<Map>() ?? const [];
    final aLines = (a['lines'] as List).cast<Map>();
    final changes = <HistoryChange>[];
    final changed = <String>[];
    if (b?['amountCents'] != a['amountCents']) {
      changed.add('amount');
      changes.add(
        HistoryChange(
          'Amount',
          before: b == null ? null : _signed(b['amountCents'] as int),
          after: _signed(a['amountCents'] as int),
          note: note,
        ),
      );
    }
    if (bLines.length == 1 && aLines.length == 1) {
      final checks = <(String, String, String Function(Map))>[
        ('category', 'Category', (l) => _categoryName(l['category'])),
        ('business', 'Business', _business),
        ('memo', 'Line memo', (l) => _show('memo', l['memo'] ?? '')),
        ('reviewed', 'Reviewed', (l) => l['reviewed'] == true ? 'Yes' : 'No'),
      ];
      for (final (key, name, show) in checks) {
        final (x, y) = (show(bLines.single), show(aLines.single));
        if (x == y) continue;
        changed.add(key);
        changes.add(HistoryChange(name, before: x, after: y, note: note));
      }
    } else if (_show(splitField, b) != _show(splitField, a) ||
        changes.isEmpty) {
      changed.add('lines');
      changes.add(
        HistoryChange(
          'Lines',
          before: b == null ? null : _show(splitField, b),
          after: _show(splitField, a),
          note: note,
        ),
      );
    }
    final sentence = aLines.length > 1 && bLines.length != aLines.length
        ? 'Split $label into ${aLines.length} lines'
        : switch (changed) {
            ['amount'] => 'Changed amount of $label',
            ['category'] =>
              'Set category of $label to '
                  '${_categoryName(aLines.single['category'])}',
            ['business'] => 'Set business status of $label',
            ['memo'] => 'Set line memo of $label',
            ['reviewed'] when aLines.single['reviewed'] == true =>
              'Marked $label Reviewed',
            _ => 'Changed lines of $label',
          };
    return _Described(sentence, changes);
  }

  String _summarize(_Group group, List<_Described> described) {
    final records = group.records;
    if (records.any((r) => r.applied == null)) {
      return 'A change this version of the app doesn’t know';
    }
    if (described.length == 1) return described.single.sentence;
    final effects = [
      for (final r in records)
        for (final a in r.applied!) a.effect,
    ];
    if (effects.every((e) => e is AddsDelta)) {
      final deltas = effects.cast<AddsDelta>();
      if (deltas.length == 2 &&
          deltas[0].key == deltas[1].key &&
          deltas[0].cents == -deltas[1].cents) {
        final from = deltas.firstWhere((d) => d.cents < 0);
        final to = deltas.firstWhere((d) => d.cents > 0);
        return 'Moved ${Money(to.cents).formatDollars()} '
            '${_label(from.entity, _values[from.entity]!)} → '
            '${_label(to.entity, _values[to.entity]!)}';
      }
      if (deltas.every((d) => d.cents > 0)) {
        final total = deltas.fold(0, (sum, d) => sum + d.cents);
        return 'Assigned ${Money(total).formatDollars()} to '
            '${deltas.map((d) => d.entity).toSet().length} categories';
      }
      return 'Changed ${deltas.length} Assignments';
    }
    if (records.every((r) => r.event.type == EventType.transactionCreated)) {
      return 'Added ${records.length} transactions';
    }
    if (effects.map((e) => e.entity).toSet().length == 1 &&
        effects.first.entity.kind == EntityKind.transaction) {
      final a = records.first.applied!.first;
      return 'Edited ${_label(a.effect.entity, {...a.values, ...a.before})}';
    }
    if (effects.first is Creates) return described.first.sentence;
    return '${described.first.sentence}'
        '${_more(described.length - 1, 'more change')}';
  }

  /// How an entity reads in a summary: a name, or a transaction's payee
  /// and amount (`Corner Bistro −48.20`), or a Scheduled Transaction's
  /// payee.
  String _label(EntityRef entity, Map<String, Object?> values) {
    if (entity.kind == EntityKind.schedule) {
      final payee =
          values['payee'] as String? ??
          _values[entity]?['payee'] as String? ??
          '';
      return payee.isEmpty ? 'Scheduled transaction' : payee;
    }
    if (entity.kind == EntityKind.businessTag) {
      // A preset tag is never created, so its id (its name) is the label.
      return values['name'] as String? ??
          _values[entity]?['name'] as String? ??
          entity.id;
    }
    if (entity.kind != EntityKind.transaction) {
      return values['name'] as String? ??
          _values[entity]?['name'] as String? ??
          '';
    }
    final payee = values['payee'] as String? ?? '';
    final split = values[splitField] as Map?;
    final amount = split == null
        ? ''
        : ' ${_signed(split['amountCents'] as int)}';
    return '${payee.isEmpty ? 'Transaction' : payee}$amount';
  }

  String _categoryName(Object? id) => switch (id) {
    null => 'Uncategorized',
    readyToAssignCategory => 'Ready to Assign',
    final String id =>
      _values[EntityRef.category(id)]?['name'] as String? ?? 'Unknown',
    _ => 'Unknown',
  };

  String _business(Map line) => switch (line['business']) {
    'personal' => 'Personal',
    'business' => 'Business (${line['businessTag']})',
    _ => 'Not set',
  };

  /// A field's value as shown in history.
  String _show(String field, Object? value) {
    if (value == null) return 'empty';
    return switch (field) {
      'payee' || 'memo' => (value as String).isEmpty ? 'empty' : '“$value”',
      'date' || 'nextDue' => _date(value as String),
      'amountCents' => _signed(value as int),
      'category' => _categoryName(value),
      'accountId' =>
        _values[EntityRef.account(value as String)]?['name'] as String? ??
            'Unknown account',
      'cleared' => switch (value) {
        'cleared' => 'Cleared',
        'reconciled' => 'Reconciled',
        _ => 'Uncleared',
      },
      splitField => () {
        final split = value as Map;
        final lines = (split['lines'] as List).cast<Map>();
        final amount = _signed(split['amountCents'] as int);
        return lines.length == 1
            ? '$amount · ${_categoryName(lines.single['category'])}'
            : '$amount in ${lines.length} lines';
      }(),
      archivedField => value == true ? 'Archived' : 'Active',
      targetField => () {
        final target = Target.fromJson((value as Map).cast());
        return switch (target) {
          RepeatingTarget(:final amount) => '${amount.format()} repeating',
          ByDateTarget(:final amount, :final date) =>
            '${amount.format()} by ${_date(date.toIso())}',
          KeepAtLeastTarget(:final amount) =>
            '${amount.format()} kept at least',
          DrivenByScheduleTarget() => 'driven by schedule',
        };
      }(),
      automationModeField => switch (value) {
        'off' => 'Off',
        'auto' => 'Auto',
        _ => 'Suggest',
      },
      _ when field.startsWith(businessUseField) => '$value%',
      priorityField => '${(value as List).length} Categories in order',
      deletedField => value == true ? 'Deleted' : 'Kept',
      'bankId' => 'Linked',
      'pendingMatch' => 'Possible match',
      _ => '$value',
    };
  }

  static Set<EntityRef> _splitCategories(Object? split) => {
    if (split case final Map split)
      for (final line in (split['lines'] as List).cast<Map>())
        if (line['category'] case final String category
            when category != readyToAssignCategory)
          EntityRef.category(category),
  };
}

final class _Group {
  _Group(this.id);

  final String id;
  final records = <_Record>[];
}

final class _Record {
  _Record(this.event, this.applied, this.references, Set<EntityRef> implied)
    : entities = {
        for (final a in applied ?? const <_Applied>[]) a.effect.entity,
        ...references,
        ...implied,
      };

  final Event event;

  /// Null for an Event type this version doesn't know.
  final List<_Applied>? applied;
  final Set<EntityRef> references;
  final Set<EntityRef> entities;

  /// What the Event changed or needs. Used to find dependents.
  Iterable<EntityRef> get touches => [
    for (final a in applied ?? const <_Applied>[]) a.effect.entity,
    ...references,
  ];

  /// Entities the Event created or restored.
  Iterable<EntityRef> get born => [
    for (final a in applied ?? const <_Applied>[])
      if (a.effect is Creates ||
          (a.effect is SetsFields &&
              (a.effect as SetsFields).fields[deletedField] == false))
        a.effect.entity,
  ];
}

/// One effect as recorded, with what it replaced.
final class _Applied {
  _Applied(this.effect, this.before, {required this.values, this.total = 0});

  final Effect effect;

  /// For [SetsFields], each field's value before it.
  final Map<String, Object?> before;

  /// The entity's fields when the Event happened.
  final Map<String, Object?> values;

  /// For [AddsDelta], the total before it.
  final int total;
}

final class _Described {
  const _Described(this.sentence, this.changes);

  final String sentence;
  final List<HistoryChange> changes;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `2026-11` as `Nov 2026`.
String _month(String iso) {
  final [year, month] = iso.split('-');
  return '${_months[int.parse(month) - 1]} $year';
}

/// `2026-11-12` as `Nov 12, 2026`.
String _date(String iso) {
  final [year, month, day] = iso.split('-');
  return '${_months[int.parse(month) - 1]} ${int.parse(day)}, $year';
}

/// `+1,500.00` or `−48.20`.
String _signed(int cents) => '${cents > 0 ? '+' : ''}${Money(cents).format()}';

/// ` and 2 more changes`, or nothing for 0.
String _more(int count, String noun) =>
    count == 0 ? '' : ' and $count $noun${count == 1 ? '' : 's'}';

String _fieldName(String field) => switch (field) {
  splitField => 'Amount and lines',
  'amountCents' => 'Amount',
  'nextDue' => 'Next due',
  'accountId' => 'Account',
  'bankId' => 'Bank link',
  'pendingMatch' => 'Possible bank match',
  _ => '${field[0].toUpperCase()}${field.substring(1)}',
};

/// `payee, date and memo`.
String _list(List<String> names) => names.length == 1
    ? names.single
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
