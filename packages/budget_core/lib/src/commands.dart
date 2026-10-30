import 'budget_state.dart';
import 'civil_date.dart';
import 'event.dart';
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

/// Adds a budget account. Its [startingBalance] is recorded as a
/// "Starting Balance" transaction that goes to Ready to Assign.
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

/// Why a command was refused.
enum Rejection {
  /// [CreateBudget] when the log already holds a budget.
  budgetAlreadyExists,

  /// Any other command before [CreateBudget].
  noBudget,

  /// A blank budget or account name.
  nameRequired,

  /// [RecordIncome] into an account that doesn't exist.
  unknownAccount,

  /// [RecordIncome] of zero or less.
  incomeMustBePositive,

  /// [CreateCategory] in a group that doesn't exist.
  unknownCategoryGroup,

  /// A Category id that doesn't exist.
  unknownCategory,

  /// Assigning to, moving money with, or archiving an archived Category.
  categoryArchived,

  /// [SetAssignment] to the amount already assigned.
  noChange,

  /// [MoveMoney] of zero or less.
  amountMustBePositive,

  /// [MoveMoney] from a Category to itself.
  sameCategory,

  /// [ArchiveCategory] while the Category's Available is not 0.00.
  categoryHasBalance,
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
