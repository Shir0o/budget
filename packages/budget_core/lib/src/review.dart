import 'budget_state.dart';

// Review (ticket 09, ADR 0003): what a line needs before a person can mark
// it Reviewed, the queue of Unreviewed lines, and the payee hint.

/// The Business Tag whose lines each need a recipient (ticket 04).
const giftsTag = 'Gifts';

/// The first thing a line still needs before it can be Reviewed.
enum ReviewNeed {
  /// A Category, or Ready to Assign for income. Transfer lines skip it.
  category,

  /// Personal or Business. Transfer lines skip it.
  businessStatus,

  /// Business was chosen without a Business Tag.
  businessTag,

  /// A gift line's recipient.
  recipient,
}

/// What a line with these values still needs, or null when a person can
/// mark it Reviewed (ticket 09).
ReviewNeed? reviewNeed({
  required String? category,
  required BusinessStatus? business,
  String? recipient,
  bool transfer = false,
}) {
  // A transfer's Category rules belong to the transfer itself (ticket
  // 07), and a transfer isn't spending, so it needs nothing here.
  if (transfer) return null;
  if (category == null) return ReviewNeed.category;
  return switch (business) {
    null => ReviewNeed.businessStatus,
    Business(:final tag) when tag.trim().isEmpty => ReviewNeed.businessTag,
    Business(tag: giftsTag) when (recipient?.trim() ?? '').isEmpty =>
      ReviewNeed.recipient,
    _ => null,
  };
}

/// One Unreviewed line in the Review queue.
final class ReviewItem {
  const ReviewItem(this.transaction, this.line);

  final Transaction transaction;
  final TransactionLine line;
}

/// A payee's most recent Reviewed values, shown as a hint chip. Nothing is
/// applied until the person taps it (ADR 0003).
final class PayeeHint {
  const PayeeHint({required this.category, required this.business});

  final String category;

  /// Null for a transfer line.
  final BusinessStatus? business;
}

extension Review on BudgetState {
  /// Every Unreviewed line, newest date first (same-day ones newest added
  /// first), then in line order. Transfer lines and tracking-account lines
  /// are left out: a transfer isn't spending, and a tracking account is
  /// outside the budget.
  List<ReviewItem> get reviewQueue => [
    for (final transaction in _newestFirst())
      if (!transaction.isTransfer &&
          (account(transaction.accountId)?.type.onBudget ?? true))
        for (final line in transaction.lines)
          if (!line.reviewed) ReviewItem(transaction, line),
  ];

  /// The Category and business status most recently Reviewed on a line for
  /// [payee], ignoring case. Lines of [exceptTransactionId] and lines whose
  /// Category is archived don't count.
  PayeeHint? payeeHint(String payee, {String? exceptTransactionId}) {
    final key = payee.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final transaction in _newestFirst()) {
      if (transaction.id == exceptTransactionId ||
          transaction.payee.trim().toLowerCase() != key) {
        continue;
      }
      for (final line in transaction.lines) {
        final category = line.category;
        if (!line.reviewed || category == null) continue;
        if (this.category(category)?.archived ?? false) continue;
        return PayeeHint(category: category, business: line.business);
      }
    }
    return null;
  }

  /// Every transaction, newest date first. Same-day ones are newest added
  /// first.
  List<Transaction> _newestFirst() {
    final list = transactions.reversed.toList();
    // List.sort isn't stable, so break ties on the position added.
    final position = {for (final (i, t) in list.indexed) t.id: i};
    return list..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : position[a.id]! - position[b.id]!;
    });
  }
}
