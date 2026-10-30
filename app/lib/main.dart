import 'package:budget_core/budget_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'budget_library.dart';
import 'platform_services.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    actor: Actor.userAndroid,
  );
  final services = AppServices(
    keys: const SecureBudgetKeyStore(secrets),
    prefs: prefs,
    saver: const SystemFileSaver(),
    authenticator: LocalAuthenticator(),
    appLockEnabled: await prefs.readAppLockEnabled(),
  );
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
