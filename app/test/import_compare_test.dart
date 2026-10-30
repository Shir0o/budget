import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A budget holding one imported Actual transaction: $12.00 at Corner Market
/// on Jan 6, 2024, with $12.00 assigned to Groceries that month.
BudgetEngine _home() {
  final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  )..execute(const CreateBudget(name: 'Home'));
  final result = engine.execute(
    CommitImport(
      ImportBatch(
        accounts: const [
          ImportAccount(
            id: 'acct-checking',
            name: 'Everyday Checking',
            type: AccountType.checking,
          ),
        ],
        categoryGroups: const [
          ImportCategoryGroup(id: 'grp-bills', name: 'Bills'),
          ImportCategoryGroup(id: 'grp-fun', name: 'Fun'),
        ],
        categories: const [
          ImportCategory(
            id: 'cat-groceries',
            groupId: 'grp-bills',
            name: 'Groceries',
          ),
          ImportCategory(id: 'cat-meals', groupId: 'grp-fun', name: 'Meals'),
        ],
        transactions: [
          ImportTransaction(
            id: 'tx-market',
            accountId: 'acct-checking',
            date: CivilDate(2024, 1, 6),
            payee: 'Corner Market',
            cleared: ClearedStatus.cleared,
            amount: const Money(-1200),
            lines: const [
              ImportLine(
                amount: Money(-1200),
                category: 'cat-groceries',
                reviewed: true,
              ),
            ],
          ),
        ],
        assignments: [
          ImportAssignment(
            categoryId: 'cat-groceries',
            month: CalendarMonth(2024, 1),
            amount: const Money(1200),
          ),
        ],
        schedules: const [],
        targets: const [],
        expectedBalancesCents: const {'acct-checking': -1200},
      ),
    ),
  );
  if (result is! Accepted) throw StateError('The history was refused');
  return engine;
}

/// A synthetic YNAB export: the same Corner Market row, one transaction only
/// YNAB has, and a Meals month this budget never touched. Round cents, never
/// real data (AGENTS.md).
Uint8List _ynabZip() {
  const register =
      'Account,Flag,Date,Payee,Category Group/Category,Category Group,'
      'Category,Memo,Outflow,Inflow,Cleared\n'
      'Everyday Checking,,01/06/2024,Corner Market,Bills: Groceries,Bills,'
      'Groceries,,12.00,,Cleared\n'
      'Everyday Checking,,01/20/2024,Cafe,Bills: Groceries,Bills,Groceries,,'
      '5.50,,Uncleared\n';
  const plan =
      'Month,Category Group/Category,Category Group,Category,Assigned,'
      'Activity,Available\n'
      'Jan 2024,Bills: Groceries,Bills,Groceries,12.00,-17.50,-5.50\n'
      'Jan 2024,Fun: Meals,Fun,Meals,25.00,0.00,25.00\n';
  final archive = Archive();
  for (final (name, text) in [
    ('Home as of Oct 30, 2026 - Register.csv', register),
    ('Home as of Oct 30, 2026 - Plan.csv', plan),
  ]) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<void> _openCompare(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Import & compare'));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('choose-ynab-export')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('compares a YNAB export and pulls in what the person picks', (
    tester,
  ) async {
    final engine = _home();
    final services = AppServices.inMemory();
    (services.loader as InMemoryFileLoader).next = _ynabZip();
    await tester.pumpWidget(BudgetApp(engine: engine, services: services));
    await _openCompare(tester);
    await _choose(tester);

    expect(find.text('(a) Month-end balances'), findsOneWidget);
    expect(find.text('(b) Transactions'), findsOneWidget);
    expect(find.text('(c) Category months'), findsOneWidget);
    expect(find.text('(d) Only in one file'), findsOneWidget);
    expect(find.text('Cafe · 2024-01-20'), findsOneWidget);
    expect(find.textContaining('first differed'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ynab-add-transaction:0')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ynab-add-month:cat-meals:2024-01')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Will be added'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('ynab-pull')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ynab-done')), findsOneWidget);
    final state = engine.state;
    final pulled = state.transactions.singleWhere(
      (transaction) => transaction.payee == 'Cafe',
    );
    expect(pulled.amount, const Money(-550));
    expect(pulled.date, CivilDate(2024, 1, 20));
    expect(pulled.lines.single.category, 'cat-groceries');
    expect(pulled.lines.single.reviewed, isFalse);
    expect(
      state.assigned('cat-meals', CalendarMonth(2024, 1)),
      const Money(2500),
    );
    expect(state.reviewQueue, isNotEmpty);
  });

  testWidgets('ignoring an item asks why and leaves it out', (tester) async {
    final engine = _home();
    final services = AppServices.inMemory();
    (services.loader as InMemoryFileLoader).next = _ynabZip();
    await tester.pumpWidget(BudgetApp(engine: engine, services: services));
    await _openCompare(tester);
    await _choose(tester);

    await tester.tap(
      find.byKey(const ValueKey('ynab-ignore-month:cat-meals:2024-01')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('A typo in YNAB'));
    await tester.pumpAndSettle();

    expect(find.text('Ignored · A typo in YNAB'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ynab-add-transaction:0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ynab-pull')));
    await tester.pumpAndSettle();

    expect(
      engine.state.assigned('cat-meals', CalendarMonth(2024, 1)),
      Money.zero,
    );
    expect(
      engine.state.transactions.any(
        (transaction) => transaction.payee == 'Cafe',
      ),
      isTrue,
    );
  });

  testWidgets('says to import from Actual first', (tester) async {
    final engine = BudgetEngine(
      log: InMemoryEventLog(),
      deviceId: 'test-device',
      actor: Actor.userAndroid,
    )..execute(const CreateBudget(name: 'Home'));
    await tester.pumpWidget(BudgetApp(engine: engine));
    await _openCompare(tester);

    expect(find.byKey(const ValueKey('ynab-no-history')), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-ynab-export')), findsNothing);
  });

  testWidgets('says so when the file is not a YNAB export', (tester) async {
    final services = AppServices.inMemory();
    (services.loader as InMemoryFileLoader).next = Uint8List.fromList(
      utf8.encode('not a zip'),
    );
    await tester.pumpWidget(BudgetApp(engine: _home(), services: services));
    await _openCompare(tester);
    await _choose(tester);

    expect(find.byKey(const ValueKey('ynab-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-ynab-export')), findsOneWidget);
  });
}
