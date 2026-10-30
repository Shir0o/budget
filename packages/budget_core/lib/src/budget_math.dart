part of 'budget_state.dart';

/// One Category's figures for one month.
final class _CategoryMonth {
  const _CategoryMonth({
    required this.activity,
    required this.available,
    this.creditOverspent = Money.zero,
  });

  final Money activity;
  final Money available;
  final Money creditOverspent;

  Money get cashOverspent =>
      available.isNegative ? -available - creditOverspent : Money.zero;
}

/// Ticket 07's budget math, worked out month by month from the first month
/// with an Assignment or a transaction to the last.
///
/// Within a month, each Category starts at Carry + Assigned, and the lines
/// in budget accounts apply in date order. A card line spent in a Category
/// moves as much of it as the Category's Available covers into the card's
/// Card Payment Category; the rest is credit overspending. A card refund
/// moves back in full. Tracking accounts never count.
final class _Ledger {
  _Ledger(BudgetState state) {
    final transactions = [
      for (final t in state._transactions.values)
        if (state._accounts[t.accountId]?.type.onBudget ?? true) t,
    ];
    // List.sort isn't stable, so break ties on the position added.
    final position = {for (final (i, t) in transactions.indexed) t.id: i};
    transactions.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : position[a.id]! - position[b.id]!;
    });

    final months = [
      for (final byMonth in state._assigned.values) ...byMonth.keys,
      for (final t in transactions) CalendarMonth.of(t.date),
    ]..sort();
    if (months.isEmpty) return;
    _first = months.first;
    _last = months.last;

    final ids = {
      ...state._assigned.keys,
      ...state._cardPayment.values,
      for (final t in transactions)
        for (final line in t.lines)
          if (line.category case final c? when c != readyToAssignCategory) c,
    };

    var previous = <String, Money>{};
    var next = 0;
    for (
      var month = _first!;
      month.compareTo(_last!) <= 0;
      month = month.next
    ) {
      final balance = {
        for (final c in ids) c: _carry(previous[c]) + state.assigned(c, month),
      };
      final activity = {for (final c in ids) c: Money.zero};
      final unfunded = <String, Money>{};
      void add(String c, Money amount) {
        balance[c] = balance[c]! + amount;
        activity[c] = activity[c]! + amount;
        lastActive[c] = month;
      }

      for (; next < transactions.length; next++) {
        final t = transactions[next];
        if (CalendarMonth.of(t.date) != month) break;
        final payment = state._cardPayment[t.accountId];
        for (final line in t.lines) {
          final category = line.category;
          if (category == readyToAssignCategory) continue;
          if (category == null) {
            // A payment to the card spends its Card Payment Category.
            // Uncategorized card spending comes out of Ready to Assign, so
            // it is funded. A cash advance goes to Ready to Assign instead,
            // so its debt is unfunded.
            if (payment != null &&
                !t.startingBalance &&
                !state._isCashAdvance(t) &&
                (t.isTransfer || line.amount.isNegative)) {
              add(payment, -line.amount);
            }
            continue;
          }
          final before = balance[category]!;
          add(category, line.amount);
          if (payment == null) continue;
          if (line.amount.isNegative) {
            final spent = -line.amount;
            final funded = before.isNegative
                ? Money.zero
                : before.compareTo(spent) < 0
                ? before
                : spent;
            add(payment, funded);
            unfunded[category] =
                (unfunded[category] ?? Money.zero) + spent - funded;
          } else {
            add(payment, -line.amount);
          }
        }
      }

      for (final c in ids) {
        final available = balance[c]!;
        final credit = unfunded[c] ?? Money.zero;
        _months.putIfAbsent(c, () => {})[month] = _CategoryMonth(
          activity: activity[c]!,
          available: available,
          creditOverspent: !available.isNegative
              ? Money.zero
              : (-available).compareTo(credit) < 0
              ? -available
              : credit,
        );
      }
      previous = balance;
    }
  }

  CalendarMonth? _first;
  CalendarMonth? _last;
  final _months = <String, Map<CalendarMonth, _CategoryMonth>>{};

  /// The last month each Category had any Activity.
  final lastActive = <String, CalendarMonth>{};

  static Money _carry(Money? available) =>
      available == null || available.isNegative ? Money.zero : available;

  /// Null before the first month. After the last, Available rolls over.
  _CategoryMonth? at(String categoryId, CalendarMonth month) {
    final byMonth = _months[categoryId];
    if (byMonth == null || month.compareTo(_first!) < 0) return null;
    if (month.compareTo(_last!) <= 0) return byMonth[month];
    return _CategoryMonth(
      activity: Money.zero,
      available: _carry(byMonth[_last!]!.available),
    );
  }

  /// Every Category's cash overspending in the months before [month].
  Money cashOverspentBefore(CalendarMonth month) {
    var total = Money.zero;
    for (final byMonth in _months.values) {
      for (final MapEntry(key: m, value: figures) in byMonth.entries) {
        if (m.compareTo(month) < 0) total += figures.cashOverspent;
      }
    }
    return total;
  }
}
