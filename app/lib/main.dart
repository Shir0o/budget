import 'dart:math';

import 'package:budget_core/budget_core.dart';
import 'package:budget_store/budget_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'platform_services.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['IBM Plex'], ofl);
  });

  // The store key and device id live only in Android Keystore-backed storage.
  const secrets = FlutterSecureStorage();
  final keyHex = await _readOrCreate(secrets, 'store-key', _randomHex);
  final deviceId = await _readOrCreate(secrets, 'device-id', newId);

  final dir = await getApplicationSupportDirectory();
  final log = SqlCipherEventLog.open('${dir.path}/budget.db', keyHex: keyHex);
  final engine = BudgetEngine(
    log: log,
    deviceId: deviceId,
    actor: Actor.userAndroid,
  );
  final prefs = const SecureDevicePrefs(secrets);
  final services = AppServices(
    keys: const SecureBudgetKeyStore(secrets),
    prefs: prefs,
    saver: const SystemFileSaver(),
    authenticator: LocalAuthenticator(),
    appLockEnabled: await prefs.readAppLockEnabled(),
  );
  runApp(BudgetApp(engine: engine, services: services));
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

/// 256 random bits as 64 hex digits.
String _randomHex() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 32; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
