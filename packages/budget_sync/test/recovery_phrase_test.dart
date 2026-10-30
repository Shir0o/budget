import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:test/test.dart';

/// BIP39's own English vectors for a 256-bit key, which is the length of a
/// Budget Key. All keys here are synthetic and fixed.
const _vectors = <(String, String)>[
  (
    '0000000000000000000000000000000000000000000000000000000000000000',
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon abandon abandon art',
  ),
  (
    '7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f',
    'legal winner thank year wave sausage worth useful legal winner thank year '
        'wave sausage worth useful legal winner thank year wave sausage worth '
        'title',
  ),
  (
    '8080808080808080808080808080808080808080808080808080808080808080',
    'letter advice cage absurd amount doctor acoustic avoid letter advice cage '
        'absurd amount doctor acoustic avoid letter advice cage absurd amount '
        'doctor acoustic bless',
  ),
];

void main() {
  group('Recovery phrase', () {
    test('spells a 256-bit key as BIP39’s 24 words', () async {
      for (final (hex, text) in _vectors) {
        final phrase = await RecoveryPhrase.of(BudgetKey.fromHex(hex));
        expect(phrase.words, hasLength(RecoveryPhrase.wordCount));
        expect(phrase.text, text);
      }
    });

    test('reads its own words back into the same key', () async {
      for (final (hex, text) in _vectors) {
        final phrase = await RecoveryPhrase.of(BudgetKey.fromHex(hex));
        final read = await RecoveryPhrase.parse(text.split(' '));
        expect(read.key.toHex(), hex);
        expect(read.words, phrase.words);
        // Spacing and case are the person's, not the phrase's.
        expect(
          (await RecoveryPhrase.parse(
            text.toUpperCase().replaceAll(' ', '   ').split(' '),
          )).key.toHex(),
          hex,
        );
      }
    });

    test('refuses a wrong word, a short phrase and a wrong checksum', () async {
      final (hex, text) = _vectors.first;
      final words = text.split(' ');

      // A word that isn't on the list.
      await expectLater(
        RecoveryPhrase.parse([...words]..[3] = 'budget'),
        throwsA(isA<SyncException>()),
      );
      // One word missing.
      await expectLater(
        RecoveryPhrase.parse(words.take(23)),
        throwsA(isA<SyncException>()),
      );
      // 24 words whose 8 checksum bits don't match the key they spell.
      await expectLater(
        RecoveryPhrase.parse([...words]..[23] = 'abandon'),
        throwsA(isA<SyncException>()),
      );
      // The untouched phrase still reads, so the refusals were the checks.
      expect((await RecoveryPhrase.parse(words)).key.toHex(), hex);
    });

    test('never prints the key or the words', () async {
      final phrase = await RecoveryPhrase.of(BudgetKey.fromHex(_vectors[1].$1));
      expect(phrase.toString(), 'RecoveryPhrase(<redacted>)');
      expect(phrase.toString(), isNot(contains(phrase.words.first)));
      expect(phrase.key.toString(), contains('<redacted>'));
      expect(phrase.key.toString(), isNot(contains(phrase.key.toHex())));
    });
  });
}
