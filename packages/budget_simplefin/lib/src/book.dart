import 'package:budget_core/budget_core.dart';

import 'access.dart';
import 'claim.dart';

// This device's side of bank sync (ticket 10): the access URL, the accounts
// it has linked, and how much of today's request budget is spent. None of
// it is an Event: the access URL never leaves this device.

/// One SimpleFIN account linked to an app account, or set to ignore.
///
/// Only the bank's id, its institution and a name trimmed to at most a
/// last-4 suffix are kept; a full account number never is (ticket 10).
final class LinkedAccount {
  const LinkedAccount({
    required this.simpleFinId,
    required this.institution,
    required this.name,
    required this.linkedFrom,
    this.accountId,
    this.bankBalance,
    this.balanceDate,
  });

  factory LinkedAccount.fromJson(Map<String, Object?> json) => LinkedAccount(
    simpleFinId: json['simpleFinId'] as String,
    institution: json['institution'] as String? ?? '',
    name: json['name'] as String? ?? '',
    linkedFrom: CivilDate.parse(json['linkedFrom'] as String),
    accountId: json['accountId'] as String?,
    bankBalance: switch (json['bankBalanceCents']) {
      final int cents => Money(cents),
      _ => null,
    },
    balanceDate: switch (json['balanceDate']) {
      final String iso => CivilDate.parse(iso),
      _ => null,
    },
  );

  /// The bank's id for the account.
  final String simpleFinId;
  final String institution;

  /// The bank's name, trimmed to at most a last-4 suffix.
  final String name;

  /// Bank transactions dated before it are ignored, so history that was
  /// already entered by hand or migrated isn't pulled in again.
  final CivilDate linkedFrom;

  /// The app account it feeds. Null means ignored.
  final String? accountId;

  /// The balance the last fetch reported for it, or null before one. The
  /// app compares it with its own balance and shows a badge when they
  /// differ (ticket 10).
  final Money? bankBalance;

  /// The day [bankBalance] was for.
  final CivilDate? balanceDate;

  bool get ignored => accountId == null;

  /// This link with the bank's balance from a fetch.
  LinkedAccount withBalance(Money balance, CivilDate date) => LinkedAccount(
    simpleFinId: simpleFinId,
    institution: institution,
    name: name,
    linkedFrom: linkedFrom,
    accountId: accountId,
    bankBalance: balance,
    balanceDate: date,
  );

  /// This link without a bank balance: before the first fetch, or when the
  /// bank no longer reports the account.
  LinkedAccount withoutBalance() => LinkedAccount(
    simpleFinId: simpleFinId,
    institution: institution,
    name: name,
    linkedFrom: linkedFrom,
    accountId: accountId,
  );

  Map<String, Object?> toJson() => {
    'simpleFinId': simpleFinId,
    'institution': institution,
    'name': name,
    'linkedFrom': linkedFrom.toIso(),
    'accountId': accountId,
    'bankBalanceCents': bankBalance?.cents,
    'balanceDate': balanceDate?.toIso(),
  };

  @override
  bool operator ==(Object other) =>
      other is LinkedAccount &&
      other.simpleFinId == simpleFinId &&
      other.institution == institution &&
      other.name == name &&
      other.linkedFrom == linkedFrom &&
      other.accountId == accountId &&
      other.bankBalance == bankBalance &&
      other.balanceDate == balanceDate;

  @override
  int get hashCode => Object.hash(
    simpleFinId,
    institution,
    name,
    linkedFrom,
    accountId,
    bankBalance,
    balanceDate,
  );
}

/// How many fetches this device has made on [day] (ticket 10). The hard cap
/// keeps the bridge's 24-per-day limit untouched.
final class RequestCount {
  const RequestCount({this.day, this.used = 0});

  factory RequestCount.fromJson(Map<String, Object?> json) => RequestCount(
    day: switch (json['day']) {
      final String iso => CivilDate.parse(iso),
      _ => null,
    },
    used: json['used'] as int? ?? 0,
  );

  /// Ticket 10's hard cap per device per day.
  static const dailyLimit = 20;

  /// The day [used] counts, or null before the first fetch.
  final CivilDate? day;
  final int used;

  /// Fetches left on [today].
  int remaining(CivilDate today) =>
      day == today ? (dailyLimit - used).clamp(0, dailyLimit) : dailyLimit;

  bool canFetch(CivilDate today) => remaining(today) > 0;

  /// This day's count after one more fetch, never over [dailyLimit].
  RequestCount afterFetch(CivilDate today) {
    final usedToday = day == today ? used : 0;
    if (usedToday >= dailyLimit) return this;
    return RequestCount(day: today, used: usedToday + 1);
  }

  Map<String, Object?> toJson() => {'day': day?.toIso(), 'used': used};
}

/// The dates one fetch asks the bridge for (ticket 10).
final class FetchWindow {
  const FetchWindow({required this.start, required this.end});

  /// The longest window a single request may cover (ticket 03).
  static const maxDays = 90;

  /// How far back of the last successful fetch each request re-reads.
  static const recheckDays = 10;

  final CivilDate start;
  final CivilDate end;
}

/// This device's SimpleFIN connection: the access URL that only the device
/// running bank sync holds, the accounts it linked, and today's request
/// count.
///
/// [toJson] is for secure storage only. Nothing here is written to the
/// Event log.
final class SimpleFinBook {
  const SimpleFinBook({
    this.accessUrl,
    this.links = const [],
    this.requests = const RequestCount(),
    this.lastFetch,
  });

  factory SimpleFinBook.fromJson(Map<String, Object?> json) => SimpleFinBook(
    accessUrl: json['accessUrl'] as String?,
    links: [
      for (final link in (json['links'] as List? ?? const []).cast<Map>())
        LinkedAccount.fromJson(link.cast<String, Object?>()),
    ],
    requests: switch (json['requests']) {
      final Map requests => RequestCount.fromJson(
        requests.cast<String, Object?>(),
      ),
      _ => const RequestCount(),
    },
    lastFetch: switch (json['lastFetch']) {
      final String iso => CivilDate.parse(iso),
      _ => null,
    },
  );

  /// The access URL, credentials included. Null until the person connects
  /// a bank.
  final String? accessUrl;

  final List<LinkedAccount> links;

  /// Fetches made today, from this device's persisted count.
  final RequestCount requests;

  /// The day of the last successful fetch, which the next window re-reads
  /// 10 days before.
  final CivilDate? lastFetch;

  bool get connected => accessUrl != null;

  /// The access URL as a client uses it. Null until connected.
  SimpleFinAccess? get access =>
      accessUrl == null ? null : SimpleFinAccess(accessUrl!);

  LinkedAccount? linkFor(String simpleFinId) =>
      links.where((link) => link.simpleFinId == simpleFinId).firstOrNull;

  /// The links that feed a budget account, not the ignored ones.
  List<LinkedAccount> get linkedAccounts => [
    for (final link in links)
      if (link.accountId != null) link,
  ];

  /// This book, now holding [accessUrl].
  SimpleFinBook withAccess(String accessUrl) => SimpleFinBook(
    accessUrl: accessUrl,
    links: links,
    requests: requests,
    lastFetch: lastFetch,
  );

  /// This book, disconnected: no token and nothing linked.
  SimpleFinBook withoutAccess() => const SimpleFinBook();

  /// This book with one account linked, replacing any record for it.
  SimpleFinBook link(LinkedAccount link) => SimpleFinBook(
    accessUrl: accessUrl,
    links: [
      for (final existing in links)
        if (existing.simpleFinId != link.simpleFinId) existing,
      link,
    ],
    requests: requests,
    lastFetch: lastFetch,
  );

  /// Reserves one request from today's budget, before asking the bridge.
  SimpleFinBook requested(CivilDate today) => SimpleFinBook(
    accessUrl: accessUrl,
    links: links,
    requests: requests.afterFetch(today),
    lastFetch: lastFetch,
  );

  /// Records a successful fetch, so the next window re-reads the 10 days
  /// before [today].
  SimpleFinBook fetched(CivilDate today) => SimpleFinBook(
    accessUrl: accessUrl,
    links: links,
    requests: requests,
    lastFetch: today,
  );

  /// This book with the balance [result] reported for each linked account,
  /// so the app can compare it with its own (ticket 10). An account the
  /// fetch didn't return has none to compare.
  SimpleFinBook recordedBalances(FetchResult result) => SimpleFinBook(
    accessUrl: accessUrl,
    links: [
      for (final link in links)
        switch (result.accounts
            .where((account) => account.id == link.simpleFinId)
            .firstOrNull) {
          final account? => link.withBalance(
            account.balance,
            account.balanceDate,
          ),
          _ => link.withoutBalance(),
        },
    ],
    requests: requests,
    lastFetch: lastFetch,
  );

  /// Each linked account whose bank balance differs from the app's (cleared
  /// plus uncleared, pending included), by app account id (ticket 10).
  Map<String, Discrepancy> discrepancies(BudgetState state) {
    final found = <String, Discrepancy>{};
    for (final link in links) {
      final accountId = link.accountId;
      final balance = link.bankBalance;
      final date = link.balanceDate;
      if (accountId == null || balance == null || date == null) continue;
      final discrepancy = balanceDiscrepancy(
        state: state,
        accountId: accountId,
        bankBalance: balance,
        date: date,
      );
      if (discrepancy != null) found[accountId] = discrepancy;
    }
    return found;
  }

  /// The window one fetch asks for: at most 90 days back, never before the
  /// earliest linked-from date, and re-reading the 10 days before the last
  /// successful fetch (ticket 10).
  FetchWindow window(CivilDate today) {
    final floor = today.addDays(-FetchWindow.maxDays);
    final last = lastFetch;
    var start = last == null ? floor : last.addDays(-FetchWindow.recheckDays);
    if (start.compareTo(floor) < 0) start = floor;
    final earliest = links.map((link) => link.linkedFrom).fold<CivilDate?>(
      null,
      (earliest, date) {
        return earliest == null || date.compareTo(earliest) < 0
            ? date
            : earliest;
      },
    );
    if (earliest != null && earliest.compareTo(start) > 0) start = earliest;
    if (start.compareTo(today) > 0) start = today;
    return FetchWindow(start: start, end: today);
  }

  Map<String, Object?> toJson() => {
    'accessUrl': accessUrl,
    'links': [for (final link in links) link.toJson()],
    'requests': requests.toJson(),
    'lastFetch': lastFetch?.toIso(),
  };

  /// Never prints the access URL. Storage uses [toJson].
  @override
  String toString() =>
      'SimpleFinBook(connected: $connected, links: ${links.length}, '
      'requests: ${requests.used})';
}

/// The bank entries one fetch contributes to the budget: linked accounts
/// only, and only transactions dated on or after their account's
/// linked-from date (ticket 10).
List<BankEntry> bankEntries(SimpleFinBook book, FetchResult result) {
  final entries = <BankEntry>[];
  for (final account in result.accounts) {
    final link = book.linkFor(account.id);
    final accountId = link?.accountId;
    if (link == null || accountId == null) continue;
    for (final transaction in account.transactions) {
      if (transaction.date.compareTo(link.linkedFrom) < 0) continue;
      entries.add(
        BankEntry(
          accountId: accountId,
          bankId: transaction.id,
          date: transaction.date,
          amount: transaction.amount,
          description: transaction.description,
          memo: transaction.memo,
          pending: transaction.pending,
        ),
      );
    }
  }
  return entries;
}

/// The app accounts [result] covered, so a fetch can drop a pending charge
/// the bank no longer reports (ticket 10, step 3).
List<String> fetchedAccountIds(SimpleFinBook book, FetchResult result) => [
  for (final account in result.accounts) ?book.linkFor(account.id)?.accountId,
];

/// The linked-from date a new link starts at: the day after the app
/// account's newest transaction, so history already in the budget isn't
/// pulled in again (ticket 10). Never later than [today].
CivilDate defaultLinkedFrom(
  BudgetState state,
  String accountId,
  CivilDate today,
) {
  final newest = state.register(accountId).firstOrNull?.date;
  if (newest == null) return today;
  final next = newest.addDays(1);
  return next.compareTo(today) > 0 ? today : next;
}
