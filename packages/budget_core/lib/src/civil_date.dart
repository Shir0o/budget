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
