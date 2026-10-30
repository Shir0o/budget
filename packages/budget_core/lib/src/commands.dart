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
