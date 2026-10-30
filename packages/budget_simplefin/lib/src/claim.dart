import 'package:budget_core/budget_core.dart';

// What a SimpleFIN fetch answers with (ticket 03). Amounts and balances
// arrive as decimal strings and are parsed to exact cents; they never pass
// through floating point.

/// Parses SimpleFIN's decimal string, such as `-48.20`, to exact cents.
///
/// Throws a [FormatException] for anything that isn't an exact cent amount,
/// so a bank's odd value is never silently rounded.
int simpleFinCents(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  final money = Money.tryParse(text.startsWith('+') ? text.substring(1) : text);
  if (money == null) throw FormatException('Not a decimal amount', text);
  return money.cents;
}

/// A calendar date from SimpleFIN's unix seconds, in UTC.
CivilDate simpleFinDate(int seconds) => CivilDate.fromDateTime(
  DateTime.fromMillisecondsSinceEpoch(
    seconds * Duration.millisecondsPerSecond,
    isUtc: true,
  ),
);

/// A bank's name for an account, cut to at most a last-4 suffix so a full
/// number is never stored (ticket 10).
String bankDisplayName(String name) => maskSensitiveNumbers(name)
    .replaceAllMapped(
      RegExp(r'\d{5,}'),
      (match) => match[0]!.substring(match[0]!.length - 4),
    );

/// One account as a fetch returned it, before it is linked to an app
/// account (ticket 10).
final class ClaimedAccount {
  const ClaimedAccount({
    required this.id,
    required this.institution,
    required this.name,
    required this.balance,
    required this.balanceDate,
    this.available,
    this.transactions = const [],
  });

  factory ClaimedAccount.fromJson(
    Map<String, Object?> json, {
    required CivilDate today,
  }) {
    final org = (json['org'] as Map?)?.cast<String, Object?>() ?? const {};
    return ClaimedAccount(
      id: json['id'] as String,
      institution: (org['name'] as String? ?? '').trim(),
      name: json['name'] as String? ?? '',
      balance: Money(simpleFinCents(json['balance'])),
      available: json['available-balance'] == null
          ? null
          : Money(simpleFinCents(json['available-balance'])),
      balanceDate: switch (json['balance-date']) {
        final int seconds when seconds > 0 => simpleFinDate(seconds),
        _ => today,
      },
      transactions: [
        for (final transaction
            in (json['transactions'] as List? ?? const []).cast<Map>())
          ClaimedTransaction.fromJson(
            transaction.cast<String, Object?>(),
            today: today,
          ),
      ],
    );
  }

  /// The bank's id for the account, which a link stores.
  final String id;

  /// The institution the account is at, such as `Sample Bank`.
  final String institution;

  /// The bank's name for the account, as it sent it.
  final String name;

  final Money balance;

  /// What the bank says is available, when it says. Null otherwise.
  final Money? available;

  final CivilDate balanceDate;
  final List<ClaimedTransaction> transactions;

  /// [name] with at most the last four digits of any number in it.
  String get displayName => bankDisplayName(name);
}

/// One transaction as a fetch returned it (ticket 03).
final class ClaimedTransaction {
  const ClaimedTransaction({
    required this.id,
    required this.date,
    required this.amount,
    required this.description,
    this.memo = '',
    this.pending = false,
  });

  factory ClaimedTransaction.fromJson(
    Map<String, Object?> json, {
    required CivilDate today,
  }) {
    // A pending charge can arrive with `posted: 0`, so it falls back to
    // when it happened, then to today.
    final posted = switch (json['posted']) {
      final int seconds when seconds > 0 => simpleFinDate(seconds),
      _ => null,
    };
    final transacted = switch (json['transacted_at']) {
      final int seconds when seconds > 0 => simpleFinDate(seconds),
      _ => null,
    };
    final payee = (json['payee'] as String? ?? '').trim();
    return ClaimedTransaction(
      id: json['id'] as String,
      date: posted ?? transacted ?? today,
      amount: Money(simpleFinCents(json['amount'])),
      description: payee.isEmpty
          ? (json['description'] as String? ?? '').trim()
          : payee,
      memo: (json['memo'] as String? ?? '').trim(),
      pending: json['pending'] == true,
    );
  }

  /// The bank's id for the transaction, which a later fetch matches on.
  final String id;
  final CivilDate date;

  /// Negative for an outflow.
  final Money amount;

  /// The bank's payee when it has one, otherwise its description.
  final String description;
  final String memo;
  final bool pending;
}

/// What one fetch answered: the accounts it returned and the bridge's
/// user-facing errors, which the app always shows (ticket 03).
final class FetchResult {
  const FetchResult({required this.accounts, required this.errors});

  factory FetchResult.fromJson(
    Map<String, Object?> json, {
    required CivilDate today,
  }) => FetchResult(
    accounts: [
      for (final account in (json['accounts'] as List? ?? const []).cast<Map>())
        ClaimedAccount.fromJson(account.cast<String, Object?>(), today: today),
    ],
    errors: [
      for (final error in (json['errors'] as List? ?? const []))
        if (error != null && error.toString().trim().isNotEmpty)
          error.toString().trim(),
    ],
  );

  final List<ClaimedAccount> accounts;

  /// Messages such as "Re-authenticate with your bank".
  final List<String> errors;
}
