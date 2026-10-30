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
  /// businessTag, memo, recipient?, note?, reviewed}`, where `category` is
  /// [readyToAssignCategory] for income and null while uncategorized,
  /// `business` is `personal`, `business` (with `businessTag`) or null, and
  /// `note` is why bank sync put the line back in Review (ticket 10).
  /// Events written before ticket 03 lack memo, cleared and the line's
  /// business, memo and reviewed. One side of a transfer also has
  /// `transferAccountId` and `transferTransactionId`, and a card or
  /// tracking account's Starting Balance has `startingBalance: true`. A
  /// bank fetch also has `bankId`, the SimpleFIN id it updates in place. An
  /// import also has `importedCategory`, the Actual income category name an
  /// income line lost when it went to Ready to Assign (ticket 14).
  static const transactionCreated = 'TransactionCreated';

  /// `{transactionId, fields: {payee?, date?, memo?, cleared?}}`. Each field
  /// is last writer wins on its own.
  static const transactionFieldsSet = 'TransactionFieldsSet';

  /// `{transactionId, amountCents, lines}`, lines as in
  /// [transactionCreated]. Replaces the whole line set, so lines from two
  /// devices are never mixed (ticket 06).
  static const transactionSplitSet = 'TransactionSplitSet';

  /// `{transactionId, lineId, category, business, businessTag, recipient}`,
  /// with `business` and `businessTag` as on a line (null for a transfer
  /// line) and `recipient` for a gift line. A person's values for one line,
  /// which mark it Reviewed. Only a person may emit it (ADR 0003); replay
  /// ignores it from any other actor.
  static const reviewSet = 'ReviewSet';

  /// `{transactionId}`. Beats any concurrent edit (ticket 06).
  static const transactionDeleted = 'TransactionDeleted';

  /// `{categoryGroupId, name}`
  static const categoryGroupCreated = 'CategoryGroupCreated';

  /// `{categoryId, categoryGroupId, name, cardAccountId?}`. A Card Payment
  /// Category has the card's `cardAccountId`.
  static const categoryCreated = 'CategoryCreated';

  /// `{categoryId, name}`. A Category's new name; everything else about it
  /// stays.
  static const categoryRenamed = 'CategoryRenamed';

  /// `{categoryId}`
  static const categoryArchived = 'CategoryArchived';

  /// `{accountId, date, clearedBalanceCents}`. Every cleared transaction in
  /// the account at that point becomes Reconciled (ticket 09).
  static const reconciled = 'Reconciled';

  /// `{category, month, deltaCents, note?}`, where `month` is `YYYY-MM`. A
  /// delta, so concurrent Assignments from two devices add up (ticket 06).
  /// An accepted Suggestion Batch has the note "accepted automation
  /// suggestion".
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

  /// `{date, by}`: the first Event of a Restore to a date group (ticket 11).
  /// `date` is the `YYYY-MM-DD` restored to, as of its end, and `by` is the
  /// Actor who asked. It changes no state.
  static const restoredToDate = 'RestoredToDate';

  // Targets and automation (ticket 08).

  /// `{categoryId, target}`, where `target` is a Target's stored form. Last
  /// writer wins.
  static const targetSet = 'TargetSet';

  /// `{categoryId}`
  static const targetCleared = 'TargetCleared';

  /// `{categoryId, mode}`, where `mode` is `off`, `suggest` or `auto`, or
  /// null for the default, as a revert writes.
  static const automationModeSet = 'AutomationModeSet';

  /// `{categoryIds}`: the whole priority order, replaced as a whole.
  static const prioritySet = 'PrioritySet';

  // Scheduled Transactions (ticket 10).

  /// `{scheduleId, accountId, payee, memo, amountCents, category, every,
  /// interval, nextDue}`, where `amountCents` is negative for an outflow and
  /// positive for income, `category` is a Category id or
  /// [readyToAssignCategory], and `interval` is days, weeks, months or
  /// years. It counts in nothing until a Transaction is entered.
  static const scheduleCreated = 'ScheduleCreated';

  /// `{scheduleId, fields}`, one field of a Scheduled Transaction at a time
  /// and last writer wins on each: `accountId`, `payee`, `memo`,
  /// `amountCents`, `category`, `every`, `interval` or `nextDue`.
  static const scheduleFieldsSet = 'ScheduleFieldsSet';

  /// `{scheduleId}`
  static const scheduleDeleted = 'ScheduleDeleted';

  /// `{scheduleId}`
  static const scheduleRestored = 'ScheduleRestored';

  // Business Tags and the business report (ticket 11).

  /// `{name, line, rule}`, where `rule` is a DeductionRule's stored form
  /// (`{kind: full}`, `{kind: percent, percent}`, `{kind: businessUse}` or
  /// `{kind: perRecipientCap, capCents}`). Custom tags only: the 19 presets
  /// ship with the app.
  static const businessTagCreated = 'BusinessTagCreated';

  /// `{tag, year, percent}`: a Business Tag's business-use % for one tax
  /// year, 0 to 100. Last writer wins. A null percent, as a revert writes,
  /// unsets it.
  static const businessUseSet = 'BusinessUseSet';
}

/// The `category` value of a transaction line whose money goes to
/// Ready to Assign.
const readyToAssignCategory = 'readyToAssign';
