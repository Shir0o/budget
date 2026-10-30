import 'civil_date.dart';
import 'money.dart';

// Targets and Automation Mode (ticket 08). The Driven-by-schedule Target
// arrives with scheduled transactions (ticket 10).

/// Whether automation leaves a Category alone, proposes Assignments for it,
/// or makes them. Suggest is the default; Card Payment Categories default
/// to off.
enum AutomationMode { off, suggest, auto }

/// How often a [RepeatingTarget] comes due.
enum TargetInterval { days, weeks, months, years }

/// The amount a Category should reach. At most one per Category.
sealed class Target {
  const Target(this.amount);

  /// Restores a Target from its stored form, [toJson].
  static Target fromJson(Map<String, Object?> json) {
    final amount = Money(json['amountCents'] as int);
    return switch (json['kind']) {
      'repeating' => RepeatingTarget(
        amount: amount,
        every: json['every'] as int,
        interval: TargetInterval.values.byName(json['interval'] as String),
        nextDue: CivilDate.parse(json['nextDue'] as String),
      ),
      'byDate' => ByDateTarget(
        amount: amount,
        date: CivilDate.parse(json['date'] as String),
      ),
      'keepAtLeast' => KeepAtLeastTarget(amount: amount),
      final kind => throw FormatException('Unknown Target kind', kind),
    };
  }

  /// Positive.
  final Money amount;

  /// What the Category needs in [month], given its Available before
  /// assigning (Carry + Activity). Never negative.
  Money needed(CalendarMonth month, Money availableBeforeAssigning);

  Map<String, Object?> toJson();
}

/// [amount] every [every] [interval]s, next due on [nextDue].
final class RepeatingTarget extends Target {
  const RepeatingTarget({
    required Money amount,
    required this.every,
    required this.interval,
    required this.nextDue,
  }) : super(amount);

  /// 1 or more.
  final int every;
  final TargetInterval interval;
  final CivilDate nextDue;

  /// Days or weeks, as opposed to months or years.
  bool get isShort =>
      interval == TargetInterval.days || interval == TargetInterval.weeks;

  /// For a monthly or longer interval, the first due date in or after
  /// [month]. The due date moves on by the interval once it has passed.
  CivilDate dueFor(CalendarMonth month) {
    final step = every * (interval == TargetInterval.years ? 12 : 1);
    var k = 0;
    var due = nextDue;
    while (CalendarMonth.of(due).compareTo(month) < 0) {
      due = _addMonths(nextDue, ++k * step);
    }
    return due;
  }

  /// For days or weeks, how many due dates fall in [month].
  int dueDatesIn(CalendarMonth month) {
    final step = every * (interval == TargetInterval.weeks ? 7 : 1);
    final first = _dayNumber(CivilDate(month.year, month.month, 1));
    final last = _dayNumber(_lastDay(month));
    final due = _dayNumber(nextDue);
    if (due > last) return 0;
    final start = due >= first ? due : due + _ceilDiv(first - due, step) * step;
    return start > last ? 0 : (last - start) ~/ step + 1;
  }

  /// Monthly or longer: (A − Available before assigning) ÷ the months from
  /// [month] to the due month, inclusive, floored at 0 and rounded up to
  /// the cent, so the last month lands the total exactly. Days or weeks:
  /// A × the due dates in [month].
  @override
  Money needed(CalendarMonth month, Money availableBeforeAssigning) {
    if (isShort) return Money(amount.cents * dueDatesIn(month));
    final months = monthsThrough(month, CalendarMonth.of(dueFor(month)));
    return _share(amount - availableBeforeAssigning, months);
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'repeating',
    'amountCents': amount.cents,
    'every': every,
    'interval': interval.name,
    'nextDue': nextDue.toIso(),
  };
}

/// Save up [amount] by [date].
final class ByDateTarget extends Target {
  const ByDateTarget({required Money amount, required this.date})
    : super(amount);

  final CivilDate date;

  /// Whether [month] is after [date]'s month, when the Target is complete.
  /// It stays complete even if spending then drops Available below the
  /// amount.
  bool isCompleteIn(CalendarMonth month) =>
      month.compareTo(CalendarMonth.of(date)) > 0;

  /// (A − Available before assigning) ÷ the months left including [month],
  /// floored at 0 and rounded up to the cent. Zero once complete.
  @override
  Money needed(CalendarMonth month, Money availableBeforeAssigning) {
    if (isCompleteIn(month)) return Money.zero;
    final months = monthsThrough(month, CalendarMonth.of(date));
    return _share(amount - availableBeforeAssigning, months);
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'byDate',
    'amountCents': amount.cents,
    'date': date.toIso(),
  };
}

/// Top up to [amount] every month.
final class KeepAtLeastTarget extends Target {
  const KeepAtLeastTarget({required Money amount}) : super(amount);

  /// max(0, A − Available before assigning).
  @override
  Money needed(CalendarMonth month, Money availableBeforeAssigning) =>
      _share(amount - availableBeforeAssigning, 1);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'keepAtLeast',
    'amountCents': amount.cents,
  };
}

/// How many months from [from] to [to], both included. Zero when [to] is
/// before [from].
int monthsThrough(CalendarMonth from, CalendarMonth to) {
  final count = (to.year * 12 + to.month) - (from.year * 12 + from.month) + 1;
  return count < 0 ? 0 : count;
}

/// [remaining] ÷ [months], rounded up to the cent, or zero when nothing
/// remains.
Money _share(Money remaining, int months) => remaining.isPositive
    ? Money(_ceilDiv(remaining.cents, months))
    : Money.zero;

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

int _dayNumber(CivilDate date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

CivilDate _lastDay(CalendarMonth month) {
  final next = month.next;
  final day = DateTime.utc(
    next.year,
    next.month,
    1,
  ).subtract(const Duration(days: 1));
  return CivilDate(day.year, day.month, day.day);
}

/// [date] plus [months], on the same day or the month's last day.
CivilDate _addMonths(CivilDate date, int months) {
  final index = date.year * 12 + date.month - 1 + months;
  final month = CalendarMonth(index ~/ 12, index % 12 + 1);
  final last = _lastDay(month).day;
  return CivilDate(month.year, month.month, date.day > last ? last : date.day);
}
