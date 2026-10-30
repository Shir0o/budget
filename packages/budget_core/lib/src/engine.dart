import 'package:uuid/uuid.dart';

import 'actor.dart';
import 'budget_state.dart';
import 'civil_date.dart';
import 'commands.dart';
import 'event.dart';
import 'event_log.dart';
import 'hlc.dart';
import 'money.dart';

const _uuid = Uuid();

/// A new UUIDv7, used for Event, group and entity ids.
String newId() => _uuid.v7();

/// The one write path into a budget. It validates each [Command], appends
/// the resulting Event group to the [EventLog], and answers queries from
/// [state], a replay of the log.
final class BudgetEngine {
  BudgetEngine({
    required EventLog log,
    required this.deviceId,
    required this.actor,
    int Function()? nowMs,
  }) : _log = log,
       _events = log.readAll().toList() {
    _state = BudgetState.replay(_events);
    final latest = _events.isEmpty
        ? null
        : _events.reduce((a, b) => a.hlc.compareTo(b.hlc) >= 0 ? a : b).hlc;
    _clock = HlcClock(deviceId, nowMs: nowMs, last: latest);
  }

  final String deviceId;
  final Actor actor;
  final EventLog _log;
  final List<Event> _events;
  late final HlcClock _clock;
  late BudgetState _state;

  /// The budget as of the latest Event.
  BudgetState get state => _state;

  /// Every Event in the log, in HLC order.
  List<Event> get events => List.unmodifiable(_events);

  CommandResult execute(Command command) {
    final result = _decide(command, _state, _Stamp(this));
    if (result is Accepted) {
      _log.append(result.events);
      _events.addAll(result.events);
      _state = BudgetState.replay(_events);
    }
    return result;
  }
}

/// Fills in the Event envelope for one command's group.
final class _Stamp {
  _Stamp(this._engine) : budgetId = _engine.state.budget?.id ?? newId();

  final BudgetEngine _engine;
  final String budgetId;
  final String groupId = newId();

  Event event(String type, Map<String, Object?> payload) => Event(
    id: newId(),
    budgetId: budgetId,
    deviceId: _engine.deviceId,
    hlc: _engine._clock.tick(),
    actor: _engine.actor,
    groupId: groupId,
    type: type,
    payload: payload,
  );
}

CommandResult _decide(Command command, BudgetState state, _Stamp stamp) {
  if (command is! CreateBudget && state.budget == null) {
    return const Rejected(Rejection.noBudget);
  }
  switch (command) {
    case CreateBudget(:final name):
      if (state.budget != null) {
        return const Rejected(Rejection.budgetAlreadyExists);
      }
      if (name.trim().isEmpty) return const Rejected(Rejection.nameRequired);
      return Accepted([
        stamp.event(EventType.budgetCreated, {'name': name.trim()}),
      ]);

    case AddAccount(:final name, :final type, :final startingBalance):
      if (name.trim().isEmpty) return const Rejected(Rejection.nameRequired);
      final accountId = newId();
      return Accepted([
        stamp.event(EventType.accountCreated, {
          'accountId': accountId,
          'name': name.trim(),
          'accountType': type.name,
        }),
        _income(
          stamp,
          accountId: accountId,
          amount: startingBalance,
          date: command.asOf,
          payee: 'Starting Balance',
        ),
      ]);

    case RecordIncome(:final accountId, :final amount):
      if (state.account(accountId) == null) {
        return const Rejected(Rejection.unknownAccount);
      }
      if (!amount.isPositive) {
        return const Rejected(Rejection.incomeMustBePositive);
      }
      return Accepted([
        _income(
          stamp,
          accountId: accountId,
          amount: amount,
          date: command.date,
          payee: command.payee.trim(),
        ),
      ]);

    case CreateCategoryGroup(:final name):
      if (name.trim().isEmpty) return const Rejected(Rejection.nameRequired);
      return Accepted([
        stamp.event(EventType.categoryGroupCreated, {
          'categoryGroupId': newId(),
          'name': name.trim(),
        }),
      ]);

    case CreateCategory(:final groupId, :final name):
      if (state.categoryGroup(groupId) == null) {
        return const Rejected(Rejection.unknownCategoryGroup);
      }
      if (name.trim().isEmpty) return const Rejected(Rejection.nameRequired);
      return Accepted([
        stamp.event(EventType.categoryCreated, {
          'categoryId': newId(),
          'categoryGroupId': groupId,
          'name': name.trim(),
        }),
      ]);

    case SetAssignment(:final categoryId, :final month, :final amount):
      if (_checkActive(state, categoryId) case final rejected?) return rejected;
      final delta = amount - state.assigned(categoryId, month);
      if (delta == Money.zero) return const Rejected(Rejection.noChange);
      return Accepted([_assignment(stamp, categoryId, month, delta)]);

    case MoveMoney(
      :final fromCategoryId,
      :final toCategoryId,
      :final month,
      :final amount,
    ):
      if (_checkActive(state, fromCategoryId) case final rejected?) {
        return rejected;
      }
      final toReadyToAssign = toCategoryId == readyToAssignCategory;
      if (!toReadyToAssign) {
        if (_checkActive(state, toCategoryId) case final rejected?) {
          return rejected;
        }
      }
      if (fromCategoryId == toCategoryId) {
        return const Rejected(Rejection.sameCategory);
      }
      if (!amount.isPositive) {
        return const Rejected(Rejection.amountMustBePositive);
      }
      return Accepted([
        _assignment(stamp, fromCategoryId, month, -amount),
        if (!toReadyToAssign) _assignment(stamp, toCategoryId, month, amount),
      ]);

    case ArchiveCategory(:final categoryId, :final month):
      if (_checkActive(state, categoryId) case final rejected?) return rejected;
      // Available rolls over, so check the latest month that has money in
      // it, which may be after [month] when assigning ahead.
      final last = state.lastActiveMonth(categoryId);
      final checked = last != null && last.compareTo(month) > 0 ? last : month;
      if (state.available(categoryId, checked) != Money.zero) {
        return const Rejected(Rejection.categoryHasBalance);
      }
      return Accepted([
        stamp.event(EventType.categoryArchived, {'categoryId': categoryId}),
      ]);
  }
}

/// Rejects a Category that doesn't exist or is archived.
Rejected? _checkActive(BudgetState state, String categoryId) {
  final category = state.category(categoryId);
  if (category == null) return const Rejected(Rejection.unknownCategory);
  if (category.archived) return const Rejected(Rejection.categoryArchived);
  return null;
}

Event _assignment(
  _Stamp stamp,
  String categoryId,
  CalendarMonth month,
  Money delta,
) => stamp.event(EventType.assignmentChanged, {
  'category': categoryId,
  'month': month.toIso(),
  'deltaCents': delta.cents,
});

/// A one-line transaction whose money goes to Ready to Assign.
Event _income(
  _Stamp stamp, {
  required String accountId,
  required Money amount,
  required CivilDate date,
  required String payee,
}) => stamp.event(EventType.transactionCreated, {
  'transactionId': newId(),
  'accountId': accountId,
  'date': date.toIso(),
  'payee': payee,
  'amountCents': amount.cents,
  'lines': [
    {
      'lineId': newId(),
      'amountCents': amount.cents,
      'category': readyToAssignCategory,
    },
  ],
});
