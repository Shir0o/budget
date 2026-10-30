/// An amount of US dollars, held as whole cents. Never floating point.
final class Money implements Comparable<Money> {
  const Money(this.cents);

  final int cents;

  static const zero = Money(0);

  static const _minus = '−';

  static final _pattern = RegExp(
    r'^([-−])?\$?(\d{1,3}(?:,\d{3})+|\d+)?(?:\.(\d{0,2}))?$',
  );

  /// Parses user input such as `4,210.55`, `$3000`, `-12.5`, `12.` or `.99`.
  ///
  /// Returns null for anything that is not an exact cent amount
  /// (for example `1.234` or `12abc`).
  static Money? tryParse(String input) {
    final match = _pattern.firstMatch(input.trim());
    if (match == null) return null;
    final whole = match.group(2)?.replaceAll(',', '') ?? '';
    final fraction = match.group(3) ?? '';
    if (whole.isEmpty && fraction.isEmpty) return null;
    if (whole.length > 13) return null; // keeps cents well inside int range
    final dollars = whole.isEmpty ? 0 : int.parse(whole);
    final total = dollars * 100 + int.parse(fraction.padRight(2, '0'));
    return Money(match.group(1) == null ? total : -total);
  }

  bool get isNegative => cents < 0;
  bool get isPositive => cents > 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator -() => Money(-cents);

  /// `4,210.55`, or `−30.00` (with a true minus sign) when negative.
  String format() {
    final abs = cents.abs();
    final dollars = (abs ~/ 100).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+$)'),
      (_) => ',',
    );
    final fraction = (abs % 100).toString().padLeft(2, '0');
    return '${isNegative ? _minus : ''}$dollars.$fraction';
  }

  /// `$4,210.55`, or `−$30.00` when negative.
  String formatDollars() =>
      '${isNegative ? _minus : ''}\$${Money(cents.abs()).format()}';

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => formatDollars();
}
