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

  /// `{transactionId, accountId, date, payee, amountCents,
  /// lines: [{lineId, amountCents, category}]}`, where `category` is
  /// [readyToAssignCategory] for income.
  static const transactionCreated = 'TransactionCreated';
}

/// The `category` value of a transaction line whose money goes to
/// Ready to Assign.
const readyToAssignCategory = 'readyToAssign';
