import 'dart:convert';

import 'budget_state.dart';
import 'civil_date.dart';
import 'event.dart';
import 'money.dart';

// Plain-text exports (ticket 12). Each is a pure function of a BudgetState,
// so what the Export screen saves is exactly what the core queries answer.
// Money is written as signed decimals built from whole cents (-12.50), never
// through floating point.

/// One row per transaction line, so a split shows as several rows that share
/// a Transaction ID.
String transactionsCsv(BudgetState state) => _csv(
  const ['Transaction ID', 'Date', 'Account', 'Payee', 'Category', 'Amount'],
  [
    for (final t in state.transactions)
      for (final line in t.lines)
        [
          t.id,
          t.date.toIso(),
          state.account(t.accountId)?.name ?? '',
          t.payee,
          switch (line.category) {
            null => '',
            readyToAssignCategory => 'Ready to Assign',
            final id => state.category(id)?.name ?? id,
          },
          _decimal(line.amount.cents),
        ],
  ],
);

/// Monthly Assignments in the shape of a YNAB Plan export (ticket 02): one
/// row per Category and month, for every month from the first Assignment
/// to the last, ordered by month, then group, then Category.
String assignmentsCsv(BudgetState state) {
  final months = state.assignmentMonths;
  return _csv(
    const [
      'Month',
      'Category Group/Category',
      'Category Group',
      'Category',
      'Assigned',
    ],
    [
      if (months.isNotEmpty)
        for (
          var month = months.first;
          month.compareTo(months.last) <= 0;
          month = month.next
        )
          for (final group in state.categoryGroups)
            for (final category in state.categories)
              if (category.groupId == group.id)
                [
                  '${_monthNames[month.month - 1]} ${month.year}',
                  '${group.name}: ${category.name}',
                  group.name,
                  category.name,
                  _decimal(state.assigned(category.id, month).cents),
                ],
    ],
  );
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The whole current state as indented JSON, with Ready to Assign as it
/// stands during [month]. Not encrypted.
String stateJson(BudgetState state, {required CalendarMonth month}) {
  final budget = state.budget;
  return const JsonEncoder.withIndent('  ').convert({
    'format': 'budget-state',
    'version': 1,
    'budget': budget == null ? null : {'id': budget.id, 'name': budget.name},
    'accounts': [
      for (final a in state.accounts)
        {'id': a.id, 'name': a.name, 'type': a.type.name},
    ],
    'transactions': [
      for (final t in state.transactions)
        {
          'id': t.id,
          'accountId': t.accountId,
          'date': t.date.toIso(),
          'payee': t.payee,
          'memo': t.memo,
          'cleared': t.cleared.name,
          'amountCents': t.amount.cents,
          'lines': [
            for (final line in t.lines)
              {
                'id': line.id,
                'amountCents': line.amount.cents,
                'category': line.category,
                'business': switch (line.business) {
                  null => null,
                  Personal() => 'personal',
                  Business(:final tag) => {'tag': tag},
                },
                'memo': line.memo,
                'reviewed': line.reviewed,
              },
          ],
        },
    ],
    'categoryGroups': [
      for (final g in state.categoryGroups) {'id': g.id, 'name': g.name},
    ],
    'categories': [
      for (final c in state.categories)
        {
          'id': c.id,
          'groupId': c.groupId,
          'name': c.name,
          'archived': c.archived,
        },
    ],
    'assignments': [
      for (final m in state.assignmentMonths)
        for (final c in state.categories)
          if (state.assigned(c.id, m) != Money.zero)
            {
              'category': c.id,
              'month': m.toIso(),
              'assignedCents': state.assigned(c.id, m).cents,
            },
    ],
    'month': month.toIso(),
    'readyToAssignCents': state.readyToAssign(month).cents,
  });
}

/// `-12.50` from -1250 cents.
String _decimal(int cents) {
  final abs = cents.abs();
  final sign = cents < 0 ? '-' : '';
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// RFC 4180: CRLF line ends, and fields holding a comma, quote or line
/// break are quoted with quotes doubled.
String _csv(List<String> header, List<List<String>> rows) {
  String field(String value) => RegExp(r'[",\r\n]').hasMatch(value)
      ? '"${value.replaceAll('"', '""')}"'
      : value;
  return [header, ...rows].map((r) => '${r.map(field).join(',')}\r\n').join();
}
