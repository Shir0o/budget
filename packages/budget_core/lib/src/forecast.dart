part of 'budget_state.dart';

// The Forecast (ticket 08): Scheduled Transactions expanded over the next
// 12 months. It is a projection of what is scheduled, never a change to the
// budget.

/// One month of the [Forecast].
final class ForecastMonth {
  const ForecastMonth({
    required this.month,
    required this.inflow,
    required this.outflow,
    required this.outflowByCategory,
    required this.balance,
  });

  final CalendarMonth month;

  /// Scheduled income due in the month. Positive.
  final Money inflow;

  /// Scheduled spending due in the month. Positive.
  final Money outflow;

  /// The spending by Category id, for the outflows that have one. Positive.
  final Map<String, Money> outflowByCategory;

  /// The predicted balance of the on-budget accounts at the end of the
  /// month.
  final Money balance;

  /// Whether the scheduled bills can't be covered by the money that will be
  /// there: the predicted balance is negative.
  bool get isUnderfunded => balance.isNegative;
}

/// The next [months] months of Scheduled Transactions, from [start]
/// (ticket 08). Scheduled Transactions never count until they happen, so
/// this reads the state and writes nothing.
final class Forecast {
  const Forecast._(this.startingBalance, this.months);

  /// [months] months from [start]. It includes every due date in each
  /// month, so a weekly schedule counts each time it comes due.
  factory Forecast.of(
    BudgetState state, {
    required CalendarMonth start,
    int months = 12,
  }) {
    final startingBalance = [
      for (final account in state.accounts)
        if (account.type.onBudget) account,
    ].fold(Money.zero, (total, a) => total + state.balance(a.id));
    final schedules = state.schedules;
    var balance = startingBalance;
    final expanded = <ForecastMonth>[];
    var month = start;
    for (var i = 0; i < months; i++, month = month.next) {
      var inflow = Money.zero;
      final outflowByCategory = <String, Money>{};
      for (final schedule in schedules) {
        final predicted = schedule.predictedIn(month);
        if (predicted == Money.zero) continue;
        if (schedule.isInflow) {
          inflow += predicted;
          continue;
        }
        outflowByCategory[schedule.category] =
            (outflowByCategory[schedule.category] ?? Money.zero) +
            Money(-predicted.cents);
      }
      final outflow = outflowByCategory.values.fold(
        Money.zero,
        (total, amount) => total + amount,
      );
      balance += inflow - outflow;
      expanded.add(
        ForecastMonth(
          month: month,
          inflow: inflow,
          outflow: outflow,
          outflowByCategory: Map.unmodifiable(outflowByCategory),
          balance: balance,
        ),
      );
    }
    return Forecast._(startingBalance, List.unmodifiable(expanded));
  }

  /// The on-budget accounts' balance now, which the months build on.
  final Money startingBalance;
  final List<ForecastMonth> months;

  /// The months whose scheduled bills can't be covered.
  List<ForecastMonth> get underfunded => [
    for (final month in months)
      if (month.isUnderfunded) month,
  ];
}
