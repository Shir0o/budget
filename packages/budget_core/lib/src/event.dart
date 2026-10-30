import 'actor.dart';
import 'hlc.dart';

/// One immutable, attributed change to a budget (ticket 06, ADR 0001).
final class Event {
  const Event({
    required this.id,
    required this.budgetId,
    required this.deviceId,
    required this.hlc,
    required this.actor,
    required this.groupId,
    required this.type,
    required this.payload,
  });

  factory Event.fromJson(Map<String, Object?> json) => Event(
    id: json['id'] as String,
    budgetId: json['budgetId'] as String,
    deviceId: json['deviceId'] as String,
    hlc: Hlc.parse(json['hlc'] as String),
    actor: Actor.fromValue(json['actor'] as String),
    groupId: json['groupId'] as String,
    type: json['type'] as String,
    payload: (json['payload'] as Map).cast<String, Object?>(),
  );

  /// UUIDv7.
  final String id;
  final String budgetId;

  /// Random id created once per install.
  final String deviceId;
  final Hlc hlc;
  final Actor actor;

  /// Shared by every Event from one user action, automation run, import or
  /// MCP tool call. Revert works per group.
  final String groupId;

  /// One of [EventType].
  final String type;

  /// JSON-compatible values only. Money is stored as int cents.
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'id': id,
    'budgetId': budgetId,
    'deviceId': deviceId,
    'hlc': hlc.toString(),
    'actor': actor.value,
    'groupId': groupId,
    'type': type,
    'payload': payload,
  };
}

/// Event types. More arrive with later tickets (see ticket 06 for the list).
abstract final class EventType {
  /// `{name}`
  static const budgetCreated = 'BudgetCreated';

  /// `{accountId, name, accountType}`
  static const accountCreated = 'AccountCreated';

  /// `{transactionId, accountId, date, payee, memo, cleared, amountCents,
  /// lines}`. Each line is `{lineId, amountCents, category, business,
  /// businessTag, memo, reviewed}`, where `category` is
  /// [readyToAssignCategory] for income and null while uncategorized, and
  /// `business` is `personal`, `business` (with `businessTag`) or null.
  /// Events written before ticket 03 lack memo, cleared and the line's
  /// business, memo and reviewed. One side of a transfer also has
  /// `transferAccountId` and `transferTransactionId`, and a card or
  /// tracking account's Starting Balance has `startingBalance: true`.
  static const transactionCreated = 'TransactionCreated';

  /// `{transactionId, fields: {payee?, date?, memo?, cleared?}}`. Each field
  /// is last writer wins on its own.
  static const transactionFieldsSet = 'TransactionFieldsSet';

  /// `{transactionId, amountCents, lines}`, lines as in
  /// [transactionCreated]. Replaces the whole line set, so lines from two
  /// devices are never mixed (ticket 06).
  static const transactionSplitSet = 'TransactionSplitSet';

  /// `{transactionId}`. Beats any concurrent edit (ticket 06).
  static const transactionDeleted = 'TransactionDeleted';

  /// `{categoryGroupId, name}`
  static const categoryGroupCreated = 'CategoryGroupCreated';

  /// `{categoryId, categoryGroupId, name, cardAccountId?}`. A Card Payment
  /// Category has the card's `cardAccountId`.
  static const categoryCreated = 'CategoryCreated';

  /// `{categoryId}`
  static const categoryArchived = 'CategoryArchived';

  /// `{category, month, deltaCents}`, where `month` is `YYYY-MM`. A delta,
  /// so concurrent Assignments from two devices add up (ticket 06).
  static const assignmentChanged = 'AssignmentChanged';

  // Lifecycle Events that reverts emit (ticket 11). Restoring brings an
  // entity back as it was when it was deleted.

  /// `{transactionId}`
  static const transactionRestored = 'TransactionRestored';

  /// `{accountId}`
  static const accountDeleted = 'AccountDeleted';

  /// `{accountId}`
  static const accountRestored = 'AccountRestored';

  /// `{categoryGroupId}`
  static const categoryGroupDeleted = 'CategoryGroupDeleted';

  /// `{categoryGroupId}`
  static const categoryGroupRestored = 'CategoryGroupRestored';

  /// `{categoryId}`
  static const categoryUnarchived = 'CategoryUnarchived';

  /// `{categoryId}`
  static const categoryDeleted = 'CategoryDeleted';

  /// `{categoryId}`
  static const categoryRestored = 'CategoryRestored';

  /// `{groupIds, by}`: the first Event of a revert group. `groupIds` are the
  /// groups it reverts, the one chosen first, then any later ones that
  /// depended on it. `by` is the Actor who asked for the revert. It changes
  /// no state.
  static const groupReverted = 'GroupReverted';
}

/// The `category` value of a transaction line whose money goes to
/// Ready to Assign.
const readyToAssignCategory = 'readyToAssign';
