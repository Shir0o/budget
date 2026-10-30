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
      var snapshotted = book.snapshottedEvents;
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

  /// The folder called [name] under [parent], made when it isn't there yet.
  Future<String> _folder(String name, String? parent) async {
    for (final entry in await drive.list(parent)) {
      if (entry.isFolder && entry.name == name) return entry.id;
    }
    return drive.createFolder(name, folderId: parent);
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
