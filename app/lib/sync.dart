import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';

import 'budget_library.dart';
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

/// Rotates the open budget's Budget Key (ticket 12): seals a fresh snapshot
/// under a new key, deletes the files the old one sealed, and keeps the new
/// key on this device. Every other device is unpaired until it joins again.
Future<RotationOutcome> rotateKey({
  required BudgetEngine engine,
  required AppServices services,
  required SyncBook book,
}) async {
  final budget = engine.state.budget;
  if (budget == null) {
    return RotationOutcome(
      book: book,
      snapshotEvents: 0,
      deletedFiles: 0,
      error: 'Create the budget before turning on sync.',
    );
  }
  final newKey = BudgetKey.generate();
  final outcome = await SyncClient(drive: services.drive).rotate(
    engine: engine,
    oldKey: await services.keys.keyFor(budget.id),
    newKey: newKey,
    book: book,
    platform: engine.actor.value.split('@').last,
  );
  if (outcome.error != null) return outcome;
  // The new key only replaces the old one once Drive is re-sealed, so a
  // failed rotation leaves this device exactly as it was.
  await services.keys.writeKey(budget.id, newKey);
  await services.prefs.writeSyncBook(budget.id, outcome.book);
  return outcome;
}

/// What a pairing code did, for the Join screen.
final class JoinResult {
  const JoinResult({this.engine, this.error});

  /// The budget the device now holds, or null when the code was refused.
  final BudgetEngine? engine;

  /// What went wrong, or null when the budget is open.
  final String? error;
}

/// Joins another device's budget from its pairing code (ticket 12): reads the
/// budget straight from this Google account's Drive folder, keeps the key,
/// and makes the budget the open one. Nothing goes through a server.
Future<JoinResult> joinBudget({
  required BudgetLibrary library,
  required AppServices services,
  required String code,
}) async {
  final PairingPayload payload;
  try {
    payload = PairingPayload.parse(code);
  } on SyncException catch (error) {
    return JoinResult(error: error.message);
  }
  final outcome = await SyncClient(drive: services.drive)
      .join(budgetId: payload.budgetId, key: payload.key);
  final problem = outcome.error;
  if (problem != null) return JoinResult(error: problem);

  await services.keys.writeKey(payload.budgetId, payload.key);
  // Pairing starts this device's book over, so its own Events are written
  // again under the key it just learned.
  await services.prefs.writeSyncBook(
    payload.budgetId,
    SyncBook(enabled: true, devices: outcome.devices),
  );
  return JoinResult(
    engine: await library.join(id: payload.budgetId, events: outcome.events),
  );
}
