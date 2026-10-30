import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// A budget with only its name, ready for the import to fill in.
(BudgetEngine, InMemoryEventLog) _home() {
  final log = InMemoryEventLog();
  final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  engine.execute(const CreateBudget(name: 'Home'));
  return (engine, log);
}

/// A tiny, synthetic Actual export: an income line and two Groceries lines in
/// an earlier year, and one Groceries line this year, on a card as well.
/// Amounts are round cents, never real data (AGENTS.md).
Uint8List _zip() {
  final directory = Directory.systemTemp.createTempSync('actual_app_test');
  final path = '${directory.path}/db.sqlite';
  try {
    final database = sqlite3.open(path);
    database.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY, name TEXT, offbudget INTEGER DEFAULT 0,
        closed INTEGER DEFAULT 0, type TEXT, tombstone INTEGER DEFAULT 0);
      CREATE TABLE category_groups (
        id TEXT PRIMARY KEY, name TEXT, is_income INTEGER DEFAULT 0,
        hidden INTEGER DEFAULT 0, tombstone INTEGER DEFAULT 0);
      CREATE TABLE categories (
        id TEXT PRIMARY KEY, name TEXT, cat_group TEXT,
        is_income INTEGER DEFAULT 0, hidden INTEGER DEFAULT 0,
        tombstone INTEGER DEFAULT 0);
      CREATE TABLE payees (
        id TEXT PRIMARY KEY, name TEXT, transfer_acct TEXT,
        tombstone INTEGER DEFAULT 0);
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY, acct TEXT, category TEXT, amount INTEGER,
        description TEXT, notes TEXT, date INTEGER, cleared TEXT,
        reconciled INTEGER DEFAULT 0, isParent INTEGER DEFAULT 0,
        isChild INTEGER DEFAULT 0, parent_id TEXT, transferred_id TEXT,
        starting_balance_flag INTEGER DEFAULT 0, tombstone INTEGER DEFAULT 0);
      CREATE TABLE zero_budgets (
        id TEXT PRIMARY KEY, month INTEGER, category TEXT, amount INTEGER,
        carryover INTEGER DEFAULT 0, tombstone INTEGER DEFAULT 0);
      CREATE TABLE rules (
        id TEXT PRIMARY KEY, conditions TEXT, actions TEXT,
        tombstone INTEGER DEFAULT 0);
      CREATE TABLE notes (
        id TEXT PRIMARY KEY, note TEXT, tombstone INTEGER DEFAULT 0);
      CREATE TABLE schedules (
        id TEXT PRIMARY KEY, name TEXT, next_date INTEGER, value INTEGER,
        account TEXT, payee TEXT, rule TEXT, tombstone INTEGER DEFAULT 0);
    ''');
    final thisYear = DateTime.now();
    final lastYear = DateTime(thisYear.year - 1, 3, 1);
    final recent = thisYear.subtract(const Duration(days: 5));
    String day(DateTime date) =>
        '${date.year}${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    database.execute('''
      INSERT INTO accounts VALUES
        ('acct-checking', 'Everyday Checking', 0, 0, 'checking', 0),
        ('acct-card', 'Travel Card', 0, 0, 'credit', 0);
      INSERT INTO category_groups VALUES
        ('grp-income', 'Income', 1, 0, 0),
        ('grp-bills', 'Bills', 0, 0, 0);
      INSERT INTO categories VALUES
        ('cat-income', 'Paycheck', 'grp-income', 1, 0, 0),
        ('cat-groceries', 'Groceries', 'grp-bills', 0, 0, 0);
      INSERT INTO payees VALUES
        ('pay-employer', 'Employer', NULL, 0),
        ('pay-store', 'Corner Market', NULL, 0);
      INSERT INTO transactions VALUES
        ('tx-income', 'acct-checking', 'cat-income', 100000, 'pay-employer',
         '', ${day(lastYear)}, 'cleared', 0, 0, 0, NULL, NULL, 0, 0),
        ('tx-old-food', 'acct-checking', 'cat-groceries', -2500, 'pay-store',
         '', ${day(lastYear.add(const Duration(days: 1)))}, 'cleared', 0, 0,
         0, NULL, NULL, 0, 0),
        ('tx-current', 'acct-checking', 'cat-groceries', -1500, 'pay-store',
         '', ${day(recent)}, 'uncleared', 0, 0, 0, NULL, NULL, 0, 0),
        ('tx-card', 'acct-card', 'cat-groceries', -2000, 'pay-store', '',
         ${day(lastYear.add(const Duration(days: 2)))}, 'cleared', 0, 0, 0,
         NULL, NULL, 0, 0);
    ''');
    database.close();
    final bytes = File(path).readAsBytesSync();
    final metadata = utf8.encode(
      jsonEncode({'id': 'actual-budget', 'budgetName': 'Home'}),
    );
    final archive = Archive()
      ..addFile(ArchiveFile('db.sqlite', bytes.length, bytes))
      ..addFile(ArchiveFile('metadata.json', metadata.length, metadata));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  } finally {
    directory.deleteSync(recursive: true);
  }
}

Future<void> _openImport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Import from Actual'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('imports an Actual zip through Match names and Map tags', (
    tester,
  ) async {
    final (engine, log) = _home();
    final services = AppServices.inMemory();
    final zip = _zip();
    (services.loader as InMemoryFileLoader).next = zip;
    await tester.pumpWidget(BudgetApp(engine: engine, services: services));
    await _openImport(tester);

    await tester.tap(find.byKey(const ValueKey('choose-actual-export')));
    await tester.pumpAndSettle();
    expect(find.text('Everyday Checking'), findsNothing);
    expect(find.text('4 (4 lines)'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('import-match-names')),
    );
    await tester.tap(find.byKey(const ValueKey('import-match-names')));
    await tester.pumpAndSettle();
    expect(find.text('Everyday Checking'), findsOneWidget);
    expect(find.text('Travel Card Payment'), findsOneWidget);
    expect(find.text('Ready to Assign'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('import-map-tags')));
    await tester.tap(find.byKey(const ValueKey('import-map-tags')));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Paycheck'), findsOneWidget);
    expect(find.text('Every account matches Actual'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('import-commit')));
    await tester.tap(find.byKey(const ValueKey('import-commit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-done')), findsOneWidget);
    final state = engine.state;
    final checking = state.accounts.singleWhere(
      (account) => account.name == 'Everyday Checking',
    );
    expect(state.balance(checking.id), const Money(96000));
    final card = state.accounts.singleWhere((a) => a.name == 'Travel Card');
    expect(state.balance(card.id), const Money(-2000));
    expect(state.cardPaymentCategory(card.id)?.name, 'Travel Card Payment');

    // The current year is Unreviewed; last year is Reviewed.
    expect(state.reviewQueue, hasLength(1));
    expect(
      state.transactions
          .singleWhere((t) => t.payee == 'Employer')
          .lines
          .single
          .reviewed,
      isTrue,
    );
    expect(
      state.transactions
          .singleWhere((t) => t.importedCategory == 'Paycheck')
          .id,
      isNotEmpty,
    );

    // Bank sync starts the day after the newest imported transaction.
    final newest = state.register(checking.id).first.date;
    expect(defaultLinkedFrom(state, checking.id, today()), newest.addDays(1));

    // One group, actor import, revertable as a unit.
    final groups = log.readAll().map((event) => event.groupId).toSet();
    expect(groups, hasLength(2));
    expect(
      log.readAll().where((event) => event.actor.value == 'import'),
      hasLength(log.readAll().length - 1),
    );
  });

  testWidgets('says so when the file is not an Actual export', (tester) async {
    final (engine, _) = _home();
    final services = AppServices.inMemory();
    (services.loader as InMemoryFileLoader).next = Uint8List.fromList(
      utf8.encode('not a zip'),
    );
    await tester.pumpWidget(BudgetApp(engine: engine, services: services));
    await _openImport(tester);

    await tester.tap(find.byKey(const ValueKey('choose-actual-export')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-actual-export')), findsOneWidget);
  });

  testWidgets('will not import into a budget that already has history', (
    tester,
  ) async {
    final (engine, _) = _home();
    engine.execute(
      AddAccount(
        name: 'Everyday Checking',
        type: AccountType.checking,
        startingBalance: const Money(100),
        asOf: today(),
      ),
    );
    await tester.pumpWidget(BudgetApp(engine: engine));
    await _openImport(tester);

    expect(find.byKey(const ValueKey('import-not-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-actual-export')), findsNothing);
  });
}
