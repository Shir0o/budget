import 'package:budget_core/budget_core.dart';

/// The `kind` a sync file's sealed body states, so a file is readable even
/// when its name says nothing but a random id.
abstract final class SyncFileKind {
  static const segment = 'segment';
  static const snapshot = 'snapshot';
  static const manifest = 'manifest';
}

/// One device's append-only Event segment: at most [maxEvents] Events
/// (ticket 12).
///
/// The name is `seg-<seq>.bin`, so a device's folder reads in order without
/// opening anything, and reveals no more than a count.
final class Segment {
  const Segment({
    required this.budgetId,
    required this.deviceId,
    required this.seq,
    required this.events,
  });

  static const maxEvents = 500;

  /// `seg-000001.bin` for [seq].
  static String fileName(int seq) =>
      'seg-${seq.toString().padLeft(6, '0')}.bin';

  final String budgetId;
  final String deviceId;

  /// 1, 2, 3… in the order the device wrote them.
  final int seq;
  final List<Event> events;

  String get name => fileName(seq);

  Map<String, Object?> toJson() => {
    'kind': SyncFileKind.segment,
    'budgetId': budgetId,
    'deviceId': deviceId,
    'seq': seq,
    'events': [for (final event in events) event.toJson()],
  };
}

/// One device's own Events up to [covered], written every so often so a
/// second device starts from one file instead of many segments (ticket 12).
///
/// It compacts this device's own segments only, and a device keeps its
/// earlier segments, so a snapshot is an optimization and never the only
/// copy.
final class Snapshot {
  const Snapshot({
    required this.budgetId,
    required this.deviceId,
    required this.covered,
    required this.events,
  });

  /// `snap-<hlc>.bin`.
  static String fileName(Hlc covered) =>
      'snap-${covered.wallMs}-${covered.counter.toRadixString(16)}.bin';

  final String budgetId;
  final String deviceId;

  /// The newest Event it holds.
  final Hlc covered;
  final List<Event> events;

  String get name => fileName(covered);

  Map<String, Object?> toJson() => {
    'kind': SyncFileKind.snapshot,
    'budgetId': budgetId,
    'deviceId': deviceId,
    'covered': covered.toString(),
    'events': [for (final event in events) event.toJson()],
  };
}

/// What a device folder says about itself, without downloading its Events:
/// the platform it runs on and how far it has written (ticket 12). Sync
/// reads the platform so it can say what came from where.
final class DeviceManifest {
  const DeviceManifest({
    required this.deviceId,
    required this.platform,
    required this.latestSeq,
    required this.eventCount,
    required this.updatedMs,
  });

  /// A fixed name in the device's own folder, so the folder can't be
  /// mistaken for another device's.
  static const fileName = 'manifest.bin';

  final String deviceId;

  /// `android` or `mac`, as the Actor's platform reads.
  final String platform;
  final int latestSeq;
  final int eventCount;
  final int updatedMs;

  Map<String, Object?> toJson() => {
    'kind': SyncFileKind.manifest,
    'deviceId': deviceId,
    'platform': platform,
    'latestSeq': latestSeq,
    'eventCount': eventCount,
    'updatedMs': updatedMs,
  };

  factory DeviceManifest.fromJson(Map<String, Object?> json) => DeviceManifest(
    deviceId: json['deviceId'] as String,
    platform: json['platform'] as String,
    latestSeq: json['latestSeq'] as int,
    eventCount: json['eventCount'] as int,
    updatedMs: json['updatedMs'] as int,
  );
}

/// The merge input: every Event one other device's folder contributed, in
/// HLC order, whatever mix of segments and snapshots it came from.
final class SyncBatch {
  const SyncBatch({
    required this.deviceId,
    required this.platform,
    required this.events,
  });

  /// The folder the Events came from.
  final String deviceId;

  /// From the device's manifest (`android` or `mac`), or null when it has
  /// none yet.
  final String? platform;
  final List<Event> events;

  /// The same Events with duplicates dropped, in HLC order, so a snapshot
  /// that repeats segments costs nothing.
  List<Event> get distinct {
    final seen = <String>{};
    return [
      for (final event in events)
        if (seen.add(event.id)) event,
    ]..sort((a, b) => a.hlc.compareTo(b.hlc));
  }
}

/// The Events in a sealed file body.
List<Event> readEvents(Map<String, Object?> json) => [
  for (final event in (json['events'] as List).cast<Map>())
    Event.fromJson(event.cast<String, Object?>()),
];

/// Whether [name] is a segment or a snapshot. A device's manifest is read
/// on its own, so it isn't an event file.
bool isEventFile(String name) =>
    name.startsWith('seg-') || name.startsWith('snap-');
