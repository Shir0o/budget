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
  }
}

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
