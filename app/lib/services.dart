import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/widgets.dart';

/// Where each budget's [BudgetKey] is kept. The real one is Android
/// Keystore-backed secure storage; the key never goes in the Event log.
abstract interface class BudgetKeyStore {
  /// The key for [budgetId], created on first use.
  Future<BudgetKey> keyFor(String budgetId);

  /// The key for [budgetId] if one exists; never creates one. Viewing the
  /// recovery phrase must not mint a key that sync would later disagree with.
  Future<BudgetKey?> existingKey(String budgetId);

  /// Replaces the key for [budgetId], as rotating it does (ticket 12).
  Future<void> writeKey(String budgetId, BudgetKey key);
}

/// Settings that belong to this device, not to the budget, so they are not
/// Events and never sync.
abstract interface class DevicePrefs {
  Future<bool> readAppLockEnabled();
  Future<void> writeAppLockEnabled(bool enabled);
  Future<CivilDate?> readLastBackup();
  Future<void> writeLastBackup(CivilDate date);

  /// The ids of the budgets stored on this device, in the order they were made.
  Future<List<String>> readBudgetIds();
  Future<void> writeBudgetIds(List<String> ids);

  /// The budget that was open last, which the app opens next time.
  Future<String?> readLastBudgetId();
  Future<void> writeLastBudgetId(String id);

  /// The last month an automation run started on opening [budgetId] here
  /// (ticket 08).
  Future<CalendarMonth?> readAutomationMonth(String budgetId);
  Future<void> writeAutomationMonth(String budgetId, CalendarMonth month);

  /// This device's bank-sync connection and today's request count
  /// (ticket 10). Only the device that runs bank sync holds the access
  /// URL, and none of it is part of the budget.
  Future<SimpleFinBook> readSimpleFinBook();
  Future<void> writeSimpleFinBook(SimpleFinBook book);

  /// This device's sync state for [budgetId] (ticket 12). It is not an
  /// Event, so it never syncs, and sync is off until it says otherwise.
  Future<SyncBook> readSyncBook(String budgetId);
  Future<void> writeSyncBook(String budgetId, SyncBook book);
}

/// Hands a finished file to the person to save where they choose.
abstract interface class FileSaver {
  /// Returns false if they backed out.
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  });
}

/// Opens the phone's file dialog and hands back what the person picked.
abstract interface class FileLoader {
  /// Returns the file's bytes, or null if they backed out.
  Future<Uint8List?> pick({required List<String> extensions});
}

/// The phone's fingerprint or screen-lock check.
abstract interface class Authenticator {
  /// Whether this phone has a fingerprint or screen lock to check against.
  Future<bool> isSupported();

  /// Returns false if the check failed or was cancelled. With
  /// [biometricOnly] false, the phone's screen lock also counts.
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  });
}

/// Asks the platform to fetch while the app is closed (ticket 10). The app
/// decides when it should run; the platform only decides how.
abstract interface class BankSyncScheduler {
  /// Arranges one fetch at most every [FetchSchedule.interval] (6 hours).
  /// Calling it when the work is already arranged changes nothing.
  Future<void> schedule();

  /// Stops it: the bank was disconnected, or the link needs re-making.
  Future<void> cancel();
}

/// Everything the app needs from the device, in one place so tests and
/// previews can swap it.
final class AppServices {
  AppServices({
    required this.keys,
    required this.prefs,
    required this.saver,
    required this.authenticator,
    FileLoader? loader,
    SimpleFinTransport? simpleFin,
    BankSyncScheduler? scheduler,
    DriveGateway? drive,
    this.mcp,
    bool appLockEnabled = false,
  }) : appLockEnabled = ValueNotifier(appLockEnabled),
       loader = loader ?? InMemoryFileLoader(),
       simpleFin = SimpleFinClient(simpleFin ?? FakeSimpleFinTransport()),
       scheduler = scheduler ?? FakeBankSyncScheduler(),
       drive = drive ?? InMemoryDrive();

  /// In-memory services for tests and previews.
  factory AppServices.inMemory() => AppServices(
    keys: InMemoryBudgetKeyStore(),
    prefs: InMemoryDevicePrefs(),
    saver: InMemoryFileSaver(),
    authenticator: FakeAuthenticator(),
    mcp: InMemoryMcpStore(),
  );

  final BudgetKeyStore keys;
  final DevicePrefs prefs;
  final FileSaver saver;
  final FileLoader loader;
  final Authenticator authenticator;

  /// The SimpleFIN Bridge client. Tests answer through their own
  /// [SimpleFinTransport], so nothing goes to the network.
  final SimpleFinClient simpleFin;

  /// The platform's background fetch (ticket 10). Tests record calls
  /// instead of arranging anything.
  final BankSyncScheduler scheduler;

  /// The Google Drive app data folder sync writes to. Tests and previews
  /// keep it in memory, so nothing leaves the device.
  final DriveGateway drive;

  /// The budgets and settings shared with the `budget-mcp` binary (ticket
  /// 13). The MCP server is macOS only, so this is null where it can't run.
  final McpStore? mcp;

  /// Whether the app lock is on. Read at launch so the first frame is
  /// already locked.
  final ValueNotifier<bool> appLockEnabled;

  var _holds = 0;

  /// True while [keepUnlocked] is running.
  bool get lockHeld => _holds > 0;

  Future<void> setAppLockEnabled(bool enabled) async {
    await prefs.writeAppLockEnabled(enabled);
    appLockEnabled.value = enabled;
  }

  /// Runs [action] without the app lock engaging if the app goes to the
  /// background meanwhile, as it does while the phone's file dialog is open.
  Future<T> keepUnlocked<T>(Future<T> Function() action) async {
    _holds++;
    try {
      return await action();
    } finally {
      _holds--;
    }
  }
}

/// Gives every screen below it the app's [AppServices].
class AppServicesScope extends InheritedWidget {
  const AppServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppServicesScope>()!.services;

  @override
  bool updateShouldNotify(AppServicesScope old) => services != old.services;
}

final class InMemoryBudgetKeyStore implements BudgetKeyStore {
  final _keys = <String, BudgetKey>{};

  @override
  Future<BudgetKey> keyFor(String budgetId) async =>
      _keys.putIfAbsent(budgetId, BudgetKey.generate);

  @override
  Future<BudgetKey?> existingKey(String budgetId) async => _keys[budgetId];

  @override
  Future<void> writeKey(String budgetId, BudgetKey key) async =>
      _keys[budgetId] = key;
}

final class InMemoryDevicePrefs implements DevicePrefs {
  bool _appLock = false;
  CivilDate? _lastBackup;
  var _budgetIds = <String>[];
  String? _lastBudgetId;
  final _automationMonths = <String, CalendarMonth>{};
  final _syncBooks = <String, SyncBook>{};
  SimpleFinBook _simpleFin = const SimpleFinBook();

  @override
  Future<bool> readAppLockEnabled() async => _appLock;

  @override
  Future<void> writeAppLockEnabled(bool enabled) async => _appLock = enabled;

  @override
  Future<CivilDate?> readLastBackup() async => _lastBackup;

  @override
  Future<void> writeLastBackup(CivilDate date) async => _lastBackup = date;

  @override
  Future<List<String>> readBudgetIds() async => List.of(_budgetIds);

  @override
  Future<void> writeBudgetIds(List<String> ids) async =>
      _budgetIds = List.of(ids);

  @override
  Future<String?> readLastBudgetId() async => _lastBudgetId;

  @override
  Future<void> writeLastBudgetId(String id) async => _lastBudgetId = id;

  @override
  Future<CalendarMonth?> readAutomationMonth(String budgetId) async =>
      _automationMonths[budgetId];

  @override
  Future<void> writeAutomationMonth(
    String budgetId,
    CalendarMonth month,
  ) async => _automationMonths[budgetId] = month;

  @override
  Future<SimpleFinBook> readSimpleFinBook() async => _simpleFin;

  @override
  Future<void> writeSimpleFinBook(SimpleFinBook book) async =>
      _simpleFin = book;

  @override
  Future<SyncBook> readSyncBook(String budgetId) async =>
      _syncBooks[budgetId] ?? SyncBook.off;

  @override
  Future<void> writeSyncBook(String budgetId, SyncBook book) async =>
      _syncBooks[budgetId] = book;
}

/// Keeps "saved" files in [saved] instead of writing them anywhere.
final class InMemoryFileSaver implements FileSaver {
  /// Set false to act as if the person backed out of the file dialog.
  bool accepts = true;

  final saved = <String, Uint8List>{};

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (accepts) saved[fileName] = bytes;
    return accepts;
  }
}

/// Acts as the file dialog: hands back [next] once.
final class InMemoryFileLoader implements FileLoader {
  Uint8List? next;

  var picks = 0;

  @override
  Future<Uint8List?> pick({required List<String> extensions}) async {
    picks++;
    final bytes = next;
    next = null;
    return bytes;
  }
}

/// A [BankSyncScheduler] that records calls instead of arranging anything.
final class FakeBankSyncScheduler implements BankSyncScheduler {
  var scheduled = 0;
  var cancelled = 0;

  @override
  Future<void> schedule() async => scheduled++;

  @override
  Future<void> cancel() async => cancelled++;
}

/// An [Authenticator] whose answers are set by the caller.
final class FakeAuthenticator implements Authenticator {
  FakeAuthenticator({this.supported = true, this.succeeds = true});

  bool supported;
  bool succeeds;

  /// The `biometricOnly` value of each call, in order.
  final calls = <bool>[];

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    calls.add(biometricOnly);
    return succeeds;
  }
}
