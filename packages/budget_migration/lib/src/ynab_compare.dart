import 'dart:math' as math;

import 'package:budget_core/budget_core.dart';

import 'import_builder.dart';
import 'import_plan.dart';
import 'ynab_export.dart';

// The four-part comparison against the imported Actual history (ticket 14):
// month-end balances (a), transactions (b), Category months (c) and entities
// only in one file (d). Expected differences are labelled so they don't read
// as errors, and every YNAB-only item waits for a person's decision.

/// The four checks of ticket 14, in order.
enum ComparisonCheck {
  monthEndBalances('Month-end balances'),
  transactions('Transactions'),
  categoryMonths('Category months'),
  entities('Only in one file');

  const ComparisonCheck(this.title);

  final String title;

  /// `a` to `d`, as ticket 14 labels the checks.
  String get letter => 'abcd'[index];
}

/// What one finding of the comparison is.
enum ComparisonStatus {
  /// Both sides agree. Counted, never listed.
  matched,

  /// Both sides are there but differ, and the difference isn't expected.
  differs,

  /// Both sides are there and differ for a reason ticket 14 expects.
  expected,

  /// Only YNAB has it.
  ynabOnly,

  /// Only the imported budget has it.
  actualOnly,
}

/// A difference ticket 14 expects, so it is labelled rather than counted as
/// an error.
enum ExpectedDifference {
  /// Actual's per-Category roll-over overspending has no equivalent: a
  /// negative Available doesn't carry here (ticket 07).
  carryover('Actual’s roll-over overspending has no equivalent'),

  /// A Card Payment Category is derived here by replaying the card's history,
  /// so its Assigned, Activity and Available needn't match YNAB's.
  cardPayment('the card payment Category is derived here'),

  /// Income goes to Ready to Assign, one pool here rather than a month's
  /// Category balance (ticket 14).
  income('income goes to Ready to Assign here');

  const ExpectedDifference(this.why);

  /// A clause for the item's detail line.
  final String why;
}

/// Which names a [NamePair] is about.
enum PairKind { account, categoryGroup, category }

/// A YNAB name and the budget entity it pairs with. A [proposed] pair is a
/// fuzzy match the person still has to confirm (ticket 14, step 3).
final class NamePair {
  const NamePair({
    required this.kind,
    required this.ynabName,
    this.actualId,
    this.actualName,
    this.proposed = false,
  });

  final PairKind kind;
  final String ynabName;

  /// Null when the name has nothing to pair with.
  final String? actualId;
  final String? actualName;
  final bool proposed;

  bool get isPaired => actualId != null;

  NamePair _withActual(String? id, String? name) =>
      NamePair(kind: kind, ynabName: ynabName, actualId: id, actualName: name);
}

/// Every YNAB name paired with at most one budget entity, and the other way
/// round.
final class NamePairing {
  const NamePairing(this.pairs);

  final List<NamePair> pairs;

  NamePair? forName(PairKind kind, String ynabName) {
    for (final pair in pairs) {
      if (pair.kind == kind && pair.ynabName == ynabName) return pair;
    }
    return null;
  }

  String? actualIdFor(PairKind kind, String ynabName) =>
      forName(kind, ynabName)?.actualId;

  /// The fuzzy proposals the person has to confirm.
  List<NamePair> get proposed => [
    for (final pair in pairs)
      if (pair.proposed) pair,
  ];

  /// The same pairing with [ynabName] pointed at [actualId]. The entity is
  /// taken from any other YNAB name, so one budget entity is never counted
  /// twice.
  NamePairing withPair({
    required PairKind kind,
    required String ynabName,
    String? actualId,
    String? actualName,
  }) => NamePairing([
    for (final pair in pairs)
      if (pair.kind != kind)
        pair
      else if (pair.ynabName == ynabName)
        pair._withActual(actualId, actualName)
      else if (actualId != null && pair.actualId == actualId)
        pair._withActual(null, null)
      else
        pair,
  ]);
}

/// Pairs names across the two files: exact names first, then the best fuzzy
/// proposals for the person to confirm (ticket 14, step 3).
NamePairing proposePairs({
  required YnabExport ynab,
  required BudgetState actual,
}) {
  final pairs = <NamePair>[];
  _pairNames(pairs, PairKind.account, ynab.accountNames, [
    for (final account in actual.accounts) (account.id, account.name),
  ]);
  _pairNames(
    pairs,
    PairKind.categoryGroup,
    [
      for (final group in ynab.categoryGroupNames)
        if (!isIncomeCategory(group)) group,
    ],
    [for (final group in actual.categoryGroups) (group.id, group.name)],
  );
  _pairNames(
    pairs,
    PairKind.category,
    [
      for (final category in ynab.categoryNames)
        if (!isIncomeCategory(category)) category,
    ],
    [for (final category in actual.categories) (category.id, category.name)],
  );
  return NamePairing(pairs);
}

void _pairNames(
  List<NamePair> pairs,
  PairKind kind,
  List<String> ynabNames,
  List<(String, String)> actualNames,
) {
  final names = ynabNames.toSet().toList()..sort();
  final remainingActual = [...actualNames];
  for (final name in names) {
    final exact = remainingActual.where(
      (candidate) => _normalize(candidate.$2) == _normalize(name),
    );
    if (exact.isEmpty) continue;
    final (id, actualName) = exact.first;
    remainingActual.removeWhere((candidate) => candidate.$1 == id);
    pairs.add(
      NamePair(
        kind: kind,
        ynabName: name,
        actualId: id,
        actualName: actualName,
      ),
    );
  }

  // Every fuzzy candidate, strongest first, so the clearest proposal wins.
  final candidates = <({double score, String ynab, (String, String) actual})>[
    for (final name in names)
      if (!pairs.any((pair) => pair.kind == kind && pair.ynabName == name))
        for (final candidate in remainingActual)
          if (_score(name, candidate.$2) case final score when score >= 0.6)
            (score: score, ynab: name, actual: candidate),
  ]..sort((a, b) => b.score.compareTo(a.score));
  final takenYnab = <String>{};
  final takenActual = <String>{};
  for (final candidate in candidates) {
    if (!takenYnab.add(candidate.ynab)) continue;
    if (!takenActual.add(candidate.actual.$1)) continue;
    pairs.add(
      NamePair(
        kind: kind,
        ynabName: candidate.ynab,
        actualId: candidate.actual.$1,
        actualName: candidate.actual.$2,
        proposed: true,
      ),
    );
  }

  for (final name in names) {
    if (pairs.any((pair) => pair.kind == kind && pair.ynabName == name)) {
      continue;
    }
    pairs.add(NamePair(kind: kind, ynabName: name));
  }
}

String _normalize(String name) => name
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

double _score(String ynabName, String actualName) {
  final ynab = _normalize(ynabName);
  final actual = _normalize(actualName);
  if (ynab.isEmpty || actual.isEmpty) return 0;
  if (ynab == actual) return 1;
  if ((ynab.startsWith(actual) || actual.startsWith(ynab)) &&
      math.min(ynab.length, actual.length) >= 3) {
    return 0.85;
  }
  final ynabTokens = ynab.split(' ').toSet();
  final actualTokens = actual.split(' ').toSet();
  final shared = ynabTokens.intersection(actualTokens).length;
  final union = ynabTokens.union(actualTokens).length;
  if (shared > 0 && union > 0) return 0.5 + 0.4 * shared / union;
  var prefix = 0;
  while (prefix < ynab.length &&
      prefix < actual.length &&
      ynab[prefix] == actual[prefix]) {
    prefix++;
  }
  final ratio = prefix / math.max(ynab.length, actual.length);
  return ratio >= 0.6 ? 0.4 + 0.4 * ratio : 0;
}

/// Whether the person takes a YNAB-only item in or leaves it out.
enum PullChoice { add, ignore }

/// One decision about a YNAB-only item (ticket 14).
final class PullDecision {
  const PullDecision.add() : choice = PullChoice.add, reason = '';

  const PullDecision.ignore(this.reason) : choice = PullChoice.ignore;

  final PullChoice choice;

  /// Why it stays out, for [PullChoice.ignore].
  final String reason;

  bool get isAdd => choice == PullChoice.add;
}

/// One line of a YNAB-only transaction to add.
final class PullLine {
  const PullLine({required this.amountCents, this.categoryId, this.memo = ''});

  final int amountCents;

  /// A Category id, [readyToAssignCategory] for income, or null while
  /// uncategorized.
  final String? categoryId;
  final String memo;
}

/// One side of a YNAB-only transaction to add.
final class PullSide {
  const PullSide({
    required this.accountId,
    required this.date,
    required this.payee,
    required this.amountCents,
    required this.lines,
    required this.cleared,
    this.memo = '',
    this.importedCategory,
  });

  final String accountId;
  final CivilDate date;
  final String payee;

  /// Negative for an outflow.
  final int amountCents;
  final List<PullLine> lines;
  final ClearedStatus cleared;
  final String memo;

  /// The YNAB income Category an income line lost to Ready to Assign.
  final String? importedCategory;
}

/// Something YNAB has that the budget doesn't, waiting for a decision.
sealed class PullTarget {
  const PullTarget({required this.key});

  /// Stable across re-compares, so a decision isn't lost.
  final String key;
}

/// A YNAB-only transaction, added Unreviewed with nothing decided for it.
final class PullTransaction extends PullTarget {
  const PullTransaction({required super.key, required this.side});

  final PullSide side;
}

/// Both sides of a YNAB-only transfer between accounts on the same side of
/// the budget line, added together.
final class PullTransfer extends PullTarget {
  const PullTransfer({
    required super.key,
    required this.from,
    required this.to,
  });

  final PullSide from;
  final PullSide to;
}

/// A YNAB-only Category month, taken as its assignment; its activity follows
/// from the transactions pulled in.
final class PullAssignment extends PullTarget {
  const PullAssignment({
    required super.key,
    required this.categoryId,
    required this.month,
    required this.amountCents,
  });

  final String categoryId;
  final CalendarMonth month;
  final int amountCents;
}

/// One finding of the comparison.
final class ComparisonItem {
  const ComparisonItem({
    required this.check,
    required this.status,
    required this.label,
    this.detail = '',
    this.expected,
    this.ynabCents,
    this.actualCents,
    this.pull,
  });

  final ComparisonCheck check;
  final ComparisonStatus status;

  /// What the screen lists, such as `Everyday Checking · Mar 2024`.
  final String label;

  /// The difference in words, such as `YNAB $45.00 vs budget $40.00`.
  final String detail;

  /// Set on a [ComparisonStatus.expected] item.
  final ExpectedDifference? expected;

  /// The YNAB side's amount, when the item has one.
  final Money? ynabCents;

  /// The budget side's amount, when the item has one.
  final Money? actualCents;

  /// Set on a YNAB-only item that can be pulled in or skipped.
  final PullTarget? pull;
}

/// How one check came out.
final class ComparisonTally {
  const ComparisonTally({
    this.matched = 0,
    this.differs = 0,
    this.expected = 0,
    this.ynabOnly = 0,
    this.actualOnly = 0,
  });

  final int matched;
  final int differs;
  final int expected;
  final int ynabOnly;
  final int actualOnly;

  int get total => matched + differs + expected + ynabOnly + actualOnly;

  /// True when nothing real differs and nothing is YNAB-only. Expected
  /// differences don't make a check unclear on their own.
  bool get isClear => differs == 0 && ynabOnly == 0;
}

final class _Tally {
  var matched = 0;
  var differs = 0;
  var expected = 0;
  var ynabOnly = 0;
  var actualOnly = 0;

  void count(ComparisonStatus status) => switch (status) {
    ComparisonStatus.matched => matched++,
    ComparisonStatus.differs => differs++,
    ComparisonStatus.expected => expected++,
    ComparisonStatus.ynabOnly => ynabOnly++,
    ComparisonStatus.actualOnly => actualOnly++,
  };

  ComparisonTally build() => ComparisonTally(
    matched: matched,
    differs: differs,
    expected: expected,
    ynabOnly: ynabOnly,
    actualOnly: actualOnly,
  );
}

/// The four-part comparison of ticket 14, over YNAB's full date range.
final class YnabComparison {
  const YnabComparison({
    required this.ynab,
    required this.actual,
    required this.pairing,
    required this.items,
    required this.tallies,
  });

  final YnabExport ynab;
  final BudgetState actual;
  final NamePairing pairing;

  /// Every finding, in check order. Matches are counted, not listed.
  final List<ComparisonItem> items;
  final Map<ComparisonCheck, ComparisonTally> tallies;

  List<ComparisonItem> itemsFor(ComparisonCheck check) => [
    for (final item in items)
      if (item.check == check) item,
  ];

  ComparisonTally tallyFor(ComparisonCheck check) =>
      tallies[check] ?? const ComparisonTally();

  /// Every YNAB-only item the person can add or skip.
  List<ComparisonItem> get pullItems => [
    for (final item in items)
      if (item.pull != null) item,
  ];

  /// The pull items with no decision yet.
  List<ComparisonItem> unresolved(Map<String, PullDecision> decisions) => [
    for (final item in pullItems)
      if (!decisions.containsKey(item.pull!.key)) item,
  ];

  /// True when nothing differs and every YNAB-only item is decided.
  bool isClear(Map<String, PullDecision> decisions) => items.every(
    (item) =>
        item.status != ComparisonStatus.differs &&
        (item.pull == null || decisions.containsKey(item.pull!.key)),
  );
}

/// Compares [ynab] with the imported history in [actual] (ticket 14).
YnabComparison compareWithYnab({
  required YnabExport ynab,
  required BudgetState actual,
  required NamePairing pairing,
}) {
  final items = <ComparisonItem>[];
  final accounts = _accountIndex(ynab, actual, pairing);
  final months = _monthsBetween(ynab.firstMonth, ynab.lastMonth);
  final tallies = <ComparisonCheck, ComparisonTally>{
    ComparisonCheck.monthEndBalances: _monthEndBalances(
      items,
      ynab,
      actual,
      accounts,
      months,
    ),
    ComparisonCheck.transactions: _transactions(
      items,
      ynab,
      actual,
      accounts,
      pairing,
    ),
    ComparisonCheck.categoryMonths: _categoryMonths(
      items,
      ynab,
      actual,
      pairing,
    ),
    ComparisonCheck.entities: _entities(items, ynab, actual, pairing),
  };
  return YnabComparison(
    ynab: ynab,
    actual: actual,
    pairing: pairing,
    items: items,
    tallies: tallies,
  );
}

/// A paired account: its YNAB name, its budget id, and whether it counts in
/// the budget.
final class _Account {
  const _Account({
    required this.ynabName,
    required this.id,
    required this.onBudget,
  });

  final String ynabName;
  final String id;
  final bool onBudget;
}

List<_Account> _accountIndex(
  YnabExport ynab,
  BudgetState actual,
  NamePairing pairing,
) => [
  for (final name in ynab.accountNames)
    if (pairing.actualIdFor(PairKind.account, name) case final id?)
      if (actual.account(id) case final account?)
        _Account(ynabName: name, id: id, onBudget: account.type.onBudget),
];

List<CalendarMonth> _monthsBetween(CalendarMonth? first, CalendarMonth? last) {
  if (first == null || last == null) return const [];
  final months = <CalendarMonth>[];
  var month = first;
  while (month.compareTo(last) <= 0) {
    months.add(month);
    month = month.next;
  }
  return months;
}

/// (a) Each paired account's month-end balance in YNAB against the imported
/// history, with the size of a difference and the first month it appears
/// (ticket 14).
ComparisonTally _monthEndBalances(
  List<ComparisonItem> items,
  YnabExport ynab,
  BudgetState actual,
  List<_Account> accounts,
  List<CalendarMonth> months,
) {
  final tally = _Tally();
  for (final account in accounts) {
    final ynabEntries = [
      for (final entry in ynab.entries)
        if (entry.account == account.ynabName) entry,
    ]..sort((a, b) => a.date.compareTo(b.date));
    final actualTransactions = [
      for (final transaction in actual.transactions)
        if (transaction.accountId == account.id) transaction,
    ]..sort((a, b) => a.date.compareTo(b.date));
    var ynabRunning = 0;
    var actualRunning = 0;
    var ynabIndex = 0;
    var actualIndex = 0;
    CalendarMonth? firstDifference;
    for (final month in months) {
      final end = _monthEnd(month);
      while (ynabIndex < ynabEntries.length &&
          ynabEntries[ynabIndex].date.compareTo(end) <= 0) {
        ynabRunning += ynabEntries[ynabIndex].amountCents;
        ynabIndex++;
      }
      while (actualIndex < actualTransactions.length &&
          actualTransactions[actualIndex].date.compareTo(end) <= 0) {
        actualRunning += actualTransactions[actualIndex].amount.cents;
        actualIndex++;
      }
      if (ynabRunning == actualRunning) {
        tally.count(ComparisonStatus.matched);
        continue;
      }
      firstDifference ??= month;
      tally.count(ComparisonStatus.differs);
      items.add(
        ComparisonItem(
          check: ComparisonCheck.monthEndBalances,
          status: ComparisonStatus.differs,
          label: '${account.ynabName} · ${_monthLabel(month)}',
          detail:
              'YNAB ${Money(ynabRunning)} vs budget ${Money(actualRunning)}'
              '${firstDifference == month ? '' : ', first differed in ${_monthLabel(firstDifference)}'}',
          ynabCents: Money(ynabRunning),
          actualCents: Money(actualRunning),
        ),
      );
    }
  }
  return tally.build();
}

CivilDate _monthEnd(CalendarMonth month) =>
    CivilDate(month.next.year, month.next.month, 1).addDays(-1);

/// (b) Matches transactions on (account, date, signed amount), exact first and
/// then ±3 days when unique, and compares the fields of each match
/// (ticket 14).
ComparisonTally _transactions(
  List<ComparisonItem> items,
  YnabExport ynab,
  BudgetState actual,
  List<_Account> accounts,
  NamePairing pairing,
) {
  final tally = _Tally();
  final accountById = {for (final account in accounts) account.id: account};
  final accountByName = {
    for (final account in accounts) account.ynabName: account,
  };
  final actualTransactions = [
    for (final transaction in actual.transactions)
      if (accountById.containsKey(transaction.accountId)) transaction,
  ];
  final ynabEntries = [
    for (final entry in ynab.entries)
      if (accountByName.containsKey(entry.account) && entry.amountCents != 0)
        entry,
  ];

  // Exact matches first, keyed on (account, date, signed amount).
  final matchedYnab = <YnabEntry>{};
  final matchedActual = <Transaction>{};
  final byKey = <(String, CivilDate, int), List<Transaction>>{};
  for (final transaction in actualTransactions) {
    (byKey[(
              transaction.accountId,
              transaction.date,
              transaction.amount.cents,
            )] ??=
            [])
        .add(transaction);
  }
  final matches = <({YnabEntry entry, Transaction transaction})>[];
  for (final entry in ynabEntries) {
    final bucket =
        byKey[(
          accountByName[entry.account]!.id,
          entry.date,
          entry.amountCents,
        )];
    if (bucket == null || bucket.isEmpty) continue;
    final transaction = bucket.removeAt(0);
    matchedYnab.add(entry);
    matchedActual.add(transaction);
    matches.add((entry: entry, transaction: transaction));
  }
  final unmatchedYnab = [
    for (final entry in ynabEntries)
      if (!matchedYnab.contains(entry)) entry,
  ];
  final unmatchedActual = [
    for (final transaction in actualTransactions)
      if (!matchedActual.contains(transaction)) transaction,
  ];

  // Then a ±3-day neighbour, when both sides have only the one candidate.
  final byAmount = <(String, int), List<Transaction>>{};
  for (final transaction in unmatchedActual) {
    (byAmount[(transaction.accountId, transaction.amount.cents)] ??= []).add(
      transaction,
    );
  }
  final candidates = <({YnabEntry entry, Transaction transaction})>[
    for (final entry in unmatchedYnab)
      for (final transaction
          in byAmount[(accountByName[entry.account]!.id, entry.amountCents)] ??
              const <Transaction>[])
        if (transaction.date != entry.date &&
            _daysBetween(transaction.date, entry.date) <= 3)
          (entry: entry, transaction: transaction),
  ];
  final nearby = <({YnabEntry entry, Transaction transaction})>[];
  for (final candidate in candidates) {
    final rivalsForEntry = candidates
        .where((other) => identical(other.entry, candidate.entry))
        .length;
    final rivalsForActual = candidates
        .where((other) => identical(other.transaction, candidate.transaction))
        .length;
    if (rivalsForEntry != 1 || rivalsForActual != 1) continue;
    if (!unmatchedYnab.contains(candidate.entry) ||
        !unmatchedActual.contains(candidate.transaction)) {
      continue;
    }
    unmatchedYnab.remove(candidate.entry);
    unmatchedActual.remove(candidate.transaction);
    nearby.add(candidate);
  }
  matches.addAll(nearby);

  for (final match in matches) {
    final differences = _differences(match.entry, match.transaction, pairing);
    if (differences.isEmpty) {
      tally.count(ComparisonStatus.matched);
      continue;
    }
    tally.count(ComparisonStatus.differs);
    items.add(
      ComparisonItem(
        check: ComparisonCheck.transactions,
        status: ComparisonStatus.differs,
        label: '${match.entry.payee} · ${match.entry.date.toIso()}',
        detail:
            '${_amount(match.entry.amountCents)} · ${differences.join(' · ')}',
        ynabCents: Money(match.entry.amountCents),
        actualCents: match.transaction.amount,
      ),
    );
  }

  final ynabOnly = <({int index, YnabEntry entry, _Account account})>[];
  for (final entry in unmatchedYnab) {
    tally.count(ComparisonStatus.ynabOnly);
    ynabOnly.add((
      index: items.length,
      entry: entry,
      account: accountByName[entry.account]!,
    ));
    items.add(
      ComparisonItem(
        check: ComparisonCheck.transactions,
        status: ComparisonStatus.ynabOnly,
        label: '${entry.payee} · ${entry.date.toIso()}',
        detail: 'Only in YNAB · ${_amount(entry.amountCents)}',
        ynabCents: Money(entry.amountCents),
      ),
    );
  }
  for (final transaction in unmatchedActual) {
    tally.count(ComparisonStatus.actualOnly);
    items.add(
      ComparisonItem(
        check: ComparisonCheck.transactions,
        status: ComparisonStatus.actualOnly,
        label: '${transaction.payee} · ${transaction.date.toIso()}',
        detail: 'Only in the budget · ${transaction.amount}',
        actualCents: transaction.amount,
      ),
    );
  }

  _pullTargets(items, ynabOnly, pairing);
  return tally.build();
}

String _amount(int cents) => Money(cents).formatDollars();

int _daysBetween(CivilDate a, CivilDate b) => DateTime.utc(
  a.year,
  a.month,
  a.day,
).difference(DateTime.utc(b.year, b.month, b.day)).inDays.abs();

/// The fields ticket 14 compares on a match: payee, Category, memo and
/// cleared status. A match found within ±3 days says its date moved too.
List<String> _differences(
  YnabEntry entry,
  Transaction transaction,
  NamePairing pairing,
) {
  final differences = <String>[];
  if (entry.date != transaction.date) {
    differences.add('Date ${entry.date.toIso()} → ${transaction.date.toIso()}');
  }
  if (entry.isTransfer && transaction.isTransfer) {
    final target = entry.first.transferAccountName;
    final paired = target == null
        ? null
        : pairing.actualIdFor(PairKind.account, target);
    if (paired != null && paired != transaction.transferAccountId) {
      differences.add(
        'Transfer to “$target” → '
        '“${_accountName(pairing, transaction.transferAccountId)}”',
      );
    }
  } else if (!_sameText(entry.payee, transaction.payee)) {
    differences.add('Payee “${entry.payee}” → “${transaction.payee}”');
  }
  if (entry.cleared != transaction.cleared) {
    differences.add(
      'Cleared: ${_clearedLabel(entry.cleared)} → '
      '${_clearedLabel(transaction.cleared)}',
    );
  }
  final ynabLines = entry.rows;
  final actualLines = transaction.lines;
  if (ynabLines.length != actualLines.length) {
    differences.add('${ynabLines.length} lines → ${actualLines.length}');
  }
  for (final (index, ynabLine) in ynabLines.indexed) {
    if (index >= actualLines.length) break;
    final actualLine = actualLines[index];
    final expected = _categoryIdFor(ynabLine.category, pairing);
    if (expected != null && expected != actualLine.category) {
      differences.add(
        'Category “${ynabLine.category}” → '
        '${_categoryLabel(pairing, actualLine.category)}',
      );
    }
    if (!entry.isSplit) continue;
    if (!_sameText(ynabLine.memo, actualLine.memo)) {
      differences.add('Memo “${ynabLine.memo}” → “${actualLine.memo}”');
    }
  }
  if (!entry.isSplit && !_sameText(entry.first.memo, transaction.memo)) {
    differences.add('Memo “${entry.first.memo}” → “${transaction.memo}”');
  }
  return differences;
}

String _accountName(NamePairing pairing, String? accountId) {
  if (accountId == null) return 'none';
  for (final pair in pairing.pairs) {
    if (pair.kind == PairKind.account && pair.actualId == accountId) {
      return pair.actualName ?? accountId;
    }
  }
  return accountId;
}

String _categoryLabel(NamePairing pairing, String? categoryId) {
  if (categoryId == null) return 'none';
  if (categoryId == readyToAssignCategory) return 'Ready to Assign';
  for (final pair in pairing.pairs) {
    if (pair.kind == PairKind.category && pair.actualId == categoryId) {
      return pair.actualName ?? categoryId;
    }
  }
  return categoryId;
}

String _clearedLabel(ClearedStatus status) => switch (status) {
  ClearedStatus.uncleared => 'Uncleared',
  ClearedStatus.cleared => 'Cleared',
  ClearedStatus.reconciled => 'Reconciled',
};

bool _sameText(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// The Category id a YNAB Category becomes: Ready to Assign for income, the
/// paired Category, or null while unpaired.
String? _categoryIdFor(String? ynabCategory, NamePairing pairing) {
  if (ynabCategory == null) return null;
  if (isIncomeCategory(ynabCategory)) return readyToAssignCategory;
  return pairing.actualIdFor(PairKind.category, ynabCategory);
}

/// (c) Assigned, Activity and Available per paired Category and month, with
/// Actual's roll-over overspending and derived card payments labelled
/// (ticket 14).
ComparisonTally _categoryMonths(
  List<ComparisonItem> items,
  YnabExport ynab,
  BudgetState actual,
  NamePairing pairing,
) {
  final tally = _Tally();
  final byCategoryMonth = <(String, CalendarMonth), YnabPlanRow>{
    for (final row in ynab.plan)
      if (row.category case final category?) (category, row.month): row,
  };
  for (final row in ynab.plan) {
    final category = row.category;
    if (category == null) continue;
    final label = '$category · ${_monthLabel(row.month)}';
    if (row.isIncome) {
      if (row.assignedCents == 0 &&
          row.activityCents == 0 &&
          row.availableCents == 0) {
        tally.count(ComparisonStatus.matched);
        continue;
      }
      tally.count(ComparisonStatus.expected);
      items.add(
        ComparisonItem(
          check: ComparisonCheck.categoryMonths,
          status: ComparisonStatus.expected,
          expected: ExpectedDifference.income,
          label: label,
          detail:
              'Assigned ${_amount(row.assignedCents)} · '
              'Activity ${_amount(row.activityCents)} · '
              'Available ${_amount(row.availableCents)}; '
              '${ExpectedDifference.income.why}',
          ynabCents: Money(row.availableCents),
        ),
      );
      continue;
    }
    final categoryId = pairing.actualIdFor(PairKind.category, category);
    if (categoryId == null || actual.category(categoryId) == null) continue;
    final mapped = actual.category(categoryId)!;
    final assigned = actual.assigned(categoryId, row.month).cents;
    final activity = actual.activity(categoryId, row.month).cents;
    final available = actual.available(categoryId, row.month).cents;
    final cells = <String>[
      if (assigned != row.assignedCents)
        'Assigned ${_amount(row.assignedCents)} → ${_amount(assigned)}',
      if (activity != row.activityCents)
        'Activity ${_amount(row.activityCents)} → ${_amount(activity)}',
      if (available != row.availableCents)
        'Available ${_amount(row.availableCents)} → ${_amount(available)}',
    ];
    if (cells.isEmpty) {
      tally.count(ComparisonStatus.matched);
      continue;
    }
    final detail = cells.join(', ');
    final previous = byCategoryMonth[(category, row.month.previous)];
    final carriedNegative =
        previous != null &&
        previous.availableCents < 0 &&
        row.availableCents - available == previous.availableCents;
    final expected = mapped.cardAccountId != null
        ? ExpectedDifference.cardPayment
        : carriedNegative
        ? ExpectedDifference.carryover
        : null;
    if (expected != null) {
      tally.count(ComparisonStatus.expected);
      items.add(
        ComparisonItem(
          check: ComparisonCheck.categoryMonths,
          status: ComparisonStatus.expected,
          expected: expected,
          label: label,
          detail: '$detail; ${expected.why}',
          ynabCents: Money(row.availableCents),
          actualCents: Money(available),
        ),
      );
      continue;
    }
    // A month YNAB budgeted and this budget hasn't touched can be taken as
    // its assignment (ticket 14).
    if (assigned == 0 &&
        activity == 0 &&
        available == 0 &&
        row.assignedCents != 0) {
      tally.count(ComparisonStatus.ynabOnly);
      items.add(
        ComparisonItem(
          check: ComparisonCheck.categoryMonths,
          status: ComparisonStatus.ynabOnly,
          label: label,
          detail: '$detail; YNAB assigned it, this budget has nothing',
          ynabCents: Money(row.assignedCents),
          actualCents: Money.zero,
          pull: PullAssignment(
            key: 'month:$categoryId:${row.month.toIso()}',
            categoryId: categoryId,
            month: row.month,
            amountCents: row.assignedCents,
          ),
        ),
      );
      continue;
    }
    tally.count(ComparisonStatus.differs);
    items.add(
      ComparisonItem(
        check: ComparisonCheck.categoryMonths,
        status: ComparisonStatus.differs,
        label: label,
        detail: detail,
        ynabCents: Money(row.availableCents),
        actualCents: Money(available),
      ),
    );
  }
  return tally.build();
}

/// (d) Accounts, Category groups, Categories and payees in only one file.
ComparisonTally _entities(
  List<ComparisonItem> items,
  YnabExport ynab,
  BudgetState actual,
  NamePairing pairing,
) {
  final tally = _Tally();

  void add(
    ComparisonStatus status,
    String label, {
    ExpectedDifference? expected,
  }) {
    tally.count(status);
    if (status != ComparisonStatus.matched) {
      items.add(
        ComparisonItem(
          check: ComparisonCheck.entities,
          status: status,
          expected: expected,
          label: label,
        ),
      );
    }
  }

  final ynabAccounts = ynab.accountNames;
  for (final name in ynabAccounts) {
    add(
      pairing.actualIdFor(PairKind.account, name) != null
          ? ComparisonStatus.matched
          : ComparisonStatus.ynabOnly,
      'Account “$name”',
    );
  }
  final pairedAccounts = {
    for (final name in ynabAccounts)
      ?pairing.actualIdFor(PairKind.account, name),
  };
  for (final account in actual.accounts) {
    if (!pairedAccounts.contains(account.id)) {
      add(ComparisonStatus.actualOnly, 'Account “${account.name}”');
    }
  }

  for (final name in ynab.categoryGroupNames.toSet().toList()..sort()) {
    if (isIncomeCategory(name)) {
      add(
        ComparisonStatus.expected,
        'Category group “$name”',
        expected: ExpectedDifference.income,
      );
    } else {
      add(
        pairing.actualIdFor(PairKind.categoryGroup, name) != null
            ? ComparisonStatus.matched
            : ComparisonStatus.ynabOnly,
        'Category group “$name”',
      );
    }
  }
  final pairedGroups = {
    for (final pair in pairing.pairs)
      if (pair.kind == PairKind.categoryGroup) ?pair.actualId,
  };
  for (final group in actual.categoryGroups) {
    if (!pairedGroups.contains(group.id)) {
      add(ComparisonStatus.actualOnly, 'Category group “${group.name}”');
    }
  }

  for (final name in ynab.categoryNames.toSet().toList()..sort()) {
    if (isIncomeCategory(name)) continue;
    add(
      pairing.actualIdFor(PairKind.category, name) != null
          ? ComparisonStatus.matched
          : ComparisonStatus.ynabOnly,
      'Category “$name”',
    );
  }
  final pairedCategories = {
    for (final pair in pairing.pairs)
      if (pair.kind == PairKind.category) ?pair.actualId,
  };
  for (final category in actual.categories) {
    if (!pairedCategories.contains(category.id)) {
      add(ComparisonStatus.actualOnly, 'Category “${category.name}”');
    }
  }

  final ynabPayees = {for (final payee in ynab.payeeNames) _normalize(payee)};
  // A transfer's payee names its other account, which is matched as an
  // account rather than as a payee.
  final actualPayeeNames = {
    for (final transaction in actual.transactions)
      if (!transaction.isTransfer && transaction.payee.trim().isNotEmpty)
        transaction.payee.trim(),
  };
  final actualPayeeKeys = {
    for (final payee in actualPayeeNames) _normalize(payee),
  };
  for (final payee in ynab.payeeNames) {
    add(
      actualPayeeKeys.contains(_normalize(payee))
          ? ComparisonStatus.matched
          : ComparisonStatus.ynabOnly,
      'Payee “$payee”',
    );
  }
  for (final payee in actualPayeeNames.toList()..sort()) {
    if (!ynabPayees.contains(_normalize(payee))) {
      add(ComparisonStatus.actualOnly, 'Payee “$payee”');
    }
  }
  return tally.build();
}

/// Turns each YNAB-only transaction into something the person can add. A
/// transfer needs both of its sides, which must sit on the same side of the
/// budget line: one side alone would leave the budget uncategorized.
void _pullTargets(
  List<ComparisonItem> items,
  List<({int index, YnabEntry entry, _Account account})> ynabOnly,
  NamePairing pairing,
) {
  final claimed = <YnabEntry>{};
  var key = 0;
  for (final candidate in ynabOnly) {
    final entry = candidate.entry;
    if (claimed.contains(entry)) continue;
    final item = items[candidate.index];
    if (entry.isTransfer) {
      final target = entry.first.transferAccountName;
      ({int index, YnabEntry entry, _Account account})? other;
      for (final possible in ynabOnly) {
        if (possible.entry == entry ||
            claimed.contains(possible.entry) ||
            possible.entry.account != target ||
            possible.entry.first.transferAccountName != entry.account ||
            possible.entry.date != entry.date ||
            possible.entry.amountCents != -entry.amountCents) {
          continue;
        }
        other = possible;
        break;
      }
      if (other == null ||
          other.account.onBudget != candidate.account.onBudget) {
        items[candidate.index] = ComparisonItem(
          check: item.check,
          status: item.status,
          label: item.label,
          detail: '${item.detail}; add a transfer by hand',
          ynabCents: item.ynabCents,
          actualCents: item.actualCents,
        );
        continue;
      }
      claimed
        ..add(entry)
        ..add(other.entry);
      final targetItem = items[other.index];
      items[other.index] = ComparisonItem(
        check: targetItem.check,
        status: targetItem.status,
        label: targetItem.label,
        detail: '${targetItem.detail}; the other side of a transfer',
        ynabCents: targetItem.ynabCents,
        actualCents: targetItem.actualCents,
      );
      items[candidate.index] = ComparisonItem(
        check: item.check,
        status: item.status,
        label: item.label,
        detail: '${item.detail}; both sides of the transfer',
        ynabCents: item.ynabCents,
        actualCents: item.actualCents,
        pull: PullTransfer(
          key: 'transaction:${key++}',
          from: _side(entry, candidate.account, pairing, transfer: true),
          to: _side(other.entry, other.account, pairing, transfer: true),
        ),
      );
      continue;
    }
    claimed.add(entry);
    items[candidate.index] = ComparisonItem(
      check: item.check,
      status: item.status,
      label: item.label,
      detail: item.detail,
      ynabCents: item.ynabCents,
      actualCents: item.actualCents,
      pull: PullTransaction(
        key: 'transaction:${key++}',
        side: _side(entry, candidate.account, pairing),
      ),
    );
  }
}

PullSide _side(
  YnabEntry entry,
  _Account account,
  NamePairing pairing, {
  bool transfer = false,
}) {
  final income = !transfer && isIncomeCategory(entry.category);
  final categoryId = transfer ? null : _categoryIdFor(entry.category, pairing);
  final lines = entry.isSplit
      ? [
          for (final row in entry.rows)
            PullLine(
              amountCents: row.amountCents,
              categoryId: categoryId == null && transfer
                  ? null
                  : _categoryIdFor(row.category, pairing),
              memo: maskSensitiveNumbers(row.memo),
            ),
        ]
      : [
          PullLine(
            amountCents: entry.amountCents,
            // Money coming in with no Category is income; an outflow with
            // none waits in Review.
            categoryId: entry.amountCents > 0 && categoryId == null && !transfer
                ? readyToAssignCategory
                : categoryId,
          ),
        ];
  return PullSide(
    accountId: account.id,
    date: entry.date,
    payee: maskSensitiveNumbers(entry.payee),
    amountCents: entry.amountCents,
    lines: lines,
    cleared: entry.cleared,
    memo: entry.isSplit ? '' : maskSensitiveNumbers(entry.first.memo),
    importedCategory: income ? entry.category : null,
  );
}

/// Everything the person chose to pull in, as one import (ticket 14).
ImportBatch pullBatch({
  required YnabComparison comparison,
  required Map<String, PullDecision> decisions,
}) {
  final transactions = <ImportTransaction>[];
  final assignments = <ImportAssignment>[];
  var index = 0;
  for (final item in comparison.pullItems) {
    final decision = decisions[item.pull!.key];
    if (decision == null || !decision.isAdd) continue;
    switch (item.pull!) {
      case PullTransaction(:final side):
        transactions.add(_pullTransaction(side, 'ynab-transaction-${index++}'));
      case PullTransfer(:final from, :final to):
        final fromId = 'ynab-transaction-${index++}';
        final toId = 'ynab-transaction-${index++}';
        transactions
          ..add(_pullTransaction(from, fromId, transferTo: to, otherId: toId))
          ..add(_pullTransaction(to, toId, transferTo: from, otherId: fromId));
      case PullAssignment(:final categoryId, :final month, :final amountCents):
        if (amountCents != 0) {
          assignments.add(
            ImportAssignment(
              categoryId: categoryId,
              month: month,
              amount: Money(amountCents),
            ),
          );
        }
    }
  }
  return ImportBatch(
    accounts: const [],
    categoryGroups: const [],
    categories: const [],
    transactions: transactions,
    assignments: assignments,
    schedules: const [],
    targets: const [],
    expectedBalancesCents: const {},
  );
}

ImportTransaction _pullTransaction(
  PullSide side,
  String id, {
  PullSide? transferTo,
  String? otherId,
}) => ImportTransaction(
  id: id,
  accountId: side.accountId,
  date: side.date,
  amount: Money(side.amountCents),
  lines: [
    for (final line in side.lines)
      ImportLine(
        amount: Money(line.amountCents),
        category: line.categoryId,
        memo: line.memo,
        // Nothing decides a Business Tag or a Category for the person
        // (ADR 0003): a pulled-in line arrives Unreviewed.
        reviewed: false,
      ),
  ],
  payee: side.payee,
  memo: side.memo,
  cleared: side.cleared,
  transferAccountId: transferTo?.accountId,
  transferTransactionId: otherId,
  importedCategory: side.importedCategory,
);

/// Commits the chosen pull-ins as one group, revertable as a unit.
ImportCommit commitYnabPull(BudgetEngine engine, ImportBatch batch) =>
    commitImportBatch(engine, batch);

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _monthLabel(CalendarMonth month) =>
    '${_monthNames[month.month - 1]} ${month.year}';
