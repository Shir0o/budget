import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'bank_sync.dart';
import 'platform_services.dart';

/// WorkManager's entry point for the 6-hourly fetch (ticket 10). Android
/// runs it in its own isolate with no app state, so it starts a binding and
/// lets [runBackgroundBankFetch] rebuild what it needs.
@pragma('vm:entry-point')
void bankSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != bankSyncTask) return true;
    return runBackgroundBankFetch();
  });
}

/// One automatic fetch from a background isolate: the book and the open
/// budget come back out of secure storage, and [fetchAutomatically] sends
/// nothing unless the 6-hour gap, today's request budget and a working
/// link all allow it.
Future<bool> runBackgroundBankFetch() async {
  WidgetsFlutterBinding.ensureInitialized();
  const secrets = FlutterSecureStorage();
  final prefs = SecureDevicePrefs(secrets);
  final book = await prefs.readSimpleFinBook();
  final budgetId = await prefs.readLastBudgetId();
  final deviceId = await secrets.read(key: 'device-id');
  if (!book.connected ||
      book.automaticPaused ||
      budgetId == null ||
      deviceId == null) {
    return true;
  }

  final directory = await getApplicationSupportDirectory();
  final log = await SqlCipherBudgetStorage(
    secrets,
    directory: directory.path,
  ).openLog(budgetId);
  await fetchAutomatically(
    engine: BudgetEngine(log: log, deviceId: deviceId, actor: Actor.bankSync),
    client: SimpleFinClient(const HttpSimpleFinTransport()),
    book: book,
    now: DateTime.now(),
    save: prefs.writeSimpleFinBook,
  );
  // A failed fetch is not retried straight away: the next 6-hourly run is
  // the retry, and the bridge's messages are waiting on the screen.
  return true;
}
