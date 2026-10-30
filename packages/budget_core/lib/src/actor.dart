/// Who or what made an Event.
///
/// Ticket 06 lists the forms: `user@android`, `user@mac`, `bank-sync`,
/// `automation`, `import`, `mcp:<client name>` and `revert`. Constants are
/// added here as the features that use them arrive.
final class Actor {
  /// Restores an actor from its stored [value].
  const Actor.fromValue(this.value);

  static const userAndroid = Actor.fromValue('user@android');

  final String value;

  @override
  bool operator ==(Object other) => other is Actor && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
