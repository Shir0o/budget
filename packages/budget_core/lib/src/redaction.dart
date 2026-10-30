import 'sensitive_numbers.dart';

// Ticket 13: every string the MCP server returns is rewritten so an AI app
// never sees a card or account number. These are pure functions, so the
// rules are tested once and the server can't drift from them.

/// [text] with each card-like, routing or long number replaced:
/// `[card ••1234]`, `[routing]` or `[number ••1234]` (ticket 13).
String redactText(String text) {
  final found = findSensitiveNumbers(text);
  if (found.isEmpty) return text;
  final buffer = StringBuffer();
  var at = 0;
  for (final number in found) {
    buffer
      ..write(text.substring(at, number.start))
      ..write(_replacement(number));
    at = number.end;
  }
  buffer.write(text.substring(at));
  return buffer.toString();
}

/// [value] with every string in it redacted, at any depth, so a whole tool
/// result can go through one function (ticket 13). A map key [skipKey]
/// returns leaves its value alone, for opaque ids a client must send back.
Object? redactJson(Object? value, {bool Function(String key)? skipKey}) =>
    switch (value) {
      final String text => redactText(text),
      final Map<String, Object?> map => {
        for (final MapEntry(:key, :value) in map.entries)
          key: skipKey != null && skipKey(key)
              ? value
              : redactJson(value, skipKey: skipKey),
      },
      final List<Object?> list => [
        for (final item in list) redactJson(item, skipKey: skipKey),
      ],
      _ => value,
    };

/// An account name, cut to at most a last-4 suffix: a bank that puts the
/// full number in the name never passes it on (ticket 13).
String redactAccountName(String name) =>
    redactText(name).replaceAllMapped(_longDigits, _lastFour);

final _longDigits = RegExp(r'\d{5,}');

String _lastFour(Match match) {
  final digits = match[0]!;
  return '••••${digits.substring(digits.length - 4)}';
}

String _replacement(SensitiveNumber number) {
  final digits = number.digits;
  final last4 = digits.substring(digits.length - 4);
  return switch (number.kind) {
    SensitiveNumberKind.card => '[card ••$last4]',
    SensitiveNumberKind.routing => '[routing]',
    SensitiveNumberKind.other => '[number ••$last4]',
  };
}
