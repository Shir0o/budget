/// A calendar date with no time zone, as used for transaction dates.
final class CivilDate implements Comparable<CivilDate> {
  CivilDate(this.year, this.month, this.day) {
    final check = DateTime.utc(year, month, day);
    if (check.year != year || check.month != month || check.day != day) {
      throw ArgumentError('Not a calendar date: $year-$month-$day');
    }
  }

  /// The local calendar date of [time].
  factory CivilDate.fromDateTime(DateTime time) =>
      CivilDate(time.year, time.month, time.day);

  /// Parses `YYYY-MM-DD`.
  factory CivilDate.parse(String iso) {
    final parts = iso.split('-').map(int.parse).toList();
    if (parts.length != 3) throw FormatException('Not YYYY-MM-DD', iso);
    return CivilDate(parts[0], parts[1], parts[2]);
  }

  final int year;
  final int month;
  final int day;

  /// `YYYY-MM-DD`.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// [days] later, across month and year ends. Negative goes back.
  CivilDate addDays(int days) {
    final moved = DateTime.utc(year, month, day).add(Duration(days: days));
    return CivilDate(moved.year, moved.month, moved.day);
  }

  /// [months] later, on the same day or the month's last day. Negative goes
  /// back.
  CivilDate addMonths(int months) {
    final index = year * 12 + month - 1 + months;
    final moved = CalendarMonth(index ~/ 12, index % 12 + 1);
    final last = moved.next;
    final lastDay = DateTime.utc(
      last.year,
      last.month,
      1,
    ).subtract(const Duration(days: 1)).day;
    return CivilDate(moved.year, moved.month, day > lastDay ? lastDay : day);
  }

  @override
  int compareTo(CivilDate other) => toIso().compareTo(other.toIso());

  @override
  bool operator ==(Object other) =>
      other is CivilDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

/// A calendar month, such as November 2026. Budget math works per month
/// (ticket 07).
final class CalendarMonth implements Comparable<CalendarMonth> {
  CalendarMonth(this.year, this.month) {
    if (month < 1 || month > 12) {
      throw ArgumentError('Not a month: $year-$month');
    }
  }

  /// The month [date] falls in.
  factory CalendarMonth.of(CivilDate date) =>
      CalendarMonth(date.year, date.month);

  /// Parses `YYYY-MM`.
  factory CalendarMonth.parse(String iso) {
    final parts = iso.split('-').map(int.parse).toList();
    if (parts.length != 2) throw FormatException('Not YYYY-MM', iso);
    return CalendarMonth(parts[0], parts[1]);
  }

  final int year;
  final int month;

  CalendarMonth get next =>
      month == 12 ? CalendarMonth(year + 1, 1) : CalendarMonth(year, month + 1);

  CalendarMonth get previous =>
      month == 1 ? CalendarMonth(year - 1, 12) : CalendarMonth(year, month - 1);

  /// `YYYY-MM`.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  @override
  int compareTo(CalendarMonth other) =>
      (year * 12 + month).compareTo(other.year * 12 + other.month);

  @override
  bool operator ==(Object other) =>
      other is CalendarMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => toIso();
}
