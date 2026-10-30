import 'package:budget_core/budget_core.dart';
import 'package:test/test.dart';

// Synthetic numbers only: 4111 1111 1111 1111 is the standard test card,
// and 123456780 is a made-up number with a valid ABA checksum.

void main() {
  group('redactText (ticket 13)', () {
    test('replaces a Luhn-valid card number with its last four', () {
      expect(
        redactText('card 4111 1111 1111 1111 lost'),
        'card [card ••1111] lost',
      );
      expect(
        redactText('card 4111-1111-1111-1111 lost'),
        'card [card ••1111] lost',
      );
    });

    test('replaces an ABA routing number with [routing]', () {
      expect(redactText('routing 123456780'), 'routing [routing]');
    });

    test('replaces any other run of 8 or more digits', () {
      // 16 digits that fail Luhn are not a card.
      expect(redactText('4111111111111112'), '[number ••1112]');
      expect(
        redactText('acct 12345678 and 98765432'),
        'acct '
        '[number ••5678] and [number ••5432]',
      );
    });

    test('leaves ordinary text alone', () {
      for (final text in [
        '',
        'Farmers market',
        r'$1,234.56 at 7-Eleven',
        'Nov 12 2026',
        'call 555-123-4567',
      ]) {
        expect(redactText(text), text, reason: text);
      }
    });
  });

  group('redactAccountName (ticket 13)', () {
    test('cuts a full number to a last-4 suffix', () {
      expect(redactAccountName('Chase 000123456789'), 'Chase [number ••6789]');
      expect(redactAccountName('Chase ••1234'), 'Chase ••1234');
    });

    test('a shorter number is cut to four digits as well', () {
      expect(redactAccountName('Acct 12345'), 'Acct ••••2345');
      expect(redactAccountName('Everyday checking'), 'Everyday checking');
    });
  });
}
