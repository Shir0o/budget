import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:budget_core/budget_core.dart';
import 'package:sqlite3/sqlite3.dart';

// What an Actual Budget export holds (ticket 01), read from `db.sqlite` and
// `metadata.json` in its zip. Every amount stays integer cents and every date
// becomes a CivilDate.

/// The export couldn't be read as an Actual zip or database.
final class ActualExportException implements Exception {
  const ActualExportException(this.message);

  final String message;

  @override
  String toString() => 'ActualExportException: $message';
}

/// The bytes of an export's `db.sqlite`, and its `metadata.json`.
abstract interface class ActualSource {
  Uint8List get database;
  Map<String, Object?>? get metadata;
}

/// An Actual export zip. The reader never writes the database anywhere or
/// keeps it after parsing.
final class ActualZip implements ActualSource {
  const ActualZip({required this.database, this.metadata});

  /// Reads `db.sqlite` and `metadata.json` out of [bytes].
  factory ActualZip.decode(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ActualExportException('That file isn’t an Actual export.');
    }
    final database = archive.findFile('db.sqlite')?.readBytes();
    if (database == null) {
      throw const ActualExportException(
        'That file isn’t an Actual export: the zip has no db.sqlite.',
      );
    }
    final metadataBytes = archive.findFile('metadata.json')?.readBytes();
    Map<String, Object?>? metadata;
    if (metadataBytes != null) {
      try {
        final decoded = jsonDecode(utf8.decode(metadataBytes));
        if (decoded is! Map) {
          throw const ActualExportException(
            'That file isn’t an Actual export: metadata.json isn’t an object.',
          );
        }
        metadata = decoded.cast<String, Object?>();
      } on FormatException {
        throw const ActualExportException(
          'That file isn’t an Actual export: metadata.json isn’t JSON.',
        );
      }
    }
    return ActualZip(database: database, metadata: metadata);
  }

  @override
  final Uint8List database;

  @override
  final Map<String, Object?>? metadata;
}

final class ActualAccount {
  const ActualAccount({
    required this.id,
    required this.name,
    required this.offBudget,
    required this.closed,
    this.type,
  });

  final String id;
  final String name;
  final bool offBudget;
  final bool closed;

  /// Actual's own account type, such as `checking`, `savings` or `credit`.
  final String? type;
}

final class ActualCategoryGroup {
  const ActualCategoryGroup({
    required this.id,
    required this.name,
    required this.isIncome,
    required this.hidden,
  });

  final String id;
  final String name;
  final bool isIncome;
  final bool hidden;
}

final class ActualCategory {
  const ActualCategory({
    required this.id,
    required this.name,
    required this.groupId,
    required this.isIncome,
    required this.hidden,
  });

  final String id;
  final String name;
  final String groupId;
  final bool isIncome;
  final bool hidden;
}

final class ActualPayee {
  const ActualPayee({
    required this.id,
    required this.name,
    this.transferAccountId,
  });

  final String id;
  final String name;

  /// Set on a payee that marks a transfer (ticket 01).
  final String? transferAccountId;
}

final class ActualTransaction {
  const ActualTransaction({
    required this.id,
    required this.accountId,
    required this.amountCents,
    required this.date,
    this.categoryId,
    this.payeeId,
    this.notes = '',
    this.cleared = ClearedStatus.uncleared,
    this.isParent = false,
    this.isChild = false,
    this.parentId,
    this.transferId,
    this.startingBalance = false,
  });

  final String id;
  final String accountId;

  /// Negative for an outflow.
  final int amountCents;
  final CivilDate date;

  /// Resolved through `category_mapping`, so merged Categories point at the
  /// one that remains.
  final String? categoryId;

  /// Resolved through `payee_mapping`.
  final String? payeeId;
  final String notes;
  final ClearedStatus cleared;

  /// A split parent. Its children carry the lines; its own amount is
  /// ignored.
  final bool isParent;
  final bool isChild;
  final String? parentId;

  /// The other row of a transfer.
  final String? transferId;
  final bool startingBalance;
}

final class ActualBudgetMonth {
  const ActualBudgetMonth({
    required this.month,
    required this.categoryId,
    required this.amountCents,
    required this.carryover,
  });

  final CalendarMonth month;
  final String categoryId;
  final int amountCents;

  /// Actual's per-Category "roll over overspending" flag, which has no
  /// equivalent here (ticket 14).
  final bool carryover;
}

final class ActualSchedule {
  const ActualSchedule({
    required this.id,
    required this.name,
    required this.amountCents,
    required this.nextDate,
    this.accountId,
    this.payeeId,
    this.categoryId,
    this.frequency,
    this.interval = 1,
  });

  final String id;
  final String name;

  /// Negative for an outflow.
  final int amountCents;
  final CivilDate nextDate;
  final String? accountId;
  final String? payeeId;

  /// Taken from the schedule's rule, when it sets one.
  final String? categoryId;

  /// `daily`, `weekly`, `monthly` or `yearly`, when the rule says.
  final String? frequency;
  final int interval;
}

final class ActualRule {
  const ActualRule({required this.id});

  final String id;
}

/// An Actual export, read into the tables the import needs (ticket 01).
final class ActualExport {
  const ActualExport({
    required this.budgetName,
    required this.accounts,
    required this.categoryGroups,
    required this.categories,
    required this.payees,
    required this.transactions,
    required this.budgetMonths,
    required this.schedules,
    required this.rules,
    required this.notes,
    required this.accountBalancesCents,
    this.trackingBudget = false,
  });

  /// Reads [source]. Throws [ActualExportException] when it isn't an Actual
  /// database.
  factory ActualExport.read(ActualSource source) {
    final directory = Directory.systemTemp.createTempSync('budget_import');
    final path = '${directory.path}/db.sqlite';
    try {
      File(path).writeAsBytesSync(source.database);
      final database = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        return _read(database, source.metadata);
      } finally {
        database.close();
      }
    } on ActualExportException {
      rethrow;
    } on Exception catch (error) {
      throw ActualExportException('db.sqlite can’t be read: $error');
    } finally {
      directory.deleteSync(recursive: true);
    }
  }

  final String budgetName;
  final List<ActualAccount> accounts;
  final List<ActualCategoryGroup> categoryGroups;
  final List<ActualCategory> categories;
  final List<ActualPayee> payees;
  final List<ActualTransaction> transactions;
  final List<ActualBudgetMonth> budgetMonths;
  final List<ActualSchedule> schedules;

  /// Listed in the import report, never imported (ADR 0003).
  final List<ActualRule> rules;

  /// The `notes` table: Category notes that may hold `#template` lines.
  final Map<String, String> notes;

  /// Actual's balance for each account: the sum of its transactions, split
  /// children rather than their parent.
  final Map<String, int> accountBalancesCents;

  /// Whether this export was made in tracking-budget mode, whose
  /// `reflect_budgets` table means Assignments are not imported (ticket 01).
  final bool trackingBudget;
}

ActualExport _read(Database database, Map<String, Object?>? metadata) {
  final accounts = _rows(
    database,
    'accounts',
    (row, has) => ActualAccount(
      id: _string(row, 'id')!,
      name: _string(row, 'name') ?? '',
      offBudget: _bool(row, 'offbudget'),
      closed: _bool(row, 'closed'),
      type: has('type') ? _string(row, 'type') : null,
    ),
  );

  final groups = _rows(
    database,
    'category_groups',
    (row, has) => ActualCategoryGroup(
      id: _string(row, 'id')!,
      name: _string(row, 'name') ?? '',
      isIncome: _bool(row, 'is_income'),
      hidden: _bool(row, 'hidden'),
    ),
  );

  final categories = _rows(
    database,
    'categories',
    (row, has) => ActualCategory(
      id: _string(row, 'id')!,
      name: _string(row, 'name') ?? '',
      groupId: _string(row, 'cat_group') ?? '',
      isIncome: _bool(row, 'is_income'),
      hidden: _bool(row, 'hidden'),
    ),
  );

  final categoryMapping = _mapping(database, 'category_mapping');
  final payeeMapping = _mapping(database, 'payee_mapping');

  final payees = _rows(
    database,
    'payees',
    (row, has) => ActualPayee(
      id: _string(row, 'id')!,
      name: _string(row, 'name') ?? '',
      transferAccountId: _string(row, 'transfer_acct'),
    ),
  );

  final transactions = _rows(database, 'transactions', (row, has) {
    final category = _string(row, 'category');
    final payee = _string(row, 'description');
    return ActualTransaction(
      id: _string(row, 'id')!,
      accountId: _string(row, 'acct') ?? '',
      amountCents: _cents(row['amount']),
      date: _date(row['date']),
      categoryId: category == null
          ? null
          : categoryMapping[category] ?? category,
      payeeId: payee == null ? null : payeeMapping[payee] ?? payee,
      notes: _string(row, 'notes') ?? '',
      cleared: _cleared(row),
      isParent: _bool(row, 'isParent'),
      isChild: _bool(row, 'isChild'),
      parentId: _string(row, 'parent_id'),
      transferId: _string(row, 'transferred_id'),
      startingBalance: _bool(row, 'starting_balance_flag'),
    );
  });

  final budgetMonths = _rows(database, 'zero_budgets', (row, has) {
    final category = _string(row, 'category');
    return ActualBudgetMonth(
      month: _month(row['month']),
      categoryId: category == null ? '' : categoryMapping[category] ?? category,
      amountCents: _cents(row['amount']),
      carryover: _bool(row, 'carryover'),
    );
  });

  final rules = _rows(
    database,
    'rules',
    (row, has) => ActualRule(id: _string(row, 'id')!),
  );
  final ruleRows = {
    for (final row in _select(database, 'rules'))
      _string(row, 'id')!: (
        conditions: _string(row, 'conditions'),
        actions: _string(row, 'actions'),
      ),
  };

  final schedules = _rows(database, 'schedules', (row, has) {
    final rule = _string(row, 'rule');
    final parsed = _ruleDecision(
      ruleRows[rule]?.conditions,
      ruleRows[rule]?.actions,
    );
    final category = parsed.categoryId;
    final payee = _string(row, 'payee');
    return ActualSchedule(
      id: _string(row, 'id')!,
      name: _string(row, 'name') ?? '',
      amountCents: _cents(row['value'] ?? row['amount']),
      nextDate: _date(row['next_date']),
      accountId: _string(row, 'account'),
      payeeId: payee == null ? null : payeeMapping[payee] ?? payee,
      categoryId: category == null
          ? null
          : categoryMapping[category] ?? category,
      frequency: parsed.frequency,
      interval: parsed.interval,
    );
  });

  final notes = <String, String>{
    for (final row in _select(database, 'notes'))
      ?_string(row, 'id'): _string(row, 'note') ?? '',
  };
  final balances = <String, int>{};
  for (final transaction in transactions) {
    if (transaction.isParent) continue;
    balances[transaction.accountId] =
        (balances[transaction.accountId] ?? 0) + transaction.amountCents;
  }

  return ActualExport(
    budgetName:
        _metadataText(metadata, 'budgetName') ??
        _metadataText(metadata, 'name') ??
        'Actual budget',
    accounts: accounts,
    categoryGroups: groups,
    categories: categories,
    payees: payees,
    transactions: transactions,
    budgetMonths: budgetMonths,
    schedules: schedules,
    rules: rules,
    notes: notes,
    accountBalancesCents: balances,
    trackingBudget: _exists(database, 'reflect_budgets'),
  );
}

/// The columns a table has, so an export from any Actual version reads.
Set<String> _columns(Database database, String table) => {
  for (final row in database.select('PRAGMA table_info("$table")'))
    row['name'] as String,
};

bool _exists(Database database, String table) => database.select(
  'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?',
  ['table', table],
).isNotEmpty;

/// Every non-tombstoned row of [table], read with its columns.
List<T> _rows<T>(
  Database database,
  String table,
  T Function(Row row, bool Function(String) has) read,
) {
  final columns = _columns(database, table);
  if (columns.isEmpty) return [];
  final has = columns.contains;
  final where = has('tombstone') ? ' WHERE tombstone = 0' : '';
  return [
    for (final row in database.select('SELECT * FROM "$table"$where'))
      read(row, has),
  ];
}

List<Row> _select(Database database, String table) {
  final columns = _columns(database, table);
  if (columns.isEmpty) return [];
  final where = columns.contains('tombstone') ? ' WHERE tombstone = 0' : '';
  return database.select('SELECT * FROM "$table"$where');
}

Map<String, String> _mapping(Database database, String table) {
  final columns = _columns(database, table);
  if (columns.isEmpty) return {};
  final target = columns.contains('targetId') ? 'targetId' : 'target';
  final where = columns.contains('tombstone') ? ' WHERE tombstone = 0' : '';
  final mapping = <String, String>{};
  for (final row in database.select('SELECT * FROM "$table"$where')) {
    final id = _string(row, 'id');
    final to = _string(row, target);
    if (id != null && to != null) mapping[id] = to;
  }
  return mapping;
}

String? _metadataText(Map<String, Object?>? metadata, String key) =>
    switch (metadata?[key]) {
      final String value when value.trim().isNotEmpty => value,
      _ => null,
    };

String? _string(Row row, String column) => switch (row[column]) {
  final String value => value,
  final int value => '$value',
  _ => null,
};

bool _bool(Row row, String column) => switch (row[column]) {
  final int value => value != 0,
  final bool value => value,
  final String value => value == '1' || value.toLowerCase() == 'true',
  _ => false,
};

/// Whole cents, never a rounded decimal (ticket 01).
int _cents(Object? value) => switch (value) {
  final int cents => cents,
  final String cents => int.parse(cents),
  null => 0,
  _ => throw ActualExportException('An amount is not whole cents: $value'),
};

ClearedStatus _cleared(Row row) {
  if (_bool(row, 'reconciled')) return ClearedStatus.reconciled;
  return switch (row['cleared']) {
    'reconciled' => ClearedStatus.reconciled,
    'cleared' || 1 || true => ClearedStatus.cleared,
    _ => ClearedStatus.uncleared,
  };
}

CivilDate _date(Object? value) => switch (value) {
  final int digits when digits >= 10000000 && digits <= 99999999 => CivilDate(
    digits ~/ 10000,
    digits ~/ 100 % 100,
    digits % 100,
  ),
  final String text when text.length == 8 && int.tryParse(text) != null =>
    _date(int.parse(text)),
  final String text when text.length >= 10 => CivilDate.parse(
    text.substring(0, 10),
  ),
  _ => throw ActualExportException('Not a date: $value'),
};

CalendarMonth _month(Object? value) => switch (value) {
  final int digits when digits >= 100000 && digits <= 999999 => CalendarMonth(
    digits ~/ 100,
    digits % 100,
  ),
  final String text when text.length == 6 && int.tryParse(text) != null =>
    _month(int.parse(text)),
  final String text when text.length >= 7 => CalendarMonth.parse(
    text.substring(0, 7),
  ),
  _ => throw ActualExportException('Not a month: $value'),
};

/// What a schedule's rule says about its Category and how often it repeats.
({String? categoryId, String? frequency, int interval}) _ruleDecision(
  String? conditions,
  String? actions,
) {
  String? categoryId;
  for (final action in _jsonList(actions)) {
    if (action['op'] == 'set' &&
        action['field'] == 'category' &&
        action['value'] is String) {
      categoryId = action['value'] as String;
    }
  }
  String? frequency;
  var interval = 1;
  for (final condition in _jsonList(conditions)) {
    final value = condition['value'];
    if (condition['op'] == 'isapprox' && value is Map) {
      if (value['frequency'] case final String name) frequency = name;
      if (value['interval'] case final int every) interval = every;
    }
  }
  return (categoryId: categoryId, frequency: frequency, interval: interval);
}

List<Map<String, Object?>> _jsonList(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map) item.cast<String, Object?>(),
    ];
  } on FormatException {
    return const [];
  }
}
