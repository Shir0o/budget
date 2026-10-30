import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'transaction_parts.dart';

/// The next 12 months of scheduled transactions (canvas: Forecast): what
/// each month spends, and where the balance lands. A month whose balance
/// goes negative is flagged, because its bills can't be covered.
class ForecastScreen extends StatelessWidget {
  const ForecastScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  Widget build(BuildContext context) {
    final state = engine.state;
    final forecast = Forecast.of(state, start: thisMonth());
    final short = forecast.underfunded;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Forecast'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  CardBox(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 2,
                      children: [
                        const Text(
                          'STARTING BALANCE',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.96,
                            color: Palette.muted,
                          ),
                        ),
                        Text(
                          forecast.startingBalance.formatDollars(),
                          style: amountStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            color: forecast.startingBalance.isNegative
                                ? Palette.problemText
                                : Palette.ink,
                          ).copyWith(letterSpacing: -0.6),
                        ),
                        const Hint(
                          'Every scheduled transaction in the next 12 months, '
                          'on the accounts that are on budget. Nothing here '
                          'counts until it happens.',
                        ),
                      ],
                    ),
                  ),
                  if (short.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        color: Palette.problemPill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        short.length == 1
                            ? '${monthName(short.single.month)} cannot cover '
                                  'its scheduled bills.'
                            : '${short.length} months cannot cover their '
                                  'scheduled bills.',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Palette.problemText,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'PREDICTED',
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 0.88,
                                    color: Palette.muted,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 96,
                                child: Text(
                                  'BALANCE',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 0.88,
                                    color: Palette.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final month in forecast.months)
                          _MonthRow(
                            month: month,
                            categories: [
                              for (final MapEntry(
                                    key: categoryId,
                                    value: amount,
                                  )
                                  in month.outflowByCategory.entries)
                                (categoryName(state, categoryId), amount),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({required this.month, required this.categories});

  final ForecastMonth month;

  /// Each Category's scheduled spending in the month.
  final List<(String, Money)> categories;

  @override
  Widget build(BuildContext context) {
    final short = month.isUnderfunded;
    final spending = [
      if (month.inflow.isPositive) '+${month.inflow.format()} in',
      if (month.outflow.isPositive) '−${month.outflow.format()} out',
      if (!month.inflow.isPositive && !month.outflow.isPositive)
        'nothing scheduled',
    ].join(' · ');
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.divider)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatMonth(month.month),
                  style: const TextStyle(fontSize: 15),
                ),
                Text(
                  spending,
                  style: const TextStyle(fontSize: 12, color: Palette.muted),
                ),
                if (categories.isNotEmpty)
                  Text(
                    [
                      for (final (name, amount) in categories)
                        '$name ${amount.format()}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                if (short)
                  Text(
                    'Short by ${Money(month.balance.cents.abs()).format()}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Palette.problemText,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerRight,
              child: AvailablePill(month.balance),
            ),
          ),
        ],
      ),
    );
  }
}
