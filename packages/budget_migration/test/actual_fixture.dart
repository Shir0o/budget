import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart';

/// A small, entirely synthetic Actual export: two budget accounts, a card, a
/// tracking account and a closed account; income; a split; three transfers; a
/// tombstoned row; a zero-amount row; Assignments, Schedules, rules, notes and
/// `#tags`. No real financial data (AGENTS.md).
///
/// Balances add up to:
/// - Everyday Checking: 500000 − 150000 + 320000 − 1200 − 50000 − 100000
///   − 4500 − 20000 − 1000 = 493300
/// - Rainy Day Savings: 50000
/// - Travel Card: −5000 − 4000 − 2500 + 20000 = 8500
/// - Brokerage: 100000
/// - Old Checking: −1000
Uint8List syntheticActualZip() {
  final directory = Directory.systemTemp.createTempSync('actual_fixture');
  final path = '${directory.path}/db.sqlite';
  try {
    final database = sqlite3.open(path);
    database.execute(_schema);
    database.execute(_rows);
    database.close();
    final bytes = File(path).readAsBytesSync();
    final metadata = utf8.encode(
      jsonEncode({'id': 'actual-budget-1', 'budgetName': 'Home'}),
    );
    final archive = Archive()
      ..addFile(ArchiveFile('db.sqlite', bytes.length, bytes))
      ..addFile(ArchiveFile('metadata.json', metadata.length, metadata));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  } finally {
    directory.deleteSync(recursive: true);
  }
}

Uint8List syntheticBytes(String text) => Uint8List.fromList(utf8.encode(text));

/// A zip of plain files, for the "not an Actual export" cases.
Uint8List syntheticZip(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(key: name, value: text) in files.entries) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _schema = '''
  CREATE TABLE accounts (
    id TEXT PRIMARY KEY,
    name TEXT,
    offbudget INTEGER DEFAULT 0,
    closed INTEGER DEFAULT 0,
    type TEXT,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE category_groups (
    id TEXT PRIMARY KEY,
    name TEXT,
    is_income INTEGER DEFAULT 0,
    hidden INTEGER DEFAULT 0,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE categories (
    id TEXT PRIMARY KEY,
    name TEXT,
    cat_group TEXT,
    is_income INTEGER DEFAULT 0,
    hidden INTEGER DEFAULT 0,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE payees (
    id TEXT PRIMARY KEY,
    name TEXT,
    transfer_acct TEXT,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE category_mapping (
    id TEXT PRIMARY KEY,
    targetId TEXT,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE payee_mapping (
    id TEXT PRIMARY KEY,
    targetId TEXT,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE transactions (
    id TEXT PRIMARY KEY,
    acct TEXT,
    category TEXT,
    amount INTEGER,
    description TEXT,
    notes TEXT,
    date INTEGER,
    cleared TEXT,
    reconciled INTEGER DEFAULT 0,
    isParent INTEGER DEFAULT 0,
    isChild INTEGER DEFAULT 0,
    parent_id TEXT,
    transferred_id TEXT,
    starting_balance_flag INTEGER DEFAULT 0,
    imported_description TEXT,
    financial_id TEXT,
    schedule TEXT,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE zero_budgets (
    id TEXT PRIMARY KEY,
    month INTEGER,
    category TEXT,
    amount INTEGER,
    carryover INTEGER DEFAULT 0,
    goal INTEGER,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE schedules (
    id TEXT PRIMARY KEY,
    name TEXT,
    next_date INTEGER,
    value INTEGER,
    account TEXT,
    payee TEXT,
    rule TEXT,
    posts_transaction INTEGER DEFAULT 1,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE rules (
    id TEXT PRIMARY KEY,
    conditions TEXT,
    actions TEXT,
    tombstone INTEGER DEFAULT 0
  );
  CREATE TABLE notes (
    id TEXT PRIMARY KEY,
    note TEXT,
    tombstone INTEGER DEFAULT 0
  );
''';

const _rows = '''
  INSERT INTO accounts VALUES
    ('acct-checking', 'Everyday Checking', 0, 0, 'checking', 0),
    ('acct-savings', 'Rainy Day Savings', 0, 0, 'savings', 0),
    ('acct-card', 'Travel Card', 0, 0, 'credit', 0),
    ('acct-brokerage', 'Brokerage', 1, 0, 'investment', 0),
    ('acct-old', 'Old Checking', 0, 1, 'checking', 0),
    ('acct-gone', 'Deleted Account', 0, 0, 'checking', 1);

  INSERT INTO category_groups VALUES
    ('grp-income', 'Income', 1, 0, 0),
    ('grp-bills', 'Bills', 0, 0, 0),
    ('grp-fun', 'Fun', 0, 1, 0);

  INSERT INTO categories VALUES
    ('cat-income', 'Paycheck', 'grp-income', 1, 0, 0),
    ('cat-rent', 'Rent', 'grp-bills', 0, 0, 0),
    ('cat-groceries', 'Groceries', 'grp-bills', 0, 0, 0),
    ('cat-meals', 'Meals', 'grp-fun', 0, 0, 0),
    ('cat-hidden', 'Old savings goal', 'grp-fun', 0, 1, 0),
    ('cat-deleted', 'Deleted Category', 'grp-bills', 0, 0, 1);

  INSERT INTO payees VALUES
    ('pay-store', 'Corner Market', NULL, 0),
    ('pay-old-store', 'Corner Market (old)', NULL, 0),
    ('pay-work', 'Client Co', NULL, 0),
    ('pay-landlord', 'Landlord', NULL, 0),
    ('pay-savings', 'Transfer : Rainy Day Savings', 'acct-savings', 0),
    ('pay-brokerage', 'Transfer : Brokerage', 'acct-brokerage', 0),
    ('pay-card', 'Transfer : Travel Card', 'acct-card', 0);

  INSERT INTO category_mapping VALUES
    ('cat-merged', 'cat-groceries', 0);
  INSERT INTO payee_mapping VALUES
    ('pay-old-store', 'pay-store', 0);

  INSERT INTO transactions VALUES
    ('tx-open', 'acct-checking', NULL, 500000, NULL, '',
     20230115, 'cleared', 1, 0, 0, NULL, NULL, 1, NULL, NULL, NULL, 0),
    ('tx-rent', 'acct-checking', 'cat-rent', -150000, 'pay-landlord', '',
     20230201, 'cleared', 0, 0, 0, NULL, NULL, 0, NULL, NULL, NULL, 0),
    ('tx-income', 'acct-checking', 'cat-income', 320000, 'pay-work', '',
     20230301, 'cleared', 0, 0, 0, NULL, NULL, 0, NULL, NULL, NULL, 0),
    ('tx-merged', 'acct-checking', 'cat-merged', -1000, 'pay-old-store', '',
     20250401, 'cleared', 0, 0, 0, NULL, NULL, 0, NULL, NULL, NULL, 0),
    ('tx-conflict', 'acct-checking', 'cat-groceries', -1200, 'pay-store',
     'Office trip #workTravel #workMeals', 20250402, 'cleared', 0, 0, 0,
     NULL, NULL, 0, NULL, NULL, NULL, 0),
    ('tx-split', 'acct-card', NULL, -9000, 'pay-store',
     '#workMeals', 20250310, 'cleared', 0, 1, 0, NULL, NULL, 0, NULL, NULL,
     NULL, 0),
    ('tx-split-1', 'acct-card', 'cat-meals', -5000, 'pay-store', 'half',
     20250310, 'cleared', 0, 0, 1, 'tx-split', NULL, 0, NULL, NULL, NULL, 0),
    ('tx-split-2', 'acct-card', 'cat-groceries', -4000, 'pay-store',
     'rest', 20250310, 'cleared', 0, 0, 1, 'tx-split', NULL, 0, NULL, NULL,
     NULL, 0),
    ('tx-card-spend', 'acct-card', 'cat-meals', -2500, 'pay-store', '',
     20250315, 'uncleared', 0, 0, 0, NULL, NULL, 0, NULL, NULL, NULL, 0),
    ('tx-transfer-out', 'acct-checking', NULL, -50000, 'pay-savings', '',
     20260105, 'cleared', 0, 0, 0, NULL, 'tx-transfer-in', 0, NULL, NULL,
     NULL, 0),
    ('tx-transfer-in', 'acct-savings', NULL, 50000, 'pay-savings', '',
     20260105, 'cleared', 0, 0, 0, NULL, 'tx-transfer-out', 0, NULL, NULL,
     NULL, 0),
    ('tx-brokerage-out', 'acct-checking', 'cat-rent', -100000, 'pay-brokerage',
     '', 20260205, 'cleared', 0, 0, 0, NULL, 'tx-brokerage-in', 0, NULL,
     NULL, NULL, 0),
    ('tx-brokerage-in', 'acct-brokerage', NULL, 100000, 'pay-brokerage', '',
     20260205, 'cleared', 0, 0, 0, NULL, 'tx-brokerage-out', 0, NULL, NULL,
     NULL, 0),
    ('tx-cardpay-out', 'acct-checking', NULL, -20000, 'pay-card', '',
     20260301, 'cleared', 0, 0, 0, NULL, 'tx-cardpay-in', 0, NULL, NULL,
     NULL, 0),
    ('tx-cardpay-in', 'acct-card', NULL, 20000, 'pay-card', '',
     20260301, 'cleared', 0, 0, 0, NULL, 'tx-cardpay-out', 0, NULL, NULL,
     NULL, 0),
    ('tx-current', 'acct-checking', 'cat-groceries', -4500, 'pay-store', '',
     20261001, 'uncleared', 0, 0, 0, NULL, NULL, 0, NULL, NULL, NULL, 0),
    ('tx-closed', 'acct-old', 'cat-groceries', -1000, 'pay-store', '',
     20230303, 'cleared', 0, 0, 0, NULL, NULL, 0, NULL, NULL, NULL, 0),
    ('tx-zero', 'acct-checking', 'cat-groceries', 0, 'pay-store', '',
     20261002, 'uncleared', 0, 0, 0, NULL, NULL, 0, NULL, NULL, NULL, 0),
    ('tx-deleted', 'acct-checking', 'cat-groceries', -9999, 'pay-store', '',
     20261003, 'cleared', 0, 0, 0, NULL, NULL, 0, NULL, NULL, NULL, 1);

  INSERT INTO zero_budgets VALUES
    ('zb-1', 202609, 'cat-rent', 150000, 1, 0, 0),
    ('zb-2', 202610, 'cat-rent', 150000, 0, 0, 0),
    ('zb-3', 202610, 'cat-groceries', 25000, 0, 0, 0),
    ('zb-4', 202303, 'cat-income', 320000, 0, 0, 0),
    ('zb-5', 202610, 'cat-deleted', 9900, 0, 0, 0),
    ('zb-6', 202610, 'cat-rent', 100, 0, 0, 1),
    ('zb-7', 202608, 'cat-meals', 0, 0, 0, 0);

  INSERT INTO schedules VALUES
    ('sch-rent', 'Rent', 20261101, -150000, 'acct-checking', 'pay-landlord',
     'rule-rent', 1, 0),
    ('sch-broken', 'Broken', 20261201, -5000, 'acct-checking', 'pay-landlord',
     'rule-broken', 1, 0);

  INSERT INTO rules VALUES
    ('rule-rent',
     '[{"field":"date","op":"isapprox","value":{"frequency":"monthly","interval":1}}]',
     '[{"op":"set","field":"category","value":"cat-rent"}]', 0),
    ('rule-broken', '[]',
     '[{"op":"set","field":"category","value":"cat-rent"}]', 0),
    ('rule-unused', '[]', '[]', 0);

  INSERT INTO notes VALUES
    ('cat-groceries', 'Food
#template 400.00', 0),
    ('cat-meals', '#template up to 100', 0),
    ('cat-rent', '#template 1500 by 2026-12', 0),
    ('cat-hidden', '#template not a number', 0);
''';
