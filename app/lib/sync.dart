import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';

import 'services.dart';

/// Runs one sync for the open budget: pulls every other device's folder,
/// merges the Events it finds, pushes this device's new ones into its own
/// folder, and saves this device's book (ticket 12).
///
/// The platform the manifest records is the Actor's, `android` or `mac`, so
/// the other device can name it without a device-name API.
Future<SyncOutcome> syncNow({
  required BudgetEngine engine,
  required AppServices services,
}) async {
  final budget = engine.state.budget;
  if (budget == null) {
    return SyncOutcome(
      book: SyncBook.off,
      pulled: 0,
      pushed: 0,
      needsAttention: const [],
      error: 'Create the budget before turning on sync.',
    );
  }
  final book = await services.prefs.readSyncBook(budget.id);
  final outcome = await SyncClient(drive: services.drive).sync(
    engine: engine,
    key: await services.keys.keyFor(budget.id),
    book: book,
    platform: engine.actor.value.split('@').last,
  );
  await services.prefs.writeSyncBook(budget.id, outcome.book);
  return outcome;
}
