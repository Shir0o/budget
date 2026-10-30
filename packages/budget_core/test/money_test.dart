import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

void main() {
  group('Money.tryParse', () {
    test('reads exact cent amounts', () {
      expect(Money.tryParse('4,210.55'), const Money(421055));
      expect(Money.tryParse('\$3000'), const Money(300000));
      expect(Money.tryParse('-12.5'), const Money(-1250));
      expect(Money.tryParse('−30.00'), const Money(-3000));
      expect(Money.tryParse('.99'), const Money(99));
      expect(Money.tryParse('12.'), const Money(1200));
      expect(Money.tryParse(' 0 '), Money.zero);
      expect(Money.tryParse('1,000,000.01'), const Money(100000001));
    });

    test('rejects anything that is not a cent amount', () {
      for (final input in ['', '.', '-', '\$', '1.234', '12abc', '1,2.00']) {
        expect(Money.tryParse(input), isNull, reason: input);
      }
    });
  });

  test('formats with grouping and a true minus sign', () {
    expect(const Money(41200).formatDollars(), '\$412.00');
    expect(const Money(421055).format(), '4,210.55');
    expect(const Money(-3000).formatDollars(), '−\$30.00');
    expect(const Money(5).format(), '0.05');
    expect(const Money(100000000).format(), '1,000,000.00');
  });

  test('adds and subtracts in cents', () {
    expect(const Money(10) + const Money(20), const Money(30));
    expect(const Money(10) - const Money(20), const Money(-10));
  });
}
