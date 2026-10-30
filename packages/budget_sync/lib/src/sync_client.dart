import 'dart:math';

import 'package:budget_core/budget_core.dart';

import 'drive.dart';
import 'envelope.dart';
import 'merge.dart';
import 'segment.dart';
import 'sync_book.dart';

/// What one sync run did, for the Encrypted sync screen.
final class SyncOutcome {
  const SyncOutcome({
    required this.book,
    required this.pulled,
    required this.pushed,
    required this.needsAttention,
    this.others = const [],
    this.error,
  });

  /// This device's sync state after the run.
  final SyncBook book;

  /// Events this device took from other devices.
  final int pulled;

  /// This device's Events it wrote to its own folder.
  final int pushed;

  /// Invariants the merge left broken (ticket 06), for the Review queue.
  final List<NeedsAttention> needsAttention;

  /// The platforms of the other devices that contributed, `android` or
  /// `mac`, as their manifests say. Empty when nothing came from another
  /// device.
  final List<String> others;

  /// What went wrong, or null when the run finished.
  final String? error;
}

/// What a pairing found in Drive, for the Join screen.
final class JoinOutcome {
  const JoinOutcome({required this.events, required this.devices, this.error});

  /// Every Event the budget holds, whichever device wrote it, in HLC order.
  final List<Event> events;

  /// How many device folders contributed.
  final int devices;

  /// What went wrong, or null when the pairing read the budget.
  final String? error;
}

/// What one key rotation did, for the Recovery phrase screen.
final class RotationOutcome {
  const RotationOutcome({
    required this.book,
    required this.snapshotEvents,
    required this.deletedFiles,
    this.error,
  });

  /// This device's sync state after the rotation.
  final SyncBook book;

  /// Events the fresh snapshot holds, which is the whole budget.
  final int snapshotEvents;

  /// Files the old key sealed, now deleted from Drive.
  final int deletedFiles;

  /// What went wrong, or null when the rotation finished.
  final String? error;
}

/// Moves one budget's Events through Drive, one folder per device, every
/// file sealed with the Budget Key (ticket 12, ADR 0002).
///
/// Pull is "read every other device's folder and merge"; push is "write this
/// device's new Events, and nothing else, into this device's own folder". A
/// file is never written by two devices.
final class SyncClient {
  SyncClient({required this.drive, this.snapshotEvery = 1000});

  final DriveGateway drive;

  /// How many of this device's own Events a snapshot compacts. 0 turns
  /// snapshots off.
  final int snapshotEvery;

  /// Runs one sync for [engine]'s open budget.
  ///
  /// [platform] is the device kind the manifest records, `android` or `mac`.
  Future<SyncOutcome> sync({
    required BudgetEngine engine,
    required BudgetKey key,
    required SyncBook book,
    String platform = 'android',
  }) async {
    final budget = engine.state.budget;
    if (budget == null) {
      return _failed(book, 'Create the budget before turning on sync.');
    }
    final budgetId = budget.id;
    final deviceId = engine.deviceId;
    try {
      // This device's folders, created once and then reused.
      final budgetFolder = await _folder(budgetId, null);
      final myFolder = await _folder(deviceId, budgetFolder);
      final deviceFolders = [
        for (final entry in await drive.list(budgetFolder))
          if (entry.isFolder) entry,
      ];

      // Pull: every other device's segments and snapshots, then merge.
      final batches = <SyncBatch>[];
      for (final folder in deviceFolders) {
        if (folder.name == deviceId) continue;
        batches.add(await _readDevice(folder, budgetId, key));
      }
      final merged = engine.merge([
        for (final batch in batches) ...batch.distinct,
      ]);

      // Push: this device's own Events only, into its own folder only.
      final own = [
        for (final event in engine.events)
          if (event.deviceId == deviceId) event,
      ];
      var uploaded = book.uploadedEvents.clamp(0, own.length);
      var seq = book.uploadedSeq;
      var snapshotted = book.snapshottedEvents;

      // A redaction rewrites Events that may already be in Drive, so this
      // device's own segments and snapshot still hold the old value.
      // Publish one fresh snapshot of the rewritten log and drop what came
      // before (ticket 11). Every device does this in its own folder.
      final redacted = {
        for (final event in engine.events)
          if (event.type == EventType.redacted &&
              !book.rewrittenFor.contains(event.id))
            event.id,
      };
      if (redacted.isNotEmpty && own.isNotEmpty) {
        for (final file in await drive.list(myFolder)) {
          if (isEventFile(file.name)) await drive.delete(file.id);
        }
        final snapshot = Snapshot(
          budgetId: budgetId,
          deviceId: deviceId,
          covered: own.last.hlc,
          events: own,
        );
        await _write(
          budgetId,
          deviceId,
          myFolder,
          snapshot.name,
          snapshot.toJson(),
          key,
        );
        uploaded = own.length;
        snapshotted = own.length;
      }

      final fresh = own.skip(uploaded).toList();
      for (var start = 0; start < fresh.length; start += Segment.maxEvents) {
        final events = fresh.sublist(
          start,
          min(start + Segment.maxEvents, fresh.length),
        );
        final segment = Segment(
          budgetId: budgetId,
          deviceId: deviceId,
          seq: ++seq,
          events: events,
        );
        await _write(
          budgetId,
          deviceId,
          myFolder,
          segment.name,
          segment.toJson(),
          key,
        );
        uploaded += events.length;
      }

      // A snapshot compacts this device's own Events, so a second device
      // starts from one file.
      if (snapshotEvery > 0 &&
          own.length >= snapshotEvery &&
          own.length - snapshotted >= snapshotEvery) {
        final snapshot = Snapshot(
          budgetId: budgetId,
          deviceId: deviceId,
          covered: own.last.hlc,
          events: own,
        );
        await _write(
          budgetId,
          deviceId,
          myFolder,
          snapshot.name,
          snapshot.toJson(),
          key,
        );
        snapshotted = own.length;
      }

      await _writeManifest(
        myFolder,
        DeviceManifest(
          deviceId: deviceId,
          platform: platform,
          latestSeq: seq,
          eventCount: own.length,
          updatedMs: DateTime.now().millisecondsSinceEpoch,
        ),
        budgetId,
        key,
      );

      final after = SyncBook(
        enabled: book.enabled,
        uploadedEvents: uploaded,
        uploadedSeq: seq,
        snapshottedEvents: snapshotted,
        devices: deviceFolders.length,
        lastSync: DateTime.now(),
        rewrittenFor: {...book.rewrittenFor, ...redacted},
      );
      return SyncOutcome(
        book: after,
        pulled: merged.length,
        pushed: fresh.length,
        needsAttention: needsAttention(engine.state),
        others: [
          for (final batch in batches)
            if (batch.events.isNotEmpty && batch.platform != null)
              batch.platform!,
        ],
      );
    } on DriveException catch (error) {
      return _failed(book, error.message);
    } on SyncException catch (error) {
      return _failed(book, error.message);
    }
  }

  /// A run that stopped, keeping the book as it was.
  SyncOutcome _failed(SyncBook book, String message) => SyncOutcome(
    book: book,
    pulled: 0,
    pushed: 0,
    needsAttention: const [],
    error: message,
  );

  /// Joins another device's budget with the key from its QR code (ticket 12):
  /// reads every device folder under [budgetId] and returns the Events they
  /// hold. Nothing is written, so a wrong code changes nothing here or in
  /// Drive.
  Future<JoinOutcome> join({
    required String budgetId,
    required BudgetKey key,
  }) async {
    try {
      final budgetFolder = await _find(budgetId, null);
      if (budgetFolder == null) {
        return const JoinOutcome(
          events: [],
          devices: 0,
          error: 'No synced budget uses that code.',
        );
      }
      final events = <Event>[];
      var devices = 0;
      for (final folder in await drive.list(budgetFolder.id)) {
        if (!folder.isFolder) continue;
        final batch = await _readDevice(folder, budgetId, key);
        if (batch.distinct.isEmpty) continue;
        events.addAll(batch.distinct);
        devices++;
      }
      if (events.any((event) => event.budgetId != budgetId)) {
        return const JoinOutcome(
          events: [],
          devices: 0,
          error: 'Those Events belong to another budget.',
        );
      }
      if (events.isEmpty) {
        return const JoinOutcome(
          events: [],
          devices: 0,
          error: 'That budget has nothing in Drive yet.',
        );
      }
      final seen = <String>{};
      return JoinOutcome(
        events: [
          for (final event in events)
            if (seen.add(event.id)) event,
        ]..sort((a, b) => a.hlc.compareTo(b.hlc)),
        devices: devices,
      );
    } on DriveException catch (error) {
      return JoinOutcome(events: const [], devices: 0, error: error.message);
    } on SyncException catch (error) {
      return JoinOutcome(events: const [], devices: 0, error: error.message);
    }
  }

  /// Rotates the Budget Key (ticket 12, for a lost or stolen device): seals a
  /// fresh snapshot of every Event with [newKey], deletes every file the old
  /// key sealed, and starts this device's folder again.
  ///
  /// Every other device is unpaired by this: its key no longer opens anything,
  /// so it has to join again with the new QR code. [oldKey] must open what is
  /// in Drive, so rotating with a wrong key deletes nothing.
  Future<RotationOutcome> rotate({
    required BudgetEngine engine,
    required BudgetKey oldKey,
    required BudgetKey newKey,
    required SyncBook book,
    String platform = 'android',
  }) async {
    final budget = engine.state.budget;
    if (budget == null) {
      return _rotationFailed(book, 'Create the budget before turning on sync.');
    }
    final budgetId = budget.id;
    final deviceId = engine.deviceId;
    try {
      final budgetFolder = await _folder(budgetId, null);
      final deviceFolders = [
        for (final entry in await drive.list(budgetFolder))
          if (entry.isFolder) entry,
      ];
      try {
        await _prove(budgetId, deviceFolders, oldKey);
      } on SyncException {
        return _rotationFailed(
          book,
          'That isn’t this budget’s current Budget Key.',
        );
      }
      var deleted = 0;
      for (final folder in deviceFolders) {
        for (final file in await drive.list(folder.id)) {
          await drive.delete(file.id);
          deleted++;
        }
      }

      // The snapshot is now Drive's only copy of the log, so it holds every
      // Event from every device, not just this one's.
      final events = engine.events;
      final folderId =
          (await _find(deviceId, budgetFolder))?.id ??
          await drive.createFolder(deviceId, folderId: budgetFolder);
      final snapshot = Snapshot(
        budgetId: budgetId,
        deviceId: deviceId,
        covered: events.last.hlc,
        events: events,
      );
      await _write(
        budgetId,
        deviceId,
        folderId,
        snapshot.name,
        snapshot.toJson(),
        newKey,
      );
      final own = [
        for (final event in events)
          if (event.deviceId == deviceId) event,
      ];
      await _writeManifest(
        folderId,
        DeviceManifest(
          deviceId: deviceId,
          platform: platform,
          latestSeq: 0,
          eventCount: own.length,
          updatedMs: DateTime.now().millisecondsSinceEpoch,
        ),
        budgetId,
        newKey,
      );
      return RotationOutcome(
        book: SyncBook(
          enabled: book.enabled,
          uploadedEvents: own.length,
          snapshottedEvents: own.length,
          // New segments start at 1 again, beside the snapshot.
          devices: deviceFolders.isEmpty ? 1 : deviceFolders.length,
          lastSync: DateTime.now(),
          rewrittenFor: book.rewrittenFor,
        ),
        snapshotEvents: events.length,
        deletedFiles: deleted,
      );
    } on DriveException catch (error) {
      return _rotationFailed(book, error.message);
    } on SyncException catch (error) {
      return _rotationFailed(book, error.message);
    }
  }

  /// A rotation that stopped, keeping the book as it was.
  RotationOutcome _rotationFailed(SyncBook book, String message) =>
      RotationOutcome(
        book: book,
        snapshotEvents: 0,
        deletedFiles: 0,
        error: message,
      );

  /// Opens one file under [budgetId] with [key], so a rotation with the wrong
  /// key is refused before anything is deleted.
  Future<void> _prove(
    String budgetId,
    List<DriveFile> folders,
    BudgetKey key,
  ) async {
    for (final folder in folders) {
      for (final file in await drive.list(folder.id)) {
        if (file.name != DeviceManifest.fileName && !isEventFile(file.name)) {
          continue;
        }
        await SealedFile.open(
          name: _name(budgetId, folder.name, file.name),
          file: await drive.download(file.id),
          key: key,
        );
        return;
      }
    }
  }

  /// The folder called [name] under [parent], made when it isn't there yet.
  Future<String> _folder(String name, String? parent) async =>
      (await _find(name, parent))?.id ??
      await drive.createFolder(name, folderId: parent);

  /// The folder called [name] under [parent], or null when there is none.
  Future<DriveFile?> _find(String name, String? parent) async {
    for (final entry in await drive.list(parent)) {
      if (entry.isFolder && entry.name == name) return entry;
    }
    return null;
  }

  /// Every Event [folder] holds, from its segments and snapshots, and the
  /// platform its manifest names.
  Future<SyncBatch> _readDevice(
    DriveFile folder,
    String budgetId,
    BudgetKey key,
  ) async {
    final events = <Event>[];
    String? platform;
    for (final file in await drive.list(folder.id)) {
      if (file.name != DeviceManifest.fileName && !isEventFile(file.name)) {
        continue;
      }
      final body = await SealedFile.open(
        name: _name(budgetId, folder.name, file.name),
        file: await drive.download(file.id),
        key: key,
      );
      if (file.name == DeviceManifest.fileName) {
        platform = DeviceManifest.fromJson(body).platform;
      } else {
        events.addAll(readEvents(body));
      }
    }
    return SyncBatch(deviceId: folder.name, platform: platform, events: events);
  }

  Future<void> _write(
    String budgetId,
    String deviceId,
    String folderId,
    String fileName,
    Map<String, Object?> body,
    BudgetKey key,
  ) async {
    final bytes = await SealedFile.seal(
      name: _name(budgetId, deviceId, fileName),
      body: body,
      key: key,
    );
    await drive.upload(name: fileName, folderId: folderId, bytes: bytes);
  }

  /// Replaces this device's manifest, deleting the old one first so Drive
  /// doesn't keep two files of the same name.
  Future<void> _writeManifest(
    String folderId,
    DeviceManifest manifest,
    String budgetId,
    BudgetKey key,
  ) async {
    for (final file in await drive.list(folderId)) {
      if (file.name == DeviceManifest.fileName) await drive.delete(file.id);
    }
    await _write(
      budgetId,
      manifest.deviceId,
      folderId,
      DeviceManifest.fileName,
      manifest.toJson(),
      key,
    );
  }

  /// What a sealed file is authenticated as: its whole path under the app
  /// data folder, so it can't be renamed into another device's or budget's.
  static String _name(String budgetId, String deviceId, String fileName) =>
      '$budgetId/$deviceId/$fileName';
}
