import 'budget_state.dart';
import 'civil_date.dart';
import 'money.dart';

// Bank sync (ticket 10): what one fetch brought in, the note a changed
// amount leaves on a line, and how a SimpleFIN id finds its transaction
// again.

/// One bank transaction a fetch brought in, already matched to an app
/// account and reduced to what a Transaction keeps.
final class BankEntry {
  const BankEntry({
    required this.accountId,
    required this.bankId,
    required this.date,
    required this.amount,
    required this.description,
    this.memo = '',
    this.pending = false,
  });

  /// The app account the SimpleFIN account is linked to.
  final String accountId;

  /// The bank's id for the transaction, which a later fetch matches on.
  final String bankId;

  final CivilDate date;

  /// Negative for an outflow.
  final Money amount;

  /// What the bank calls the payee.
  final String description;
  final String memo;

  /// Pending charges count in the balance but are not cleared yet.
  final bool pending;
}

/// The note a line carries when a fetch changed its amount after a person
/// had reviewed it, such as `changed by bank: −$48.20 → −$15.00`.
String bankChangeNote(Money before, Money after) =>
    'changed by bank: ${before.formatDollars()} → ${after.formatDollars()}';

extension BankSync on BudgetState {
  /// The transaction a fetch imported with [bankId] into [accountId], or
  /// null when this is the first time it arrived. A bank id is only unique
  /// within its account.
  Transaction? bankTransaction(String accountId, String bankId) {
    for (final transaction in transactions) {
      if (transaction.accountId == accountId && transaction.bankId == bankId) {
        return transaction;
      }
    }
    return null;
  }
}
