import 'bank_sync.dart';
import 'budget_state.dart';
import 'civil_date.dart';
import 'event.dart';
import 'history.dart';
import 'import_batch.dart';
import 'money.dart';
import 'review.dart';
import 'target.dart';

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
    this.recipient,
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

  /// Who received a gift line. Null when unset.
  final String? recipient;
}

/// Enters a transaction by hand. Its [lines] must sum to [amount]. When a
/// person enters it, each line that [reviewNeed] finds complete is Reviewed
/// (ticket 09).
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
    this.confirmReconciled = false,
  });

  final String transactionId;
  final String? payee;
  final CivilDate? date;
  final String? memo;
  final ClearedStatus? cleared;
  final Money? amount;
  final List<LineInput>? lines;

  /// Editing a Reconciled transaction needs the person's confirmation
  /// (ticket 09).
  final bool confirmReconciled;
}

/// Reconciles [accountId] against [bankBalance], the balance the bank shows
/// on [date] (ticket 09). If the account's cleared balance matches, its
/// cleared transactions become Reconciled. On a mismatch it is rejected with
/// [Rejection.reconcileMismatch], unless [addAdjustment] is set: then an
/// adjustment transaction for the difference is added first. The adjustment
/// is cleared, Unreviewed, and goes to Ready to Assign.
final class Reconcile extends Command {
  const Reconcile({
    required this.accountId,
    required this.date,
    required this.bankBalance,
    this.addAdjustment = false,
  });

  final String accountId;
  final CivilDate date;
  final Money bankBalance;
  final bool addAdjustment;
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

/// A person marks one line Reviewed with its Category and business status
/// (ticket 09). Any actor other than a person is rejected (ADR 0003). A
/// transfer line skips [business]; a gift line needs a [recipient].
final class ReviewLine extends Command {
  const ReviewLine({
    required this.transactionId,
    required this.lineId,
    required this.category,
    required this.business,
    this.recipient,
  });

  final String transactionId;
  final String lineId;

  /// A Category id, or [readyToAssignCategory] for income.
  final String? category;
  final BusinessStatus? business;
  final String? recipient;
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

/// Restores the budget to how it was at the end of [date] (ticket 11): one
/// group of compensating Events, with actor `revert`, for the full
/// difference, so the restore can itself be reverted. Nothing is erased.
final class RestoreToDate extends Command {
  const RestoreToDate(this.date);

  final CivilDate date;
}

// Targets and automation (ticket 08).

/// Gives [categoryId] [target], replacing any it had.
final class SetTarget extends Command {
  const SetTarget({required this.categoryId, required this.target});

  final String categoryId;
  final Target target;
}

final class ClearTarget extends Command {
  const ClearTarget({required this.categoryId});

  final String categoryId;
}

final class SetAutomationMode extends Command {
  const SetAutomationMode({required this.categoryId, required this.mode});

  final String categoryId;
  final AutomationMode mode;
}

/// Sets the order automation fills Targets in. Categories left out follow,
/// in their order on screen.
final class SetPriority extends Command {
  const SetPriority({required this.categoryIds});

  final List<String> categoryIds;
}

/// Accepts the lines of [month]'s Suggestion Batch for [categoryIds], all
/// at once or some of them, as one group with the note "accepted
/// automation suggestion". The amounts are the batch's.
final class AcceptSuggestions extends Command {
  const AcceptSuggestions({required this.month, required this.categoryIds});

  final CalendarMonth month;
  final List<String> categoryIds;
}

/// An automation run for [month], which should be the current month:
/// assigns the auto-mode Categories' lines as one group with actor
/// `automation`. Suggest-mode lines are left for the person to accept.
final class RunAutomation extends Command {
  const RunAutomation({required this.month});

  final CalendarMonth month;
}

/// The note on an accepted Suggestion Batch's Assignments.
const acceptedSuggestionNote = 'accepted automation suggestion';

// Scheduled Transactions (ticket 10).

/// Adds a future or repeating transaction. It counts in nothing until
/// [EnterSchedule] enters it as a real Transaction.
///
/// [category] is a Category id for an outflow and [readyToAssignCategory]
/// for income, which is why [amount]'s sign decides what [category] may be.
final class CreateSchedule extends Command {
  const CreateSchedule({
    required this.accountId,
    required this.payee,
    required this.amount,
    required this.category,
    required this.every,
    required this.interval,
    required this.nextDue,
    this.memo = '',
  });

  final String accountId;
  final String payee;

  /// Negative for an outflow, positive for income.
  final Money amount;
  final String category;

  /// 1 or more.
  final int every;
  final TargetInterval interval;
  final CivilDate nextDue;
  final String memo;
}

/// Changes a Scheduled Transaction. Null fields stay as they are. The whole
/// change is one Event group, and each field is last writer wins on its own.
final class EditSchedule extends Command {
  const EditSchedule({
    required this.scheduleId,
    this.accountId,
    this.payee,
    this.amount,
    this.category,
    this.every,
    this.interval,
    this.nextDue,
    this.memo,
  });

  final String scheduleId;
  final String? accountId;
  final String? payee;
  final Money? amount;
  final String? category;
  final int? every;
  final TargetInterval? interval;
  final CivilDate? nextDue;
  final String? memo;
}

final class DeleteSchedule extends Command {
  const DeleteSchedule({required this.scheduleId});

  final String scheduleId;
}

/// Enters [scheduleId] as a real, Unreviewed Transaction dated its next due
/// date, and moves the schedule on by one interval (ticket 08). The line has
/// no business status, so Review asks the person for one: nothing is
/// categorized for them.
final class EnterSchedule extends Command {
  const EnterSchedule({required this.scheduleId});

  final String scheduleId;
}

/// Applies one bank fetch (ticket 10) as one Event group with actor
/// `bank-sync`: a same SimpleFIN id updates its transaction in place, and
/// anything new becomes an Unreviewed line. A Reviewed line whose amount
/// changed returns to Review with the note [bankChangeNote].
final class ImportBankTransactions extends Command {
  const ImportBankTransactions({required this.entries});

  final List<BankEntry> entries;
}

// Migration (ticket 14).

/// Writes a whole import as one Event group with actor `import`: accounts,
/// Category groups and Categories, Assignments, Targets, Scheduled
/// Transactions and Transactions. It is checked as a whole and refused as a
/// whole: in particular, every account's transactions must add up to
/// Actual's balance for it, to the cent. Rules are never imported and only a
/// person marks a current-year line Reviewed (ADR 0003).
final class CommitImport extends Command {
  const CommitImport(this.batch);

  final ImportBatch batch;
}

// Business Tags (ticket 11).

/// Adds a custom Business Tag (ticket 04). Its name must not be a preset or
/// another custom tag.
final class CreateBusinessTag extends Command {
  const CreateBusinessTag({
    required this.name,
    required this.line,
    required this.rule,
  });

  final String name;

  /// One of [scheduleCLines].
  final String line;
  final DeductionRule rule;
}

/// Sets [tag]'s business-use % for tax [year], which is one calendar year.
final class SetBusinessUse extends Command {
  const SetBusinessUse({
    required this.tag,
    required this.year,
    required this.percent,
  });

  final String tag;
  final int year;

  /// 0 to 100.
  final int percent;
}

/// Why a command was refused.
enum Rejection {
  /// [CreateBudget] when the log already holds a budget.
  budgetAlreadyExists,

  /// Any other command before [CreateBudget].
  noBudget,

  /// A blank budget or account name.
  nameRequired,

  /// [RecordIncome], a transaction or a Scheduled Transaction in an account
  /// that doesn't exist.
  unknownAccount,

  /// [RecordIncome] of zero or less.
  incomeMustBePositive,

  /// [CreateCategory] in a group that doesn't exist.
  unknownCategoryGroup,

  /// A Category id that doesn't exist.
  unknownCategory,

  /// Assigning to, moving money with, or archiving an archived Category.
  categoryArchived,

  /// [SetAssignment] to the amount already assigned, a [RevertGroup]
  /// that skips every field, or a [RestoreToDate] with nothing to undo.
  noChange,

  /// [MoveMoney] or [CreateTransfer] of zero or less.
  amountMustBePositive,

  /// [MoveMoney] from a Category to itself.
  sameCategory,

  /// [ArchiveCategory] while the Category's Available is not 0.00.
  categoryHasBalance,

  /// A transaction id that doesn't exist or was deleted.
  unknownTransaction,

  /// A transaction or Scheduled Transaction of 0.00.
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
  /// or an Event type this version doesn't know. Also a [RestoreToDate]
  /// that would need such an undo, such as a date before the budget.
  cannotRevert,

  /// [RevertGroup] without [RevertGroup.includeDependents] when later
  /// changes depend on what the group created.
  hasDependents,

  /// [ReviewLine] from bank sync, automation, an import, MCP or a revert.
  /// Only a person marks a line Reviewed (ADR 0003).
  personRequired,

  /// [ReviewLine] of a line id the transaction doesn't have.
  unknownLine,

  /// [ReviewLine] without a Category.
  categoryRequired,

  /// [ReviewLine] without Personal or Business on a line that isn't a
  /// transfer.
  businessStatusRequired,

  /// [ReviewLine] of a gift line without a recipient.
  recipientRequired,

  /// [Reconcile] when the cleared balance differs from the bank's and no
  /// adjustment was asked for.
  reconcileMismatch,

  /// [EditTransaction] of a Reconciled transaction without
  /// `confirmReconciled`.
  reconciledNeedsConfirmation,

  /// A Target of zero or less.
  targetAmountMustBePositive,

  /// A Repeating Target or Scheduled Transaction every 0 or fewer days,
  /// weeks, months or years.
  intervalMustBePositive,

  /// [SetPriority] listing a Category twice.
  duplicateCategory,

  /// [AcceptSuggestions] for a Category that isn't in the batch.
  notSuggested,

  /// A Scheduled Transaction id that doesn't exist or was deleted.
  unknownSchedule,

  /// [CreateSchedule] or [EditSchedule] of income that isn't to Ready to
  /// Assign, or of an outflow without a Category.
  scheduleCategoryRequired,

  /// [CreateBusinessTag] with a name a preset or custom tag already has.
  businessTagExists,

  /// [CreateBusinessTag] without a Schedule C line.
  businessLineRequired,

  /// [CreateBusinessTag] with a fixed percentage outside 1 to 100, or
  /// [SetBusinessUse] outside 0 to 100.
  percentOutOfRange,

  /// [CreateBusinessTag] with a gift cap of zero or less.
  capMustBePositive,

  /// [SetBusinessUse] for a tag that doesn't exist.
  unknownBusinessTag,

  /// [CommitImport] with an id the log already has, a one-sided transfer, a
  /// line that doesn't sum to its transaction, or a like break of the rules.
  importPlanInvalid,

  /// [CommitImport] where an account's imported transactions don't add up to
  /// Actual's balance for it, to the cent (ticket 14). A parser bug, never a
  /// user problem.
  importBalanceMismatch,
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
