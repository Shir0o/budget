// Card and account numbers must never be stored (ticket 09) or handed to AI
// apps (ticket 13). These are ticket 13's patterns, as pure functions so the
// MCP server can reuse them for redaction.

/// What a number in some text looks like.
enum SensitiveNumberKind {
  /// 12–19 digits, spaces and dashes allowed, that pass the Luhn check.
  card,

  /// 9 digits with a valid ABA routing checksum.
  routing,

  /// Any other run of 8 or more digits.
  other,
}

/// One card-like, routing or other long number found in some text.
final class SensitiveNumber {
  const SensitiveNumber({
    required this.kind,
    required this.start,
    required this.end,
    required this.digits,
  });

  final SensitiveNumberKind kind;

  /// Where it sits in the text: `text.substring(start, end)`.
  final int start;
  final int end;

  /// Just the digits, without spaces or dashes.
  final String digits;
}

/// Digit groups joined by single spaces or dashes, such as `4111 1111`.
final _run = RegExp(r'\d+(?:[ -]\d+)*');
final _group = RegExp(r'\d+');

/// Every card-like number, routing number and other run of 8 or more digits
/// in [text], in order (ticket 13).
List<SensitiveNumber> findSensitiveNumbers(String text) {
  final found = <SensitiveNumber>[];
  for (final run in _run.allMatches(text)) {
    final groups = _group.allMatches(run[0]!).toList();
    var i = 0;
    while (i < groups.length) {
      // The longest span of groups from i that reads as a card number.
      int? cardEnd;
      for (var j = groups.length; j > i && cardEnd == null; j--) {
        final digits = groups.sublist(i, j).map((g) => g[0]).join();
        if (digits.length >= 12 && digits.length <= 19 && _luhn(digits)) {
          cardEnd = j;
        }
      }
      if (cardEnd != null) {
        found.add(
          SensitiveNumber(
            kind: SensitiveNumberKind.card,
            start: run.start + groups[i].start,
            end: run.start + groups[cardEnd - 1].end,
            digits: groups.sublist(i, cardEnd).map((g) => g[0]).join(),
          ),
        );
        i = cardEnd;
        continue;
      }
      final digits = groups[i][0]!;
      if (digits.length >= 8) {
        found.add(
          SensitiveNumber(
            kind: digits.length == 9 && _aba(digits)
                ? SensitiveNumberKind.routing
                : SensitiveNumberKind.other,
            start: run.start + groups[i].start,
            end: run.start + groups[i].end,
            digits: digits,
          ),
        );
      }
      i++;
    }
  }
  return found;
}

/// Whether [text] holds anything that looks like a card or account number.
bool containsSensitiveNumber(String text) =>
    findSensitiveNumbers(text).isNotEmpty;

/// [text] with each of its sensitive numbers cut to its last four digits,
/// such as `Card ••••1111`, so a payee or bank description never carries a
/// full number into the log (ticket 09).
String maskSensitiveNumbers(String text) {
  final found = findSensitiveNumbers(text);
  if (found.isEmpty) return text;
  final buffer = StringBuffer();
  var at = 0;
  for (final number in found) {
    final digits = number.digits;
    buffer
      ..write(text.substring(at, number.start))
      ..write('••••${digits.substring(digits.length - 4)}');
    at = number.end;
  }
  buffer.write(text.substring(at));
  return buffer.toString();
}

bool _luhn(String digits) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var d = digits.codeUnitAt(digits.length - 1 - i) - 0x30;
    if (i.isOdd) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 == 0;
}

/// 3·(d1 + d4 + d7) + 7·(d2 + d5 + d8) + (d3 + d6 + d9) ≡ 0 (mod 10).
bool _aba(String digits) {
  const weights = [3, 7, 1];
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += (digits.codeUnitAt(i) - 0x30) * weights[i % 3];
  }
  return sum % 10 == 0;
}
