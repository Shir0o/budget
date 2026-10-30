import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';

import 'services.dart';

/// What one fetch did, for the screen to show.
final class BankSyncOutcome {
  const BankSyncOutcome({
    required this.book,
    required this.accounts,
    required this.errors,
    this.message,
  });

  /// The book after the attempt. A request is counted even when it failed,
  /// because the bridge may have counted it. A failed attempt also leaves
  /// its message and any auth pause in the book.
  final SimpleFinBook book;

  /// Every account the bridge returned, for linking. Empty when nothing
  /// came back.
  final List<ClaimedAccount> accounts;

  /// The messages the fetch left to show, which are always shown and
  /// survive leaving the screen (ticket 03).
  final List<String> errors;

  /// What to tell the person, such as "Imported 2 new."
  final String? message;
}

/// Fetches by hand, inside this device's daily budget (ticket 10), and
/// applies what came back as one `bank-sync` Event group.
///
/// [save] persists the book, so today's request count survives a restart
/// and the next device window re-reads the last 10 days.
Future<BankSyncOutcome> fetchByHand({
  required BudgetEngine engine,
  required SimpleFinClient client,
  required SimpleFinBook book,
  required CivilDate today,
  required Future<void> Function(SimpleFinBook book) save,
}) => _fetch(
  engine: engine,
  client: client,
  book: book,
  today: today,
  save: save,
);

/// Fetches on the platform's schedule (ticket 10): only when the book says
/// one is due, so a background run never breaks the 6-hour gap, the day's
/// request budget or a paused link.
Future<BankSyncOutcome> fetchAutomatically({
  required BudgetEngine engine,
  required SimpleFinClient client,
  required SimpleFinBook book,
  required DateTime now,
  required Future<void> Function(SimpleFinBook book) save,
}) async {
  if (!book.automaticFetchDue(now)) {
    return _outcome(book);
  }
  return _fetch(
    engine: engine,
    client: client,
    book: book,
    today: CivilDate.fromDateTime(now.toLocal()),
    save: save,
    automaticAt: now,
  );
}

/// Keeps the platform's background fetch in step with [book] (ticket 10):
/// arranged while the bank is connected and the link works, stopped
/// otherwise, and stopped after an auth failure until the person re-links.
Future<void> syncBankSchedule(
  BankSyncScheduler scheduler,
  SimpleFinBook book,
) => book.connected && !book.automaticPaused
    ? scheduler.schedule()
    : scheduler.cancel();

Future<BankSyncOutcome> _fetch({
  required BudgetEngine engine,
  required SimpleFinClient client,
  required SimpleFinBook book,
  required CivilDate today,
  required Future<void> Function(SimpleFinBook book) save,
  DateTime? automaticAt,
}) async {
  final access = book.access;
  if (access == null) {
    return _outcome(book, message: 'Connect a bank first.');
  }
  if (!book.requests.canFetch(today)) {
    return _outcome(
      book,
      message:
          'No fetches left today. Bank sync allows '
          '${RequestCount.dailyLimit} a day; try again tomorrow.',
    );
  }

  // Count the request before it goes out, and remember an automatic
  // attempt so the next one waits 6 hours.
  var counted = book.requested(today);
  if (automaticAt != null) {
    counted = counted.attemptedAutomatically(automaticAt);
  }
  await save(counted);

  final FetchResult result;
  try {
    final window = counted.window(today);
    result = await client.fetch(
      access,
      start: window.start,
      end: window.end,
      today: today,
    );
  } on SimpleFinException catch (error) {
    final failure = BankError(
      message: error.message,
      day: today,
      auth: error.authFailed,
    );
    final failed = error.authFailed
        ? counted.needsRelink().withErrors([failure])
        : counted.withErrors([failure]);
    await save(failed);
    return _outcome(failed);
  } on Exception {
    final failed = counted.withErrors([
      BankError(message: 'Couldn’t reach SimpleFIN. Try again.', day: today),
    ]);
    await save(failed);
    return _outcome(failed);
  }

  final applied = engine.execute(
    ImportBankTransactions(
      entries: bankEntries(counted, result),
      fetchedAccounts: fetchedAccountIds(counted, result),
    ),
  );
  // A successful fetch proves the access URL works again, and the bridge's
  // own errors replace the last fetch's.
  counted = counted
      .recordedBalances(result)
      .fetched(today)
      .resumed()
      .withErrors([
        for (final message in result.errors)
          BankError(message: message, day: today),
      ]);
  await save(counted);

  return BankSyncOutcome(
    book: counted,
    accounts: result.accounts,
    errors: _messages(counted),
    message: switch (applied) {
      Accepted(:final events) => _importedMessage(events),
      Rejected(reason: Rejection.noChange) => 'No new transactions.',
      Rejected() => 'Bank sync was refused.',
    },
  );
}

BankSyncOutcome _outcome(SimpleFinBook book, {String? message}) =>
    BankSyncOutcome(
      book: book,
      accounts: const [],
      errors: _messages(book),
      message: message,
    );

List<String> _messages(SimpleFinBook book) => [
  for (final error in book.errors) error.message,
];

String _importedMessage(List<Event> events) {
  final created = events
      .where((event) => event.type == EventType.transactionCreated)
      .length;
  // One transaction can take several Events, such as a field change and a
  // new amount, so count the transactions touched. Dropped charges and
  // possible matches are said separately below.
  final touched = <Object?>{
    for (final event in events)
      if (event.type != EventType.transactionDeleted && !_proposesMatch(event))
        event.payload['transactionId'],
  }.length;
  final updated = touched - created;
  final proposed = events.where(_proposesMatch).length;
  final dropped = events
      .where((event) => event.type == EventType.transactionDeleted)
      .length;
  final imported = [
    if (created > 0) '$created new',
    if (updated > 0) '$updated updated',
  ].join(' and ');
  return [
    if (imported.isNotEmpty) 'Imported $imported.',
    if (proposed > 0)
      '$proposed possible ${proposed == 1 ? 'match' : 'matches'}.',
    if (dropped > 0)
      '$dropped pending ${dropped == 1 ? 'charge' : 'charges'} dropped.',
  ].join(' ');
}

/// Whether [event] offers a possible match (ticket 10, step 4).
bool _proposesMatch(Event event) =>
    event.type == EventType.transactionFieldsSet &&
    (event.payload['fields'] as Map)['pendingMatch'] != null;
