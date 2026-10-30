import 'dart:io';

import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/budget_mcp.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'bank_background.dart';
import 'bank_sync.dart';
import 'budget_library.dart';
import 'platform_services.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android's background fetch runs in its own isolate (ticket 10); the
  // entry point is top level so WorkManager can find it there.
  if (Platform.isAndroid) {
    await Workmanager().initialize(bankSyncDispatcher);
  }
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['IBM Plex'], ofl);
  });

  // Keys and the device id live only in Android Keystore-backed storage.
  const secrets = FlutterSecureStorage();
  final deviceId = await _readOrCreate(secrets, 'device-id', newId);

  final dir = await getApplicationSupportDirectory();
  final prefs = const SecureDevicePrefs(secrets);
  final library = await BudgetLibrary.load(
    storage: SqlCipherBudgetStorage(secrets, directory: dir.path),
    prefs: prefs,
    deviceId: deviceId,
    actor: userActorFor(Platform.operatingSystem),
  );
  final services = AppServices(
    keys: const SecureBudgetKeyStore(secrets),
    prefs: prefs,
    saver: const SystemFileSaver(),
    loader: const SystemFileLoader(),
    authenticator: LocalAuthenticator(),
    simpleFin: const HttpSimpleFinTransport(),
    scheduler: const WorkManagerBankSyncScheduler(),
    // Google Drive's hidden app data folder only (ADR 0002). The token comes
    // from Google Sign-In, which needs the OAuth client id.
    drive: GoogleDriveAppData(
      transport: const HttpDriveTransport(),
      access: const SecureDriveAccess(secrets),
    ),
    // budget-mcp is macOS only (ticket 13); its registry sits next to the
    // encrypted store files.
    mcp: Platform.isMacOS ? FileMcpStore(dir.path) : null,
    appLockEnabled: await prefs.readAppLockEnabled(),
  );
  // Arrange or stop the 6-hourly fetch to match the bank book on this
  // device (ticket 10): on after a connection, off after an auth failure.
  await syncBankSchedule(services.scheduler, await prefs.readSimpleFinBook());
  runApp(BudgetApp(library: library, services: services));
}

Future<String> _readOrCreate(
  FlutterSecureStorage storage,
  String key,
  String Function() create,
) async {
  final existing = await storage.read(key: key);
  if (existing != null) return existing;
  final value = create();
  await storage.write(key: key, value: value);
  return value;
}
