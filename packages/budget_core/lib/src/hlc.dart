/// A hybrid logical clock timestamp: wall time in ms, a counter, and the
/// device that issued it. Gives a total order across devices (ticket 06).
final class Hlc implements Comparable<Hlc> {
  const Hlc(this.wallMs, this.counter, this.deviceId);

  /// Parses the form produced by [toString].
  factory Hlc.parse(String text) {
    final first = text.indexOf(':');
    final second = text.indexOf(':', first + 1);
    if (first < 0 || second < 0) throw FormatException('Not an HLC', text);
    return Hlc(
      int.parse(text.substring(0, first)),
      int.parse(text.substring(first + 1, second), radix: 16),
      text.substring(second + 1),
    );
  }

  final int wallMs;
  final int counter;
  final String deviceId;

  @override
  int compareTo(Hlc other) {
    final byWall = wallMs.compareTo(other.wallMs);
    if (byWall != 0) return byWall;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return deviceId.compareTo(other.deviceId);
  }

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.wallMs == wallMs &&
      other.counter == counter &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(wallMs, counter, deviceId);

  /// Fixed-width, so string order equals HLC order.
  @override
  String toString() =>
      '${wallMs.toString().padLeft(15, '0')}:'
      '${counter.toRadixString(16).padLeft(4, '0')}:$deviceId';
}

/// Issues increasing [Hlc]s for one device, even if the wall clock steps back.
final class HlcClock {
  /// [last] is the latest HLC already in the log, so new ones sort after it.
  HlcClock(this.deviceId, {int Function()? nowMs, this.last})
    : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String deviceId;
  final int Function() _nowMs;

  /// The most recent HLC issued or observed.
  Hlc? last;

  Hlc tick() {
    final now = _nowMs();
    final last = this.last;
    final next = last == null || now > last.wallMs
        ? Hlc(now, 0, deviceId)
        : Hlc(last.wallMs, last.counter + 1, deviceId);
    return this.last = next;
  }
}
