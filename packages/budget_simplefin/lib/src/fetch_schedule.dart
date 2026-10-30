import 'package:budget_core/budget_core.dart';

// When an unminded device may fetch, and what it says when it can't
// (ticket 10). All of it is device-local: the schedule, a link the bridge
// refused and the bridge's own messages never reach the Event log.

/// When this device may fetch on its own (ticket 10): no more often than
/// every 6 hours, which is at most four times a day, and always inside the
/// day's [RequestCount].
final class FetchSchedule {
  const FetchSchedule({this.lastAttempt});

  factory FetchSchedule.fromJson(Map<String, Object?> json) => FetchSchedule(
    lastAttempt: switch (json['lastAutomaticMs']) {
      final int milliseconds => DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ),
      _ => null,
    },
  );

  /// The shortest gap between two automatic fetches (ticket 10).
  static const interval = Duration(hours: 6);

  /// When the last automatic fetch started, in UTC, or null before the
  /// first one.
  final DateTime? lastAttempt;

  /// Whether [interval] has passed since [lastAttempt], or there never was
  /// one. [now] is converted to UTC first.
  bool isDue(DateTime now) {
    final last = lastAttempt;
    if (last == null) return true;
    return now.toUtc().difference(last) >= interval;
  }

  /// This schedule with [now] as the last automatic attempt, after the
  /// request it asked for was counted.
  FetchSchedule attemptedAt(DateTime now) =>
      FetchSchedule(lastAttempt: now.toUtc());

  Map<String, Object?> toJson() => {
    'lastAutomaticMs': lastAttempt?.millisecondsSinceEpoch,
  };
}

/// Whether this device's access URL can be used with nobody watching
/// (ticket 10).
enum AuthState {
  /// Nothing has refused the access URL, so automatic fetches may run.
  linked,

  /// The bridge refused the access URL: automatic fetches stay paused
  /// until the person re-links the bank.
  needsRelink;

  /// Whether automatic fetches are held back.
  bool get paused => this == AuthState.needsRelink;

  /// The stored form, defaulting to [linked] for anything else.
  static AuthState parse(Object? value) =>
      value == needsRelink.name ? needsRelink : linked;
}

/// One message a fetch left to show the person (ticket 03): a line from the
/// bridge's `errors` array, or the failure that stopped the fetch.
final class BankError {
  const BankError({
    required this.message,
    required this.day,
    this.auth = false,
  });

  factory BankError.fromJson(Map<String, Object?> json) => BankError(
    message: json['message'] as String,
    day: CivilDate.parse(json['day'] as String),
    auth: json['auth'] as bool? ?? false,
  );

  /// The message as the bridge wrote it, or what went wrong.
  final String message;

  /// The day of the fetch that reported it.
  final CivilDate day;

  /// True when it means the access URL must be replaced, which pauses
  /// automatic fetches (ticket 10).
  final bool auth;

  Map<String, Object?> toJson() => {
    'message': message,
    'day': day.toIso(),
    'auth': auth,
  };

  @override
  bool operator ==(Object other) =>
      other is BankError &&
      other.message == message &&
      other.day == day &&
      other.auth == auth;

  @override
  int get hashCode => Object.hash(message, day, auth);
}
