/// Who or what made an Event.
///
/// Ticket 06 lists the forms: `user@android`, `user@mac`, `bank-sync`,
/// `automation`, `import`, `mcp:<client name>` and `revert`. Constants are
/// added here as the features that use them arrive.
final class Actor {
  /// Restores an actor from its stored [value].
  const Actor.fromValue(this.value);

  static const userAndroid = Actor.fromValue('user@android');

  /// Compensating Events written by a revert (ticket 11).
  static const revert = Actor.fromValue('revert');

  final String value;

  /// A person on one of their devices (`user@…`), as opposed to bank sync,
  /// automation, an import, an MCP client or a revert.
  bool get isPerson => value.startsWith('user@');

  ActorKind get kind => switch (value) {
    _ when isPerson => ActorKind.person,
    'bank-sync' => ActorKind.bankSync,
    'automation' => ActorKind.automation,
    'import' => ActorKind.import,
    'revert' => ActorKind.revert,
    _ when value.startsWith('mcp:') => ActorKind.mcp,
    _ => ActorKind.other,
  };

  /// The client name of an `mcp:<client name>` actor.
  String? get mcpClient =>
      value.startsWith('mcp:') ? value.substring('mcp:'.length) : null;

  @override
  bool operator ==(Object other) => other is Actor && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The forms of [Actor] that ticket 06 lists.
enum ActorKind { person, bankSync, automation, import, mcp, revert, other }
