import 'budget_state.dart';
import 'civil_date.dart';
import 'event.dart';
import 'history.dart';
import 'money.dart';

/// A request to change the budget. Commands are validated against the
/// current [BudgetState] and either produce one Event group or a
/// [Rejection]. They never change state themselves.
sealed class Command {
  const Command();
}

/// Starts a new budget. Only one budget lives in an Event log.
final class CreateBudget extends Command {
  const CreateBudget({required this.name});

  final String name;
}

/// Adds an account. Its [startingBalance] is recorded as a "Starting
/// Balance" transaction. In a cash account it goes to Ready to Assign; in a
/// card or tracking account it doesn't touch the budget, so an existing
/// card balance starts as unfunded debt (ticket 07 example 6). A credit
/// card also gets its Card Payment Category.
final class AddAccount extends Command {
  const AddAccount({
    required this.name,
    required this.type,
    required this.startingBalance,
    required this.asOf,
  });

  final String name;
  final AccountType type;
  final Money startingBalance;
  final CivilDate asOf;
}

/// Records money arriving in an account. It goes to Ready to Assign
/// (ticket 07 example 9).
final class RecordIncome extends Command {
  const RecordIncome({
    required this.accountId,
    required this.amount,
    required this.date,
    this.payee = '',
  });

  final String accountId;
  final Money amount;
  final CivilDate date;
  final String payee;
}

/// One line of a transaction as entered.
final class LineInput {
  const LineInput({
    required this.amount,
    this.category,
    this.business,
    this.memo = '',
    this.id,
  });

  /// An existing line's id, kept when its transaction is edited. Null for a
  /// new line.
  final String? id;

  /// Negative for an outflow.
  final Money amount;

  /// A Category id, [readyToAssignCategory] for income, or null to leave
  /// the line uncategorized. Income can only go to Ready to Assign; an
  /// inflow to a Category is a refund (ticket 07).
  final String? category;

  /// Null to leave it unset.
  final BusinessStatus? business;
  final String memo;
}

/// Enters a transaction by hand. Its [lines] must sum to [amount]. When a
/// person enters it, each line with both a category and a business status
/// is Reviewed (ticket 09).
final class CreateTransaction extends Command {
  const CreateTransaction({
    required this.accountId,
    required this.date,
    required this.amount,
    required this.lines,
    this.payee = '',
    this.memo = '',
  });

  final String accountId;
  final CivilDate date;

  /// Negative for an outflow.
  final Money amount;
  final List<LineInput> lines;
  final String payee;
  final String memo;
}

/// Changes a transaction. Null fields stay as they are. When [amount] or
/// [lines] is given, the lines (new or current) must sum to the amount (new
/// or current), and the whole line set is replaced.
final class EditTransaction extends Command {
  const EditTransaction({
    required this.transactionId,
    this.payee,
    this.date,
    this.memo,
    this.cleared,
    this.amount,
    this.lines,
  });

  final String transactionId;
  final String? payee;
  final CivilDate? date;
  final String? memo;
  final ClearedStatus? cleared;
  final Money? amount;
  final List<LineInput>? lines;
}

final class DeleteTransaction extends Command {
  const DeleteTransaction({required this.transactionId});

  final String transactionId;
}

/// Moves [amount] from one account to another as a pair of linked
/// transactions (ticket 07). Between two budget accounts, or two tracking
/// accounts, it has no [category]. From a budget account to a tracking
/// account it needs a Category, because the money leaves the budget; the
/// other way it needs Ready to Assign or a Category. Paying a card from
/// checking spends the card's Card Payment Category. Transfer lines skip
/// business status (ticket 09).
final class CreateTransfer extends Command {
  const CreateTransfer({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.date,
    this.category,
    this.memo = '',
  });

  final String fromAccountId;
  final String toAccountId;

  /// Positive.
  final Money amount;
  final CivilDate date;
  final String? category;
  final String memo;
}

/// Adds a category group, such as Bills or Everyday.
final class CreateCategoryGroup extends Command {
  const CreateCategoryGroup({required this.name});

  final String name;
}

/// Adds a Category to an existing group.
final class CreateCategory extends Command {
  const CreateCategory({required this.groupId, required this.name});

  final String groupId;
  final String name;
}

/// Sets a Category's Assignment for [month] to [amount]. Any month may be
/// assigned, including future ones (ticket 07). The change is recorded as
/// a delta.
final class SetAssignment extends Command {
  const SetAssignment({
    required this.categoryId,
    required this.month,
    required this.amount,
  });

  final String categoryId;
  final CalendarMonth month;
  final Money amount;
}

/// Moves [amount] of [month]'s Available from one Category to another, or
/// back to Ready to Assign when [toCategoryId] is [readyToAssignCategory].
/// A move between Categories leaves Ready to Assign unchanged.
final class MoveMoney extends Command {
  const MoveMoney({
    required this.fromCategoryId,
    required this.toCategoryId,
    required this.month,
    required this.amount,
  });

  final String fromCategoryId;
  final String toCategoryId;
  final CalendarMonth month;
  final Money amount;
}

/// Archives a Category. Blocked while it has a non-zero Available in
/// [month] or any later month it has money in (ticket 07 example 8).
final class ArchiveCategory extends Command {
  const ArchiveCategory({required this.categoryId, required this.month});

  final String categoryId;
  final CalendarMonth month;
}

/// Reverts an Event group by appending compensating Events with actor
/// `revert` in a new group (ticket 11). Nothing is erased, and reverting a
/// revert redoes it. Run [ChangeHistory.planRevert] first: a field set again
/// later is reverted anyway unless it is in [skipFields], and later groups
/// that depend on what this one created are reverted too only with
/// [includeDependents].
final class RevertGroup extends Command {
  const RevertGroup({
    required this.groupId,
    this.skipFields = const {},
    this.includeDependents = false,
  });

  final String groupId;
  final Set<FieldRef> skipFields;
  final bool includeDependents;
}

/// Why a command was refused.
enum Rejection {
  /// [CreateBudget] when the log already holds a budget.
  budgetAlreadyExists,

  /// Any other command before [CreateBudget].
  noBudget,

  /// A blank budget or account name.
  nameRequired,

  /// [RecordIncome] or a transaction in an account that doesn't exist.
  unknownAccount,

  /// [RecordIncome] of zero or less.
  incomeMustBePositive,

  /// [CreateCategory] in a group that doesn't exist.
  unknownCategoryGroup,

  /// A Category id that doesn't exist.
  unknownCategory,

  /// Assigning to, moving money with, or archiving an archived Category.
  categoryArchived,

  /// [SetAssignment] to the amount already assigned, or a [RevertGroup]
  /// that skips every field.
  noChange,

  /// [MoveMoney] or [CreateTransfer] of zero or less.
  amountMustBePositive,

  /// [MoveMoney] from a Category to itself.
  sameCategory,

  /// [ArchiveCategory] while the Category's Available is not 0.00.
  categoryHasBalance,

  /// A transaction id that doesn't exist or was deleted.
  unknownTransaction,

  /// A transaction of 0.00.
  zeroAmount,

  /// A transaction with no lines.
  noLines,

  /// Split lines that don't sum to the transaction's amount.
  splitDoesNotSum,

  /// [Business] with a blank tag.
  businessTagRequired,

  /// A payee or memo that looks like a card or account number
  /// (`containsSensitiveNumber`). "Don't store account numbers here."
  accountNumberNotAllowed,

  /// [CreateTransfer] from an account to itself.
  sameAccount,

  /// A transfer between a budget and a tracking account without a
  /// Category on the budget side (Ready to Assign is allowed only coming
  /// in).
  transferCategoryRequired,

  /// A Category on a transfer between two budget accounts, or two tracking
  /// accounts.
  transferHasNoCategory,

  /// Splitting a transfer into several lines.
  transferCannotSplit,

  /// [RevertGroup] of a group that isn't in the log.
  unknownGroup,

  /// [RevertGroup] of a group a revert is already undoing. Revert that
  /// revert to redo it instead.
  alreadyReverted,

  /// [RevertGroup] of something with no undo, such as creating the budget
  /// or an Event type this version doesn't know.
  cannotRevert,

  /// [RevertGroup] without [RevertGroup.includeDependents] when later
  /// changes depend on what the group created.
  hasDependents,
}

/// What a command produced.
sealed class CommandResult {
  const CommandResult();
}

/// The command was valid. [events] is the one group it appended.
final class Accepted extends CommandResult {
  const Accepted(this.events);

  final List<Event> events;
}

final class Rejected extends CommandResult {
  const Rejected(this.reason);

  final Rejection reason;
}
