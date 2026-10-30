import 'budget_state.dart';
import 'civil_date.dart';
import 'money.dart';

// Bank sync (ticket 10): what one fetch brought in, the note a changed
// amount leaves on a line, how a SimpleFIN id finds its transaction again,
// and the two edge cases a fetch leaves to a person: a pending charge that
// posts under a new id or vanishes, and a possible match with a line
// someone entered by hand.

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

/// How many days after its own date a posted charge may still be the posted
/// version of a pending one (ticket 10, step 2).
const bankPostedWindowDays = 7;

/// How many days a pending charge may be missing from the feed before it is
/// dropped (ticket 10, step 3).
const bankDropAfterDays = 10;

/// How many days either side of a line entered by hand an incoming bank
/// charge may be and still look like it (ticket 10, step 4).
const bankMatchWindowDays = 5;

/// How alike two payees must be to be the same charge, as a percentage
/// (ticket 10, step 2's ≥ 0.8).
const bankSamePayeePercent = 80;

/// A bank transaction that looks like one entered by hand or from a
/// schedule (ticket 10, step 4) waits on the transaction as
/// [Transaction.pendingMatch], so its shape lives with the transaction.

/// A fetch that left an account's balance different from the bank's
/// (ticket 10). The account shows a badge that opens Reconcile.
final class Discrepancy {
  const Discrepancy({
    required this.accountId,
    required this.bankBalance,
    required this.appBalance,
    required this.date,
  });

  final String accountId;

  /// The balance the bank reported.
  final Money bankBalance;

  /// The app's balance: cleared plus uncleared, pending included.
  final Money appBalance;

  /// The day the bank's balance was for.
  final CivilDate date;

  /// The bank's balance less the app's.
  Money get difference => bankBalance - appBalance;
}

/// The difference between [bankBalance] and the app's balance for
/// [accountId], or null when they agree (ticket 10's balance check).
Discrepancy? balanceDiscrepancy({
  required BudgetState state,
  required String accountId,
  required Money bankBalance,
  required CivilDate date,
}) {
  final appBalance = state.balance(accountId);
  if (bankBalance == appBalance) return null;
  return Discrepancy(
    accountId: accountId,
    bankBalance: bankBalance,
    appBalance: appBalance,
    date: date,
  );
}

/// [text] reduced to lower-case letters and digits, so `CORNER BISTRO #2`
/// and `Corner Bistro` compare equal (ticket 10, step 2).
String normalizedPayee(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// How alike two payees are, 0 to 100, using the characters their
/// [normalizedPayee] forms have in common (ticket 10, step 2's ≥ 80).
int payeeSimilarity(String a, String b) {
  final left = normalizedPayee(a);
  final right = normalizedPayee(b);
  if (left == right) return 100;
  if (left.isEmpty || right.isEmpty) return 0;
  // Levenshtein distance, one row at a time.
  var previous = [for (var i = 0; i <= right.length; i++) i];
  for (var i = 1; i <= left.length; i++) {
    final current = <int>[i];
    for (var j = 1; j <= right.length; j++) {
      final substitution =
          previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1);
      current.add(
        [
          previous[j] + 1,
          current[j - 1] + 1,
          substitution,
        ].reduce((a, b) => a < b ? a : b),
      );
    }
    previous = current;
  }
  final distance = previous[right.length];
  return 100 - (200 * distance ~/ (left.length + right.length));
}

/// Whether the two payees are the same charge: equal once normalized, or
/// [payeeSimilarity] at least [bankSamePayeePercent].
bool samePayee(String a, String b) =>
    normalizedPayee(a) == normalizedPayee(b) ||
    payeeSimilarity(a, b) >= bankSamePayeePercent;

/// Whether [posted] is within +25% or −10% of a [pending] charge, with the
/// same sign: tips and fuel holds change the amount a little (ticket 10,
/// step 2).
bool withinPostedWindow(Money pending, Money posted) {
  if (pending.isNegative != posted.isNegative) return false;
  final before = pending.cents.abs();
  final after = posted.cents.abs();
  if (before == 0) return after == 0;
  return after * 100 >= before * 90 && after * 100 <= before * 125;
}

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

  /// The still-pending charge [entry] may have posted under a new id
  /// (ticket 10, step 2): the same account, its own date within
  /// [bankPostedWindowDays], the same payee and an amount within the posted
  /// window. [except] holds the ids this fetch already took.
  Transaction? postedReplacementFor(
    BankEntry entry, {
    Set<String> except = const {},
  }) {
    if (entry.pending) return null;
    Transaction? best;
    var bestDays = 0;
    for (final transaction in transactions.reversed) {
      if (transaction.accountId != entry.accountId ||
          transaction.bankId == null ||
          transaction.cleared != ClearedStatus.uncleared ||
          except.contains(transaction.id) ||
          !samePayee(transaction.payee, entry.description) ||
          !withinPostedWindow(transaction.amount, entry.amount)) {
        continue;
      }
      final days = _daysBetween(transaction.date, entry.date);
      if (days > bankPostedWindowDays) continue;
      if (best == null || days < bestDays) {
        best = transaction;
        bestDays = days;
      }
    }
    return best;
  }

  /// The line someone entered by hand or from a schedule that [entry] may
  /// be (ticket 10, step 4): an unlinked transaction in the same account for
  /// exactly the same amount, dated within [bankMatchWindowDays]. It is only
  /// ever a proposal. [except] holds the ids this fetch already proposed.
  ///
  /// A line already waiting on this same bank id is offered again, so a
  /// re-fetch can refresh what the proposal shows.
  Transaction? proposedMatchFor(
    BankEntry entry, {
    Set<String> except = const {},
  }) {
    Transaction? best;
    var bestDays = 0;
    for (final transaction in transactions.reversed) {
      if (transaction.accountId != entry.accountId ||
          transaction.bankId != null ||
          transaction.isTransfer ||
          transaction.startingBalance ||
          except.contains(transaction.id) ||
          transaction.amount != entry.amount) {
        continue;
      }
      if (transaction.pendingMatch case final match?
          when match.bankId != entry.bankId) {
        continue;
      }
      final days = _daysBetween(transaction.date, entry.date);
      if (days > bankMatchWindowDays) continue;
      if (best == null || days < bestDays) {
        best = transaction;
        bestDays = days;
      }
    }
    return best;
  }

  /// Transactions waiting on a possible bank match, in the order they were
  /// added (ticket 10, step 4).
  List<Transaction> get proposedMatches => [
    for (final transaction in transactions)
      if (transaction.pendingMatch != null) transaction,
  ];
}

/// Whole days between two dates, either way round.
int _daysBetween(CivilDate a, CivilDate b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays.abs();
