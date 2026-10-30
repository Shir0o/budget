part of 'budget_state.dart';

// Scheduled Transactions and repeating-charge suggestions (ticket 10). A
// Scheduled Transaction is a projection: nothing here counts in the budget
// until a person enters it as a real Transaction.

/// A future or repeating transaction that has not happened yet. It is the
/// source of predicted expenses (ticket 08), never of a balance.
final class Schedule {
  const Schedule({
    required this.id,
    required this.accountId,
    required this.payee,
    required this.amount,
    required this.category,
    required this.every,
    required this.interval,
    required this.nextDue,
    this.memo = '',
  });

  /// Restores a Scheduled Transaction from its stored form, [toJson].
  static Schedule fromJson(String id, Map<String, Object?> json) => Schedule(
    id: id,
    accountId: json['accountId'] as String,
    payee: json['payee'] as String,
    amount: Money(json['amountCents'] as int),
    category: json['category'] as String,
    every: json['every'] as int,
    interval: TargetInterval.values.byName(json['interval'] as String),
    nextDue: CivilDate.parse(json['nextDue'] as String),
    memo: json['memo'] as String? ?? '',
  );

  final String id;
  final String accountId;
  final String payee;
  final String memo;

  /// Negative for an outflow, positive for income.
  final Money amount;

  /// A Category id for an outflow, [readyToAssignCategory] for income.
  final String category;

  /// 1 or more.
  final int every;
  final TargetInterval interval;

  /// The next date it comes due.
  final CivilDate nextDue;

  /// Whether the money comes in rather than goes out.
  bool get isInflow => amount.isPositive;

  /// Days or weeks, as opposed to months or years.
  bool get isShort =>
      interval == TargetInterval.days || interval == TargetInterval.weeks;

  /// The Repeating Target this stands for: its amount, recurrence and next
  /// due date (ticket 08). That is exactly what a Driven-by-schedule Target
  /// sums.
  RepeatingTarget get implied => RepeatingTarget(
    amount: Money(amount.cents.abs()),
    every: every,
    interval: interval,
    nextDue: nextDue,
  );

  /// The first due date in or after [month], for a monthly or longer
  /// interval.
  CivilDate dueFor(CalendarMonth month) => implied.dueFor(month);

  /// How many times it comes due in [month]. At most one for a monthly or
  /// longer interval.
  int occurrencesIn(CalendarMonth month) => isShort
      ? implied.dueDatesIn(month)
      : (CalendarMonth.of(dueFor(month)) == month ? 1 : 0);

  /// The month's predicted money movement: positive for income, negative
  /// for spending, and zero when it doesn't come due.
  Money predictedIn(CalendarMonth month) =>
      Money(amount.cents * occurrencesIn(month));

  /// The due date after [nextDue].
  CivilDate get following => isShort
      ? nextDue.addDays(every * (interval == TargetInterval.weeks ? 7 : 1))
      : nextDue.addMonths(every * (interval == TargetInterval.years ? 12 : 1));

  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'payee': payee,
    'memo': memo,
    'amountCents': amount.cents,
    'category': category,
    'every': every,
    'interval': interval.name,
    'nextDue': nextDue.toIso(),
  };

  /// With the fields given, as an edit or a revert sets them.
  Schedule _copyWith({
    String? accountId,
    String? payee,
    String? memo,
    Money? amount,
    String? category,
    int? every,
    TargetInterval? interval,
    CivilDate? nextDue,
  }) => Schedule(
    id: id,
    accountId: accountId ?? this.accountId,
    payee: payee ?? this.payee,
    memo: memo ?? this.memo,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    every: every ?? this.every,
    interval: interval ?? this.interval,
    nextDue: nextDue ?? this.nextDue,
  );
}

/// One repeating charge a person might want to make a Scheduled
/// Transaction (ticket 08). It is a suggestion only: nothing is written
/// until the person sets the schedule.
final class RecurringSuggestion {
  const RecurringSuggestion({
    required this.payee,
    required this.amount,
    required this.accountId,
    required this.category,
    required this.every,
    required this.interval,
    required this.nextDue,
    required this.count,
  });

  final String payee;

  /// The most recent transaction's amount, which the others are within
  /// 10% of.
  final Money amount;
  final String accountId;
  final String category;
  final int every;
  final TargetInterval interval;

  /// The date it is next expected.
  final CivilDate nextDue;

  /// How many transactions the pattern was found in.
  final int count;
}

/// The intervals a repeating charge is recognised at, with their length in
/// days (ticket 08).
const _repeats = [
  (7, 1, TargetInterval.weeks),
  (14, 2, TargetInterval.weeks),
  (31, 1, TargetInterval.months),
  (91, 3, TargetInterval.months),
  (365, 1, TargetInterval.years),
];

/// How far a gap may be from the interval's length, in days.
const _repeatSlack = 3;

extension ScheduleQueries on BudgetState {
  /// Every Scheduled Transaction, in the order they were added.
  List<Schedule> get schedules => List.unmodifiable(_schedules.values);

  /// Null when it doesn't exist or was deleted.
  Schedule? schedule(String id) => _schedules[id];

  /// The Scheduled Transactions that come out of [categoryId], which are the
  /// ones its Driven-by-schedule Target sums.
  List<Schedule> schedulesFor(String categoryId) => [
    for (final schedule in _schedules.values)
      if (!schedule.isInflow && schedule.category == categoryId) schedule,
  ];

  /// What [target] needs in [month] for [categoryId]. A Driven-by-schedule
  /// Target sums the implied Repeating target of each of the Category's
  /// Scheduled Transactions (ticket 08); every other kind answers for
  /// itself.
  Money neededFor(String categoryId, Target target, CalendarMonth month) {
    final before = availableBeforeAssigning(categoryId, month);
    if (target is! DrivenByScheduleTarget) return target.needed(month, before);
    var total = Money.zero;
    for (final schedule in schedulesFor(categoryId)) {
      total += schedule.implied.needed(month, before);
    }
    return total;
  }

  /// The payees that look like repeating charges but have no Scheduled
  /// Transaction yet, the newest payee first. Suggestions only: nothing is
  /// applied, and there is no Event to accept (ticket 08).
  List<RecurringSuggestion> recurringSuggestions() {
    final byPayee = <String, List<Transaction>>{};
    for (final transaction in _transactions.values.toList().reversed) {
      if (transaction.isTransfer || transaction.startingBalance) continue;
      if (transaction.lines.length != 1) continue;
      if (transaction.lines.single.category == null) continue;
      final payee = transaction.payee.trim();
      if (payee.isEmpty) continue;
      if (_schedules.values.any(
        (s) => s.payee.toLowerCase() == payee.toLowerCase(),
      )) {
        continue;
      }
      byPayee.putIfAbsent(payee, () => []).add(transaction);
    }
    return [
      for (final MapEntry(key: payee, value: charges) in byPayee.entries)
        ?_suggest(payee, charges..sort((a, b) => a.date.compareTo(b.date))),
    ];
  }

  /// The suggestion [charges] makes, or null when they don't form one
  /// (ticket 08): 3 or more, amounts within 10% of the latest, and every
  /// gap within 3 days of a recognised interval.
  RecurringSuggestion? _suggest(String payee, List<Transaction> charges) {
    if (charges.length < 3) return null;
    final latest = charges.last;
    for (final charge in charges) {
      if (!_withinTenPercent(charge.amount, latest.amount)) return null;
    }
    for (final (days, every, interval) in _repeats) {
      final regular = [
        for (var i = 1; i < charges.length; i++)
          _daysBetween(charges[i - 1].date, charges[i].date),
      ].every((gap) => (gap - days).abs() <= _repeatSlack);
      if (!regular) continue;
      return RecurringSuggestion(
        payee: payee,
        amount: latest.amount,
        accountId: latest.accountId,
        category: latest.lines.single.category!,
        every: every,
        interval: interval,
        nextDue: switch (interval) {
          TargetInterval.days ||
          TargetInterval.weeks => latest.date.addDays(days),
          _ => latest.date.addMonths(
            every * (interval == TargetInterval.years ? 12 : 1),
          ),
        },
        count: charges.length,
      );
    }
    return null;
  }
}

bool _withinTenPercent(Money amount, Money reference) =>
    (amount.cents - reference.cents).abs() * 10 <= reference.cents.abs();

int _daysBetween(CivilDate from, CivilDate to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
