import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

// Synthetic numbers only: 4111 1111 1111 1111 is the standard test card,
// and 123456780 is a made-up number with a valid ABA checksum.

List<(SensitiveNumberKind, String)> _found(String text) => [
  for (final n in findSensitiveNumbers(text))
    (n.kind, text.substring(n.start, n.end)),
];

void main() {
  group('findSensitiveNumbers (ticket 13)', () {
    test('finds a Luhn-valid card number, with spaces or dashes', () {
      expect(_found('card 4111 1111 1111 1111 lost'), [
        (SensitiveNumberKind.card, '4111 1111 1111 1111'),
      ]);
      expect(_found('4111-1111-1111-1111'), [
        (SensitiveNumberKind.card, '4111-1111-1111-1111'),
      ]);
      expect(_found('x4111111111111111y'), [
        (SensitiveNumberKind.card, '4111111111111111'),
      ]);
      expect(
        findSensitiveNumbers('4111 1111 1111 1111').single.digits,
        '4111111111111111',
      );
    });

    test('a card number must be 12 to 19 digits', () {
      // 12 digits, Luhn-valid.
      expect(_found('4111 1111 1117'), [
        (SensitiveNumberKind.card, '4111 1111 1117'),
      ]);
      // 11 digits in groups is not a card, and no group is 8 long.
      expect(_found('4111 1111 111'), isEmpty);
    });

    test('a 16-digit run that fails Luhn is still a long number', () {
      expect(_found('4111111111111112'), [
        (SensitiveNumberKind.other, '4111111111111112'),
      ]);
    });

    test('finds a 9-digit ABA routing number', () {
      expect(_found('routing 123456780'), [
        (SensitiveNumberKind.routing, '123456780'),
      ]);
      // A bad checksum is just another long number.
      expect(_found('123456789'), [(SensitiveNumberKind.other, '123456789')]);
    });

    test('finds any other run of 8 or more digits', () {
      expect(_found('acct 12345678'), [
        (SensitiveNumberKind.other, '12345678'),
      ]);
      expect(_found('1234567'), isEmpty);
    });

    test('leaves ordinary text alone', () {
      for (final text in [
        '',
        'Farmers market',
        r'$1,234.56 at 7-Eleven',
        'Nov 12 2026',
        '2026-11-12',
        'call 555-123-4567',
        '1234 5678 9012', // grouped, fails Luhn, no group of 8
      ]) {
        expect(containsSensitiveNumber(text), isFalse, reason: text);
      }
    });

    test('finds several in one text', () {
      expect(_found('4111 1111 1111 1111 and 12345678'), [
        (SensitiveNumberKind.card, '4111 1111 1111 1111'),
        (SensitiveNumberKind.other, '12345678'),
      ]);
    });
  });
}
