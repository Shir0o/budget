import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';

/// What one hand-run fetch did, for the screen to show.
final class BankSyncOutcome {
  const BankSyncOutcome({
    required this.book,
    required this.accounts,
    required this.errors,
    this.message,
  });

  /// The book after the attempt. A request is counted even when it failed,
  /// because the bridge may have counted it.
  final SimpleFinBook book;

  /// Every account the bridge returned, for linking. Empty when nothing
  /// came back.
  final List<ClaimedAccount> accounts;

  /// The bridge's user-facing errors, which are always shown (ticket 03).
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
}) async {
  final access = book.access;
  if (access == null) {
    return BankSyncOutcome(
      book: book,
      accounts: const [],
      errors: const [],
      message: 'Connect a bank first.',
    );
  }
  if (!book.requests.canFetch(today)) {
    return BankSyncOutcome(
      book: book,
      accounts: const [],
      errors: const [],
      message:
          'No fetches left today. Bank sync allows '
          '${RequestCount.dailyLimit} a day; try again tomorrow.',
    );
  }

  // Count the request before it goes out.
  var counted = book.requested(today);
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
    return BankSyncOutcome(
      book: counted,
      accounts: const [],
      errors: const [],
      message: error.message,
    );
  } on Exception {
    return BankSyncOutcome(
      book: counted,
      accounts: const [],
      errors: const [],
      message: 'Couldn’t reach SimpleFIN. Try again.',
    );
  }

  final applied = engine.execute(
    ImportBankTransactions(entries: bankEntries(counted, result)),
  );
  counted = counted.fetched(today);
  await save(counted);

  return BankSyncOutcome(
    book: counted,
    accounts: result.accounts,
    errors: result.errors,
    message: switch (applied) {
      Accepted(:final events) => _importedMessage(events),
      Rejected(reason: Rejection.noChange) => 'No new transactions.',
      Rejected() => 'Bank sync was refused.',
    },
  );
}

String _importedMessage(List<Event> events) {
  final created = events
      .where((event) => event.type == EventType.transactionCreated)
      .length;
  // One transaction can take several Events, such as a field change and a
  // new amount, so count the transactions touched.
  final touched = <Object?>{
    for (final event in events) event.payload['transactionId'],
  }.length;
  final updated = touched - created;
  final parts = [
    if (created > 0) '$created new',
    if (updated > 0) '$updated updated',
  ].join(' and ');
  return 'Imported $parts.';
}
