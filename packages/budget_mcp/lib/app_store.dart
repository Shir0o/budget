/// The macOS side of `budget-mcp`: where the app keeps its files, the budget
/// registry Settings writes, and the store keys in the Keychain.
library;

import 'dart:io';

import 'package:budget_core/budget_core.dart' show Event;
import 'package:budget_store/budget_store.dart';

import 'src/budgets.dart';

export 'src/file_store.dart' show FileMcpStore;

/// The app's support folder, which `path_provider` names after the bundle
/// identifier. The app and `budget-mcp` both use it.
const appDirectoryName = 'io.github.shir0o.budget';

/// `/Applications/Budget.app/Contents/MacOS/budget-mcp`, the binary the DMG
/// ships next to the app (ticket 15). Settings shows it in the client config.
const bundledMcpCommand = '/Applications/Budget.app/Contents/MacOS/budget-mcp';

/// The app's support folder in the current user's home.
String get appSupportDirectory =>
    '${Platform.environment['HOME']}/Library/Application Support/$appDirectoryName';

/// This device's store keys. The app writes them through
/// flutter_secure_storage, whose macOS items are Keychain entries named
/// `store-key:<budgetId>`.
abstract interface class StoreKeys {
  Future<String?> keyHex(String budgetId);
}

/// Reads the store keys from the login Keychain, which asks once whether
/// `budget-mcp` may read each item.
final class KeychainStoreKeys implements StoreKeys {
  const KeychainStoreKeys();

  @override
  Future<String?> keyHex(String budgetId) async {
    final result = await Process.run('security', [
      'find-generic-password',
      '-a',
      'store-key:$budgetId',
      '-w',
    ]);
    if (result.exitCode != 0) return null;
    final key = (result.stdout as String).trim();
    return _hexKey.hasMatch(key) ? key : null;
  }
}

final _hexKey = RegExp(r'^[0-9a-fA-F]{64}$');

/// Opens each budget's SQLCipher store, with the key from [keys].
final class AppEventSource implements EventSource {
  const AppEventSource({
    required this.directory,
    this.keys = const KeychainStoreKeys(),
  });

  final String directory;
  final StoreKeys keys;

  @override
  Future<List<Event>> events(McpBudget budget) async {
    final key = await keys.keyHex(budget.id);
    if (key == null) {
      throw StateError('No store key for ${budget.id}; open the app once.');
    }
    final log = SqlCipherEventLog.open(
      '$directory/${budget.store}',
      keyHex: key,
    );
    try {
      return log.readAll();
    } finally {
      log.close();
    }
  }
}
