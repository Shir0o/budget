import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'actor.dart';
import 'budget_state.dart';
import 'civil_date.dart';
import 'commands.dart';
import 'event.dart';
import 'event_log.dart';
import 'hlc.dart';
import 'money.dart';
import 'sensitive_numbers.dart';

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

  Actor get actor => _engine.actor;

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
          // It is the bank's balance on that date.
          cleared: ClearedStatus.cleared,
        ),
      ]);

    case RecordIncome(:final accountId, :final amount):
      if (state.account(accountId) == null) {
        return const Rejected(Rejection.unknownAccount);
      }
      if (!amount.isPositive) {
        return const Rejected(Rejection.incomeMustBePositive);
      }
      if (_checkText([command.payee]) case final rejected?) return rejected;
      return Accepted([
        _income(
          stamp,
          accountId: accountId,
          amount: amount,
          date: command.date,
          payee: command.payee.trim(),
        ),
      ]);

    case CreateTransaction(:final accountId, :final amount, :final lines):
      if (state.account(accountId) == null) {
        return const Rejected(Rejection.unknownAccount);
      }
      if (_checkText([command.payee, command.memo]) case final rejected?) {
        return rejected;
      }
      if (_checkLines(state, amount, lines) case final rejected?) {
        return rejected;
      }
      return Accepted([
        stamp.event(EventType.transactionCreated, {
          'transactionId': newId(),
          'accountId': accountId,
          'date': command.date.toIso(),
          'payee': command.payee.trim(),
          'memo': command.memo.trim(),
          'cleared': ClearedStatus.uncleared.name,
          'amountCents': amount.cents,
          'lines': [for (final line in lines) _lineJson(line, stamp.actor)],
        }),
      ]);

    case EditTransaction():
      return _editTransaction(command, state, stamp);

    case DeleteTransaction(:final transactionId):
      if (state.transaction(transactionId) == null) {
        return const Rejected(Rejection.unknownTransaction);
      }
      return Accepted([
        stamp.event(EventType.transactionDeleted, {
          'transactionId': transactionId,
        }),
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
  ClearedStatus cleared = ClearedStatus.uncleared,
}) => stamp.event(EventType.transactionCreated, {
  'transactionId': newId(),
  'accountId': accountId,
  'date': date.toIso(),
  'payee': payee,
  'memo': '',
  'cleared': cleared.name,
  'amountCents': amount.cents,
  'lines': [
    _lineJson(
      LineInput(amount: amount, category: readyToAssignCategory),
      stamp.actor,
    ),
  ],
});

const _accountNumber = Rejected(Rejection.accountNumberNotAllowed);

/// Rejects payees and memos that look like a card or account number
/// (ticket 09).
Rejected? _checkText(Iterable<String?> texts) =>
    texts.any((t) => t != null && containsSensitiveNumber(t))
    ? _accountNumber
    : null;

/// Checks a transaction's [lines] against its [amount]. A line may keep a
/// Category in [kept] even if it has since been archived.
Rejected? _checkLines(
  BudgetState state,
  Money amount,
  List<LineInput> lines, {
  Set<String?> kept = const {},
}) {
  if (amount == Money.zero) return const Rejected(Rejection.zeroAmount);
  if (lines.isEmpty) return const Rejected(Rejection.noLines);
  final sum = lines.fold(Money.zero, (total, line) => total + line.amount);
  if (sum != amount) return const Rejected(Rejection.splitDoesNotSum);
  for (final line in lines) {
    final category = line.category;
    if (category != null &&
        category != readyToAssignCategory &&
        !kept.contains(category)) {
      if (_checkActive(state, category) case final rejected?) return rejected;
    }
    if (line.business case Business(:final tag) when tag.trim().isEmpty) {
      return const Rejected(Rejection.businessTagRequired);
    }
  }
  return _checkText(lines.map((line) => line.memo));
}

/// A stored line. It is Reviewed when a person set both its category and
/// its business status (ticket 09, ADR 0003).
Map<String, Object?> _lineJson(LineInput line, Actor actor) {
  final business = switch (line.business) {
    Business(:final tag) => Business(tag.trim()),
    final other => other,
  };
  return {
    'lineId': line.id ?? newId(),
    'amountCents': line.amount.cents,
    'category': line.category,
    ...?business?.toJson(),
    'memo': line.memo.trim(),
    'reviewed': actor.isPerson && line.category != null && business != null,
  };
}

/// [line] as an edit would resubmit it.
LineInput _asInput(TransactionLine line) => LineInput(
  id: line.id,
  amount: line.amount,
  category: line.category,
  business: line.business,
  memo: line.memo,
);

/// The stored form of a projected line, to tell whether an edit changed it.
Map<String, Object?> _storedLine(TransactionLine line) => {
  'lineId': line.id,
  'amountCents': line.amount.cents,
  'category': line.category,
  ...?line.business?.toJson(),
  'memo': line.memo,
  'reviewed': line.reviewed,
};

CommandResult _editTransaction(
  EditTransaction command,
  BudgetState state,
  _Stamp stamp,
) {
  final transaction = state.transaction(command.transactionId);
  if (transaction == null) {
    return const Rejected(Rejection.unknownTransaction);
  }
  if (_checkText([command.payee, command.memo]) case final rejected?) {
    return rejected;
  }
  final fields = <String, Object?>{
    if (command.payee?.trim() case final payee? when payee != transaction.payee)
      'payee': payee,
    if (command.date case final date? when date != transaction.date)
      'date': date.toIso(),
    if (command.memo?.trim() case final memo? when memo != transaction.memo)
      'memo': memo,
    if (command.cleared case final cleared? when cleared != transaction.cleared)
      'cleared': cleared.name,
  };
  final events = [
    if (fields.isNotEmpty)
      stamp.event(EventType.transactionFieldsSet, {
        'transactionId': transaction.id,
        'fields': fields,
      }),
  ];
  if (command.amount != null || command.lines != null) {
    final amount = command.amount ?? transaction.amount;
    final lines = command.lines ?? transaction.lines.map(_asInput).toList();
    final kept = {for (final line in transaction.lines) line.category};
    if (_checkLines(state, amount, lines, kept: kept) case final rejected?) {
      return rejected;
    }
    final stored = [for (final line in lines) _lineJson(line, stamp.actor)];
    if (amount != transaction.amount ||
        jsonEncode(stored) !=
            jsonEncode(transaction.lines.map(_storedLine).toList())) {
      events.add(
        stamp.event(EventType.transactionSplitSet, {
          'transactionId': transaction.id,
          'amountCents': amount.cents,
          'lines': stored,
        }),
      );
    }
  }
  if (events.isEmpty) return const Rejected(Rejection.noChange);
  return Accepted(events);
}
