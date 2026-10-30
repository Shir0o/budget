import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:budget_store/budget_store.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'budget_library.dart';
import 'services.dart';

/// The real services: secure storage, the system file dialog and
/// local_auth. Only `main.dart` uses these; tests use the in-memory ones.

final class SecureBudgetKeyStore implements BudgetKeyStore {
  const SecureBudgetKeyStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<BudgetKey> keyFor(String budgetId) async {
    final name = 'budget-key:$budgetId';
    final existing = await _storage.read(key: name);
    if (existing != null) return BudgetKey.fromHex(existing);
    final key = BudgetKey.generate();
    await _storage.write(key: name, value: key.toHex());
    return key;
  }
}

final class SecureDevicePrefs implements DevicePrefs {
  const SecureDevicePrefs(this._storage);

  final FlutterSecureStorage _storage;

  static const _appLock = 'app-lock-enabled';
  static const _lastBackup = 'last-backup';
  static const _budgetIds = 'budget-ids';
  static const _lastBudgetId = 'last-budget-id';
  static const _simpleFin = 'simplefin-book';

  @override
  Future<bool> readAppLockEnabled() async =>
      await _storage.read(key: _appLock) == 'true';

  @override
  Future<void> writeAppLockEnabled(bool enabled) =>
      _storage.write(key: _appLock, value: '$enabled');

  @override
  Future<CivilDate?> readLastBackup() async {
    final iso = await _storage.read(key: _lastBackup);
    return iso == null ? null : CivilDate.parse(iso);
  }

  @override
  Future<void> writeLastBackup(CivilDate date) =>
      _storage.write(key: _lastBackup, value: date.toIso());

  @override
  Future<List<String>> readBudgetIds() async {
    final joined = await _storage.read(key: _budgetIds);
    return joined == null || joined.isEmpty ? [] : joined.split(',');
  }

  @override
  Future<void> writeBudgetIds(List<String> ids) =>
      _storage.write(key: _budgetIds, value: ids.join(','));

  @override
  Future<String?> readLastBudgetId() => _storage.read(key: _lastBudgetId);

  @override
  Future<void> writeLastBudgetId(String id) =>
      _storage.write(key: _lastBudgetId, value: id);

  @override
  Future<CalendarMonth?> readAutomationMonth(String budgetId) async {
    final iso = await _storage.read(key: 'automation-month:$budgetId');
    return iso == null ? null : CalendarMonth.parse(iso);
  }

  @override
  Future<void> writeAutomationMonth(String budgetId, CalendarMonth month) =>
      _storage.write(key: 'automation-month:$budgetId', value: month.toIso());

  @override
  Future<SimpleFinBook> readSimpleFinBook() async {
    final json = await _storage.read(key: _simpleFin);
    if (json == null) return const SimpleFinBook();
    return SimpleFinBook.fromJson(
      (jsonDecode(json) as Map).cast<String, Object?>(),
    );
  }

  @override
  Future<void> writeSimpleFinBook(SimpleFinBook book) =>
      _storage.write(key: _simpleFin, value: jsonEncode(book.toJson()));

  @override
  Future<SyncBook> readSyncBook(String budgetId) async {
    final json = await _storage.read(key: 'sync-book:$budgetId');
    if (json == null) return SyncBook.off;
    return SyncBook.fromJson((jsonDecode(json) as Map).cast<String, Object?>());
  }

  @override
  Future<void> writeSyncBook(String budgetId, SyncBook book) => _storage.write(
    key: 'sync-book:$budgetId',
    value: jsonEncode(book.toJson()),
  );
}

/// The Google Drive access token, as Google Sign-In leaves it in secure
/// storage. Null until this device connects Drive: getting the token needs
/// the project's OAuth client id, which a later ticket adds the screen for.
final class SecureDriveAccess implements DriveAccess {
  const SecureDriveAccess(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> accessToken() => _storage.read(key: 'drive-access-token');
}

final class SystemFileSaver implements FileSaver {
  const SystemFileSaver();

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async =>
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      ) !=
      null;
}

final class LocalAuthenticator implements Authenticator {
  LocalAuthenticator() : _auth = LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
      );
    } on LocalAuthException {
      // Cancelled, locked out, or nothing enrolled: the person stays locked.
      return false;
    }
  }
}

/// One SQLCipher file per budget in [directory], each under its own store
/// key kept in secure storage.
final class SqlCipherBudgetStorage implements BudgetStorage {
  const SqlCipherBudgetStorage(this._storage, {required this.directory});

  final FlutterSecureStorage _storage;
  final String directory;

  @override
  Future<EventLog> openLog(String budgetId) async {
    final name = 'store-key:$budgetId';
    var keyHex = await _storage.read(key: name);
    if (keyHex == null) {
      keyHex = BudgetKey.generate().toHex();
      await _storage.write(key: name, value: keyHex);
    }
    return SqlCipherEventLog.open(
      '$directory/budget-$budgetId.db',
      keyHex: keyHex,
    );
  }
}
