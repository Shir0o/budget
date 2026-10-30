import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

// Pieces shared by the Business tags and Business report screens.

/// The years those screens offer: every year with a transaction, this year
/// and next, newest first. A tax year is one calendar year (ticket 09).
List<int> businessYears(BudgetState state) {
  final years = {
    today().year,
    today().year + 1,
    for (final transaction in state.transactions) transaction.date.year,
  };
  return years.toList()..sort((a, b) => b.compareTo(a));
}

/// `Line 1 (gross receipts)` as it is, and `8` as `Schedule C line 8`.
String scheduleCLineText(String line) =>
    line.startsWith('Line ') ? line : 'Schedule C line $line';

/// The tax year the Business screens report on or set values for.
class BusinessYearPicker extends StatelessWidget {
  const BusinessYearPicker({
    super.key,
    required this.years,
    required this.year,
    required this.onChanged,
  });

  final List<int> years;
  final int year;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const FieldLabel('Tax year'),
      const Spacer(),
      DropdownButton<int>(
        key: const ValueKey('business-year'),
        value: year,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(12),
        style: const TextStyle(
          fontFamily: sansFamily,
          fontSize: 15,
          color: Palette.ink,
        ),
        items: [
          for (final year in years)
            DropdownMenuItem(value: year, child: Text('$year')),
        ],
        onChanged: (year) {
          if (year != null) onChanged(year);
        },
      ),
    ],
  );
}
