import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'actor.dart';
import 'budget_state.dart';
import 'civil_date.dart';
import 'commands.dart';
import 'event.dart';
import 'event_log.dart';
import 'history.dart';
import 'hlc.dart';
import 'money.dart';
import 'review.dart';
import 'sensitive_numbers.dart';
import 'target.dart';

part 'engine_accounts.dart';
part 'engine_schedules.dart';
part 'engine_targets.dart';

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
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _events = log.readAll().toList() {
    _state = BudgetState.replay(_events);
    final latest = _events.isEmpty
        ? null
        : _events.reduce((a, b) => a.hlc.compareTo(b.hlc) >= 0 ? a : b).hlc;
    _clock = HlcClock(deviceId, nowMs: _nowMs, last: latest);
  }

  final String deviceId;
  final Actor actor;
  final EventLog _log;
  final int Function() _nowMs;
  final List<Event> _events;
  late final HlcClock _clock;
  late BudgetState _state;

  /// The budget as of the latest Event.
  BudgetState get state => _state;

  /// Every Event in the log, in HLC order.
  List<Event> get events => List.unmodifiable(_events);

  /// Change History as of the latest Event (ticket 11).
  ChangeHistory get history => _history ??= ChangeHistory.of(_events);
  ChangeHistory? _history;

  /// The budget as it was at the end of [date], read-only (ticket 11).
  BudgetState stateAsOf(CivilDate date) =>
      BudgetState.replay(eventsAsOf(_events, date));

  /// Runs [command]. A [RunAutomation] is recorded with actor
  /// `automation`. Reviewing an income line also starts an automation run
  /// for the current month, as its own group (ticket 08).
  CommandResult execute(Command command) {
    final before = _state;
    final result = _execute(command);
    if (result is Accepted &&
        command is! RunAutomation &&
        _reviewsIncome(before, result.events)) {
      final now = DateTime.fromMillisecondsSinceEpoch(_nowMs());
      _execute(
        RunAutomation(month: CalendarMonth.of(CivilDate.fromDateTime(now))),
      );
    }
    return result;
  }

  CommandResult _execute(Command command) {
    final stamp = _Stamp(
      this,
      command is RunAutomation ? Actor.automation : actor,
    );
    final result = _decide(command, _state, stamp);
    if (result is Accepted) {
      _log.append(result.events);
      _events.addAll(result.events);
      _state = BudgetState.replay(_events);
      _history = null;
    }
    return result;
  }
}

/// Fills in the Event envelope for one command's group.
final class _Stamp {
  _Stamp(this._engine, this.actor)
    : budgetId = _engine.state.budget?.id ?? newId();

  final BudgetEngine _engine;
  final String budgetId;
  final String groupId = newId();
  final Actor actor;

  Event event(String type, Map<String, Object?> payload, {Actor? actor}) =>
      Event(
        id: newId(),
        budgetId: budgetId,
        deviceId: _engine.deviceId,
        hlc: _engine._clock.tick(),
        actor: actor ?? this.actor,
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
        if (type == AccountType.creditCard)
          ..._cardPaymentCategory(state, stamp, accountId, name.trim()),
        if (type == AccountType.creditCard || !type.onBudget)
          _offBudgetStartingBalance(stamp, accountId, command)
        else
          _income(
            stamp,
            accountId: accountId,
            amount: startingBalance,
            date: command.asOf,
            payee: 'Starting Balance',
            // It is the bank's balance on that date.
            cleared: ClearedStatus.cleared,
            startingBalance: true,
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

    case Reconcile():
      return _reconcile(command, state, stamp);

    case EditTransaction():
      return _editTransaction(command, state, stamp);

    case CreateTransfer():
      return _createTransfer(command, state, stamp);

    case ReviewLine():
      return _reviewLine(command, state, stamp);

    case DeleteTransaction(:final transactionId):
      final transaction = state.transaction(transactionId);
      if (transaction == null) {
        return const Rejected(Rejection.unknownTransaction);
      }
      // Both sides of a transfer go together.
      final pair = transaction.transferTransactionId;
      return Accepted([
        for (final id in [transactionId, ?pair])
          if (state.transaction(id) != null)
            stamp.event(EventType.transactionDeleted, {'transactionId': id}),
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

    case RevertGroup():
      final compensation = stamp._engine.history.compensate(
        command,
        by: stamp.actor,
      );
      if (compensation.rejection case final reason?) return Rejected(reason);
      return Accepted([
        for (final (type, payload) in compensation.events)
          stamp.event(type, payload, actor: Actor.revert),
      ]);

    case RestoreToDate(:final date):
      final compensation = restoreTo(
        stamp._engine._events,
        date,
        by: stamp.actor,
      );
      if (compensation.rejection case final reason?) return Rejected(reason);
      return Accepted([
        for (final (type, payload) in compensation.events)
          stamp.event(type, payload, actor: Actor.revert),
      ]);
    case SetTarget():
      return _setTarget(command, state, stamp);
    case ClearTarget():
      return _clearTarget(command, state, stamp);
    case SetAutomationMode():
      return _setAutomationMode(command, state, stamp);
    case SetPriority():
      return _setPriority(command, state, stamp);
    case AcceptSuggestions():
      return _acceptSuggestions(command, state, stamp);
    case RunAutomation():
      return _runAutomation(command, state, stamp);
    case CreateSchedule():
      return _createSchedule(command, state, stamp);
    case EditSchedule():
      return _editSchedule(command, state, stamp);
    case DeleteSchedule():
      return _deleteSchedule(command, state, stamp);
    case EnterSchedule():
      return _enterSchedule(command, state, stamp);
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
  Money delta, {
  String? note,
}) => stamp.event(EventType.assignmentChanged, {
  'category': categoryId,
  'month': month.toIso(),
  'deltaCents': delta.cents,
  'note': ?note,
});

/// A one-line transaction whose money goes to Ready to Assign.
Event _income(
  _Stamp stamp, {
  required String accountId,
  required Money amount,
  required CivilDate date,
  required String payee,
  ClearedStatus cleared = ClearedStatus.uncleared,
  bool startingBalance = false,
}) => stamp.event(EventType.transactionCreated, {
  'transactionId': newId(),
  'accountId': accountId,
  'date': date.toIso(),
  'payee': payee,
  'memo': '',
  'cleared': cleared.name,
  'amountCents': amount.cents,
  'lines': [
    {
      ..._lineJson(
        LineInput(amount: amount, category: readyToAssignCategory),
        stamp.actor,
      ),
      // A Starting Balance is neither spending nor income, so it has no
      // business status to choose. The person adding the account has
      // already confirmed it, so it never enters the Review queue.
      if (startingBalance) 'reviewed': stamp.actor.isPerson,
    },
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
  return _checkText(lines.expand((line) => [line.memo, line.recipient]));
}

/// A stored line. It is Reviewed when a person set everything
/// [reviewNeed] asks for (ticket 09, ADR 0003).
Map<String, Object?> _lineJson(LineInput line, Actor actor) {
  final business = switch (line.business) {
    Business(:final tag) => Business(tag.trim()),
    final other => other,
  };
  final recipient = line.recipient?.trim();
  return {
    'lineId': line.id ?? newId(),
    'amountCents': line.amount.cents,
    'category': line.category,
    ...?business?.toJson(),
    'memo': line.memo.trim(),
    if (recipient != null && recipient.isNotEmpty) 'recipient': recipient,
    'reviewed':
        actor.isPerson &&
        reviewNeed(
              category: line.category,
              business: business,
              recipient: recipient,
            ) ==
            null,
  };
}

/// [line] as an edit would resubmit it.
LineInput _asInput(TransactionLine line) => LineInput(
  id: line.id,
  amount: line.amount,
  category: line.category,
  business: line.business,
  memo: line.memo,
  recipient: line.recipient,
);

/// The stored form of a projected line, to tell whether an edit changed it.
Map<String, Object?> _storedLine(TransactionLine line) => {
  'lineId': line.id,
  'amountCents': line.amount.cents,
  'category': line.category,
  ...?line.business?.toJson(),
  'memo': line.memo,
  'recipient': ?line.recipient,
  'reviewed': line.reviewed,
};

CommandResult _reviewLine(ReviewLine command, BudgetState state, _Stamp stamp) {
  if (!stamp.actor.isPerson) return const Rejected(Rejection.personRequired);
  final transaction = state.transaction(command.transactionId);
  if (transaction == null) {
    return const Rejected(Rejection.unknownTransaction);
  }
  final line = transaction.lines
      .where((line) => line.id == command.lineId)
      .firstOrNull;
  if (line == null) return const Rejected(Rejection.unknownLine);
  // A transfer line keeps its Category, which only an edit that checks the
  // transfer rules may change, and has no business status.
  final category = transaction.isTransfer ? line.category : command.category;
  final business = transaction.isTransfer
      ? null
      : switch (command.business) {
          Business(:final tag) => Business(tag.trim()),
          final other => other,
        };
  final recipient = business == const Business(giftsTag)
      ? command.recipient?.trim()
      : null;
  switch (reviewNeed(
    category: category,
    business: business,
    recipient: recipient,
    transfer: transaction.isTransfer,
  )) {
    case ReviewNeed.category:
      return const Rejected(Rejection.categoryRequired);
    case ReviewNeed.businessStatus:
      return const Rejected(Rejection.businessStatusRequired);
    case ReviewNeed.businessTag:
      return const Rejected(Rejection.businessTagRequired);
    case ReviewNeed.recipient:
      return const Rejected(Rejection.recipientRequired);
    case null:
  }
  if (category != readyToAssignCategory && category != line.category) {
    if (_checkActive(state, category!) case final rejected?) return rejected;
  }
  if (_checkText([recipient]) case final rejected?) return rejected;
  if (line.reviewed &&
      line.category == category &&
      line.business == business &&
      line.recipient == recipient) {
    return const Rejected(Rejection.noChange);
  }
  return Accepted([
    stamp.event(EventType.reviewSet, {
      'transactionId': transaction.id,
      'lineId': line.id,
      'category': category,
      ...?business?.toJson(),
      'recipient': ?recipient,
    }),
  ]);
}

CommandResult _editTransaction(
  EditTransaction command,
  BudgetState state,
  _Stamp stamp,
) {
  final transaction = state.transaction(command.transactionId);
  if (transaction == null) {
    return const Rejected(Rejection.unknownTransaction);
  }
  if (transaction.cleared == ClearedStatus.reconciled &&
      !command.confirmReconciled) {
    return const Rejected(Rejection.reconciledNeedsConfirmation);
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
    if (transaction.isTransfer) {
      if (_checkTransferLines(state, transaction, amount, lines)
          case final rejected?) {
        return rejected;
      }
    }
    final stored = [
      for (final line in lines)
        transaction.isTransfer
            ? _transferLine(
                line.amount,
                line.category,
                stamp.actor,
                id: line.id,
              )
            : _lineJson(line, stamp.actor),
    ];
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
  if (transaction.isTransfer) {
    events.addAll(_mirrorTransfer(state, stamp, transaction, events));
  }
  return Accepted(events);
}
