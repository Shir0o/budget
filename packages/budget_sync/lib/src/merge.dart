import 'package:budget_core/budget_core.dart';

/// What one of a merge's invariant checks found broken (ticket 06).
enum AttentionKind {
  /// One side of a transfer is missing, or the two sides disagree.
  transferPair,

  /// A split's lines don't add up to its amount.
  splitSum,

  /// A credit card has no Card Payment Category.
  cardPayment,
}

/// Something a merge left broken, for the Review queue. It is never fixed
/// silently: a person repairs it, and the item stays until they do.
final class NeedsAttention {
  const NeedsAttention({
    required this.kind,
    required this.message,
    this.transactionId,
  });

  final AttentionKind kind;

  /// One line, such as `The lines of “Corner Bistro” don’t add up to its
  /// amount.`
  final String message;

  /// The transaction to open, when there is one.
  final String? transactionId;
}

/// Every invariant a merge found broken in [state] (ticket 06): both sides
/// of a transfer exist and agree, a split's lines add up to its amount, and
/// each credit card has a Card Payment Category.
///
/// A pure function of the projection, so both devices report the same items
/// after converging, and an item disappears only when the values behind it
/// are repaired.
List<NeedsAttention> needsAttention(BudgetState state) {
  final items = <NeedsAttention>[];
  for (final transaction in state.transactions) {
    final otherId = transaction.transferTransactionId;
    if (otherId != null) {
      final other = state.transaction(otherId);
      if (other == null) {
        items.add(
          NeedsAttention(
            kind: AttentionKind.transferPair,
            message:
                'The other side of ${_label(transaction, state)} is missing.',
            transactionId: transaction.id,
          ),
        );
      } else if (transaction.id.compareTo(otherId) < 0 &&
          (other.transferTransactionId != transaction.id ||
              other.accountId != transaction.transferAccountId ||
              other.amount != -transaction.amount)) {
        // Once per pair, on the side that sorts first.
        items.add(
          NeedsAttention(
            kind: AttentionKind.transferPair,
            message:
                'The two sides of ${_label(transaction, state)} don’t match.',
            transactionId: transaction.id,
          ),
        );
      }
    }
    final sum = transaction.lines.fold(
      Money.zero,
      (total, line) => total + line.amount,
    );
    if (sum != transaction.amount) {
      items.add(
        NeedsAttention(
          kind: AttentionKind.splitSum,
          message:
              'The lines of ${_label(transaction, state)} don’t add up to its '
              'amount.',
          transactionId: transaction.id,
        ),
      );
    }
  }
  for (final account in state.accounts) {
    if (account.type == AccountType.creditCard &&
        state.cardPaymentCategory(account.id) == null) {
      items.add(
        NeedsAttention(
          kind: AttentionKind.cardPayment,
          message: '${account.name} has no Card Payment Category.',
        ),
      );
    }
  }
  return items;
}

/// A transaction as a message names it: `“Corner Bistro”`, the account it
/// is in when it has no payee (a transfer), or `a transaction`.
String _label(Transaction transaction, BudgetState state) {
  if (transaction.payee.isNotEmpty) return '“${transaction.payee}”';
  return state.account(transaction.accountId)?.name ?? 'a transaction';
}
