import 'dart:convert';

import 'budget_state.dart';
import 'event.dart';

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
          line.category == readyToAssignCategory
              ? 'Ready to Assign'
              : line.category,
          _decimal(line.amount.cents),
        ],
  ],
);

/// Monthly Assignments in the shape of a YNAB Plan export (ticket 02): one
/// row per category and month. Assignments arrive with the Categories
/// ticket, so until then this holds the header only.
String assignmentsCsv(BudgetState state) => _csv(const [
  'Month',
  'Category Group/Category',
  'Category Group',
  'Category',
  'Assigned',
], const []);

/// The whole current state as indented JSON. Not encrypted.
String stateJson(BudgetState state) {
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
          'amountCents': t.amount.cents,
          'lines': [
            for (final line in t.lines)
              {
                'id': line.id,
                'amountCents': line.amount.cents,
                'category': line.category,
              },
          ],
        },
    ],
    'readyToAssignCents': state.readyToAssign.cents,
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
