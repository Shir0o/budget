import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:budget_core/budget_core.dart';

// What a YNAB export holds (ticket 02): a zip with `<Budget> as of <date> -
// Register.csv` and `Plan.csv`. Amounts stay integer cents and dates become
// CivilDates, so the comparison against the imported history never rounds.

/// The export couldn't be read as a YNAB zip or CSV.
final class YnabExportException implements Exception {
  const YnabExportException(this.message);

  final String message;

  @override
  String toString() => 'YnabExportException: $message';
}

/// Which way a `3/4/2024` date reads. YNAB writes dates in the user's own
/// setting, so the two orders are told apart by sampling the rows (ticket 02).
enum YnabDateOrder { monthFirst, dayFirst, yearFirst }

/// The CSVs of a YNAB export, as text. The seam behind it lets a test read a
/// synthetic export without a zip.
abstract interface class YnabSource {
  String get budgetName;
  String get registerCsv;
  String get planCsv;

  /// The order the caller wants dates read in, or null to detect one.
  YnabDateOrder? get dateOrder;
}

/// A YNAB export zip. The reader never writes the file anywhere.
final class YnabZip implements YnabSource {
  const YnabZip({
    required this.budgetName,
    required this.registerCsv,
    required this.planCsv,
    this.dateOrder,
  });

  /// Reads `Register.csv` and `Plan.csv` out of [bytes]. [dateOrder] overrides
  /// the detected order, for the ambiguous case a person answers.
  factory YnabZip.decode(Uint8List bytes, {YnabDateOrder? dateOrder}) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const YnabExportException('That file isn’t a YNAB export.');
    }
    String? registerName;
    String? planName;
    for (final file in archive.files) {
      final name = file.name.toLowerCase();
      if (!name.endsWith('.csv')) continue;
      if (name.endsWith('register.csv')) {
        registerName = file.name;
      } else if (name.endsWith('plan.csv') || name.endsWith('budget.csv')) {
        planName = file.name;
      }
    }
    if (registerName == null) {
      throw const YnabExportException(
        'That file isn’t a YNAB export: the zip has no Register.csv.',
      );
    }
    final register = archive.findFile(registerName)!.readBytes()!;
    final planBytes = planName == null
        ? null
        : archive.findFile(planName)!.readBytes();
    final base = registerName.split('/').last;
    final asOf = base.toLowerCase().indexOf(' as of ');
    return YnabZip(
      budgetName: asOf < 0 ? 'YNAB budget' : base.substring(0, asOf),
      registerCsv: _text(register),
      planCsv: planBytes == null ? '' : _text(planBytes),
      dateOrder: dateOrder,
    );
  }

  @override
  final String budgetName;

  @override
  final String registerCsv;

  @override
  final String planCsv;

  @override
  final YnabDateOrder? dateOrder;
}

/// One row of `Register.csv`. Outflow and Inflow are both positive; the signed
/// amount is `inflow − outflow` (ticket 02).
final class YnabTransaction {
  const YnabTransaction({
    required this.account,
    required this.flag,
    required this.date,
    required this.payee,
    required this.outflowCents,
    required this.inflowCents,
    required this.cleared,
    this.category,
    this.categoryGroup,
    this.memo = '',
    this.splitIndex = 0,
    this.splitCount = 0,
  });

  final String account;

  /// A flag colour or custom flag label, blank when unflagged.
  final String flag;
  final CivilDate date;
  final String payee;

  /// The Category's name, or null for an uncategorized line.
  final String? category;
  final String? categoryGroup;
  final String memo;
  final int outflowCents;
  final int inflowCents;
  final ClearedStatus cleared;

  /// `n` in a `Split (n/m)` memo, 0 when the row isn't part of a split.
  final int splitIndex;
  final int splitCount;

  /// Negative for an outflow.
  int get amountCents => inflowCents - outflowCents;

  /// YNAB marks a transfer with the payee `Transfer : <account name>`.
  bool get isTransfer => transferAccountName != null;

  /// The other account's name for a transfer, or null.
  String? get transferAccountName {
    final colon = payee.indexOf(':');
    if (colon < 0) return null;
    if (payee.substring(0, colon).trim().toLowerCase() != 'transfer') {
      return null;
    }
    final name = payee.substring(colon + 1).trim();
    return name.isEmpty ? null : name;
  }
}

/// One row of `Plan.csv`. The same month and Category appears once.
final class YnabPlanRow {
  const YnabPlanRow({
    required this.month,
    required this.assignedCents,
    required this.activityCents,
    required this.availableCents,
    this.category,
    this.categoryGroup,
  });

  final CalendarMonth month;

  /// The Category's name, or null on a group's total row.
  final String? category;
  final String? categoryGroup;
  final int assignedCents;
  final int activityCents;
  final int availableCents;

  /// Income categories have no counterpart here: their lines go to Ready to
  /// Assign instead (ticket 14).
  bool get isIncome => isIncomeCategory(category);
}

/// Whether a YNAB Category is one of its income categories.
bool isIncomeCategory(String? name) {
  if (name == null) return false;
  final text = name.trim();
  return text.startsWith('Inflow:') || text == 'To be Budgeted';
}

/// One Register entry. A split's rows are folded back into one entry, as YNAB
/// flattens them into one row per line (ticket 02).
final class YnabEntry {
  const YnabEntry(this.rows);

  /// One row, or a split's lines in `Split (n/m)` order.
  final List<YnabTransaction> rows;

  YnabTransaction get first => rows.first;

  String get account => first.account;
  CivilDate get date => first.date;
  String get payee => first.payee;
  ClearedStatus get cleared => first.cleared;
  String? get category => first.category;
  String? get categoryGroup => first.categoryGroup;
  bool get isTransfer => first.isTransfer;
  bool get isSplit => rows.length > 1;

  /// The parent total, which is what a comparison keys on.
  int get amountCents => rows.fold(0, (total, row) => total + row.amountCents);
}

/// A YNAB export, read into the tables the comparison needs.
final class YnabExport {
  const YnabExport({
    required this.budgetName,
    required this.transactions,
    required this.plan,
    required this.entries,
    required this.dateOrder,
    required this.dateOrderAmbiguous,
  });

  /// Reads [source]. Throws [YnabExportException] when its CSVs aren't a YNAB
  /// export.
  factory YnabExport.read(YnabSource source) {
    final register = _csv(source.registerCsv);
    if (register.isEmpty) {
      throw const YnabExportException('Register.csv is empty.');
    }
    final registerHeader = _header(register.first);
    for (final column in const [
      'Account',
      'Date',
      'Payee',
      'Outflow',
      'Inflow',
    ]) {
      if (!registerHeader.containsKey(column.toLowerCase())) {
        throw YnabExportException('Register.csv has no $column column.');
      }
    }
    final detected = _detectDateOrder([
      for (final row in register.skip(1))
        if (_field(row, registerHeader, 'Date') case final text?
            when text.isNotEmpty)
          text,
    ]);
    final order = source.dateOrder ?? detected.order;
    final transactions = [
      for (final row in register.skip(1))
        ?_registerRow(row, registerHeader, order),
    ];

    final rows = source.planCsv.trim().isEmpty
        ? const <List<String>>[]
        : _csv(source.planCsv);
    final planHeader = rows.isEmpty
        ? const <String, int>{}
        : _header(rows.first);
    final assignedColumn = planHeader.containsKey('assigned')
        ? 'assigned'
        : 'budgeted';
    if (planHeader.isNotEmpty && !planHeader.containsKey(assignedColumn)) {
      throw const YnabExportException('Plan.csv has no Assigned column.');
    }
    final plan = [
      if (planHeader.isNotEmpty)
        for (final row in rows.skip(1))
          ?_planRow(row, planHeader, assignedColumn),
    ];

    return YnabExport(
      budgetName: source.budgetName,
      transactions: transactions,
      plan: plan,
      entries: _entries(transactions),
      dateOrder: order,
      dateOrderAmbiguous: source.dateOrder == null && detected.ambiguous,
    );
  }

  final String budgetName;
  final List<YnabTransaction> transactions;
  final List<YnabPlanRow> plan;

  /// [transactions] with each split folded back into one entry.
  final List<YnabEntry> entries;
  final YnabDateOrder dateOrder;

  /// True when every sampled day of the month was 12 or less, so the order
  /// can't be told from the file and the person has to say (ticket 02).
  final bool dateOrderAmbiguous;

  /// Every account the Register mentions, in the order it first appears.
  List<String> get accountNames =>
      {for (final transaction in transactions) transaction.account}.toList();

  /// Every Category Group and Category the Register or the Plan mentions.
  List<String> get categoryGroupNames => {
    for (final transaction in transactions) ?transaction.categoryGroup,
    for (final row in plan) ?row.categoryGroup,
  }.toList();

  List<String> get categoryNames => {
    for (final transaction in transactions) ?transaction.category,
    for (final row in plan) ?row.category,
  }.toList();

  /// Every payee the Register mentions except a transfer's, in the order it
  /// first appears.
  List<String> get payeeNames => {
    for (final transaction in transactions)
      if (!transaction.isTransfer && transaction.payee.trim().isNotEmpty)
        transaction.payee,
  }.toList();

  /// The first and last month the Register covers, or null when it's empty.
  CalendarMonth? get firstMonth => transactions.isEmpty
      ? null
      : transactions
            .map((transaction) => CalendarMonth.of(transaction.date))
            .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);

  CalendarMonth? get lastMonth => transactions.isEmpty
      ? null
      : transactions
            .map((transaction) => CalendarMonth.of(transaction.date))
            .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
}

String _text(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

/// The CSV's rows of fields. Handles quotes, `""` escapes and commas or line
/// breaks inside a field.
List<List<String>> _csv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var started = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }
    switch (char) {
      case '"':
        quoted = true;
        started = true;
      case ',':
        row.add(field.toString());
        field.clear();
        started = true;
      case '\r':
      case '\n':
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        if (started || field.isNotEmpty) {
          row.add(field.toString());
          rows.add(row);
        }
        row = <String>[];
        field.clear();
        started = false;
      default:
        field.write(char);
        started = true;
    }
  }
  if (started || field.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// Each header's column index, keyed by its lowercased name.
Map<String, int> _header(List<String> row) {
  final header = <String, int>{};
  for (final (index, name) in row.indexed) {
    header[name.trim().toLowerCase()] = index;
  }
  return header;
}

String? _field(List<String> row, Map<String, int> header, String column) {
  final index = header[column.toLowerCase()];
  if (index == null || index >= row.length) return null;
  return row[index].trim();
}

YnabTransaction? _registerRow(
  List<String> row,
  Map<String, int> header,
  YnabDateOrder order,
) {
  final date = _field(row, header, 'Date');
  final account = _field(row, header, 'Account');
  if (date == null || date.isEmpty || account == null || account.isEmpty) {
    return null;
  }
  final memo = _field(row, header, 'Memo') ?? '';
  final split = _splitPrefix.firstMatch(memo);
  final category = _empty(_field(row, header, 'Category'));
  return YnabTransaction(
    account: account,
    flag: _field(row, header, 'Flag') ?? '',
    date: _date(date, order),
    payee: _field(row, header, 'Payee') ?? '',
    category: category,
    categoryGroup: _empty(_field(row, header, 'Category Group')),
    memo: split == null ? memo : memo.substring(split.end).trim(),
    outflowCents: _cents(_field(row, header, 'Outflow') ?? ''),
    inflowCents: _cents(_field(row, header, 'Inflow') ?? ''),
    cleared: _cleared(_field(row, header, 'Cleared') ?? ''),
    splitIndex: split == null ? 0 : int.parse(split[1]!),
    splitCount: split == null ? 0 : int.parse(split[2]!),
  );
}

YnabPlanRow? _planRow(
  List<String> row,
  Map<String, int> header,
  String assignedColumn,
) {
  final month = _field(row, header, 'Month');
  if (month == null || month.isEmpty) return null;
  final category = _empty(_field(row, header, 'Category'));
  // A row without a Category is its group's total.
  if (category == null) return null;
  return YnabPlanRow(
    month: _planMonth(month),
    category: category,
    categoryGroup: _empty(_field(row, header, 'Category Group')),
    assignedCents: _cents(_field(row, header, assignedColumn) ?? ''),
    activityCents: _cents(_field(row, header, 'Activity') ?? ''),
    availableCents: _cents(_field(row, header, 'Available') ?? ''),
  );
}

String? _empty(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

/// `Split (1/2) half` marks a split line; its memo follows the prefix.
final _splitPrefix = RegExp(r'^Split \((\d+)/(\d+)\)\s*');

/// A date with the currency symbols and separators YNAB may write; whole
/// cents only (ticket 02).
int _cents(String text) {
  final value = text.trim();
  if (value.isEmpty) return 0;
  final parenthesised = value.startsWith('(') && value.endsWith(')');
  final inner = parenthesised ? value.substring(1, value.length - 1) : value;
  final amount = Money.tryParse(inner.replaceAll(' ', ''));
  if (amount == null) {
    throw YnabExportException('“$text” is not a cent amount.');
  }
  return parenthesised ? -amount.cents : amount.cents;
}

ClearedStatus _cleared(String text) => switch (text.trim().toLowerCase()) {
  'cleared' => ClearedStatus.cleared,
  'reconciled' => ClearedStatus.reconciled,
  _ => ClearedStatus.uncleared,
};

final _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

CalendarMonth _planMonth(String text) {
  final value = text.trim();
  if (RegExp(r'^\d{4}-\d{1,2}$').hasMatch(value)) {
    return CalendarMonth.parse(value);
  }
  final match = RegExp(r'^([A-Za-z]{3,})\.?\s+(\d{4})$').firstMatch(value);
  if (match == null) {
    throw YnabExportException('“$text” is not a month.');
  }
  final month = _months.indexOf(match[1]!.substring(0, 3).toLowerCase());
  if (month < 0) throw YnabExportException('“$text” is not a month.');
  return CalendarMonth(int.parse(match[2]!), month + 1);
}

/// A `3/4/2024`, `4/3/24` or `2024-03-04` date in [order].
CivilDate _date(String text, YnabDateOrder order) {
  final parts = text.trim().split(RegExp(r'[/.-]'));
  if (parts.length != 3) {
    throw YnabExportException('“$text” is not a date.');
  }
  final numbers = [for (final part in parts) int.tryParse(part.trim())];
  if (numbers.any((number) => number == null)) {
    throw YnabExportException('“$text” is not a date.');
  }
  final [first, second, third] = numbers.cast<int>();
  final (
    year,
    month,
    day,
  ) = order == YnabDateOrder.yearFirst || parts.first.trim().length == 4
      ? (first, second, third)
      : order == YnabDateOrder.dayFirst
      ? (third, second, first)
      : (third, first, second);
  try {
    return CivilDate(year < 100 ? 2000 + year : year, month, day);
  } on ArgumentError {
    throw YnabExportException('“$text” is not a date.');
  }
}

/// The order the sampled dates are written in, and whether the samples can't
/// tell the two apart (ticket 02).
({YnabDateOrder order, bool ambiguous}) _detectDateOrder(
  Iterable<String> dates,
) {
  var dayFirst = false;
  var monthFirst = false;
  for (final text in dates) {
    final parts = text.trim().split(RegExp(r'[/.-]'));
    if (parts.length != 3) continue;
    if (parts.first.trim().length == 4) {
      return (order: YnabDateOrder.yearFirst, ambiguous: false);
    }
    final first = int.tryParse(parts[0].trim());
    final second = int.tryParse(parts[1].trim());
    if (first == null || second == null) continue;
    if (first > 12) dayFirst = true;
    if (second > 12) monthFirst = true;
  }
  if (dayFirst && !monthFirst) {
    return (order: YnabDateOrder.dayFirst, ambiguous: false);
  }
  if (monthFirst) {
    return (order: YnabDateOrder.monthFirst, ambiguous: false);
  }
  return (
    order: dayFirst ? YnabDateOrder.dayFirst : YnabDateOrder.monthFirst,
    ambiguous: !dayFirst,
  );
}

/// Folds the flattened `Split (n/m)` rows back into one entry each (ticket 02).
List<YnabEntry> _entries(List<YnabTransaction> transactions) {
  final entries = <YnabEntry>[];
  var index = 0;
  while (index < transactions.length) {
    final row = transactions[index];
    if (row.splitCount > 1 && row.splitIndex == 1) {
      final rows = [row];
      var next = index + 1;
      while (next < transactions.length && rows.length < row.splitCount) {
        final line = transactions[next];
        if (line.splitIndex != rows.length + 1 ||
            line.splitCount != row.splitCount ||
            line.account != row.account ||
            line.date != row.date ||
            line.payee != row.payee) {
          break;
        }
        rows.add(line);
        next++;
      }
      if (rows.length == row.splitCount) {
        entries.add(YnabEntry(rows));
        index = next;
        continue;
      }
    }
    entries.add(YnabEntry([row]));
    index++;
  }
  return entries;
}
