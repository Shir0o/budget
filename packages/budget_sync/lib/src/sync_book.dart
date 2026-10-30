/// This device's sync state for one budget, kept in secure storage.
///
/// It is not an Event and never syncs: it only remembers how far this device
/// has written its own folder, so a run uploads what changed instead of
/// everything.
final class SyncBook {
  const SyncBook({
    this.enabled = false,
    this.uploadedEvents = 0,
    this.uploadedSeq = 0,
    this.snapshottedEvents = 0,
    this.devices = 0,
    this.lastSync,
  });

  /// Sync is off by default (ADR 0002).
  static const off = SyncBook();

  final bool enabled;

  /// This device's own Events already in Drive.
  final int uploadedEvents;

  /// The newest segment number this device wrote.
  final int uploadedSeq;

  /// This device's own Events in its newest snapshot.
  final int snapshottedEvents;

  /// Device folders seen on the last run, this one included.
  final int devices;

  /// When the last run finished on this device.
  final DateTime? lastSync;

  SyncBook copyWith({bool? enabled}) => SyncBook(
    enabled: enabled ?? this.enabled,
    uploadedEvents: uploadedEvents,
    uploadedSeq: uploadedSeq,
    snapshottedEvents: snapshottedEvents,
    devices: devices,
    lastSync: lastSync,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'uploadedEvents': uploadedEvents,
    'uploadedSeq': uploadedSeq,
    'snapshottedEvents': snapshottedEvents,
    'devices': devices,
    if (lastSync case final lastSync?)
      'lastSync': lastSync.millisecondsSinceEpoch,
  };

  factory SyncBook.fromJson(Map<String, Object?> json) => SyncBook(
    enabled: json['enabled'] as bool? ?? false,
    uploadedEvents: json['uploadedEvents'] as int? ?? 0,
    uploadedSeq: json['uploadedSeq'] as int? ?? 0,
    snapshottedEvents: json['snapshottedEvents'] as int? ?? 0,
    devices: json['devices'] as int? ?? 0,
    lastSync: switch (json['lastSync']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
  );
}
