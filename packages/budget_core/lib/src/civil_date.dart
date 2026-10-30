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
