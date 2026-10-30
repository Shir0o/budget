/// What an MCP client may do with one budget (ticket 13). Off is the
/// default, so a fresh budget exposes nothing.
enum McpMode {
  off,
  readOnly,
  readWrite;

  /// Whether read tools answer for a budget in this mode.
  bool get allowsRead => this != off;

  /// Whether write tools may run. Read-write keeps a line Unreviewed until a
  /// person confirms it (ADR 0003), so writes never finish a Review.
  bool get allowsWrite => this == readWrite;

  /// `Off`, `Read-only` or `Read-write` as Settings shows it.
  String get label => switch (this) {
    McpMode.off => 'Off',
    McpMode.readOnly => 'Read-only',
    McpMode.readWrite => 'Read-write',
  };
}

/// This device's MCP setting for one budget, and the last client that used
/// it (ticket 13). It is not an Event, so it never syncs.
final class McpBook {
  const McpBook({this.mode = McpMode.off, this.lastUsedBy, this.lastUsedAt});

  /// Off, and never used.
  static const off = McpBook();

  static McpBook fromJson(Map<String, Object?> json) => McpBook(
    mode: switch (json['mode']) {
      final String name => McpMode.values.asNameMap()[name] ?? McpMode.off,
      _ => McpMode.off,
    },
    lastUsedBy: json['lastUsedBy'] as String?,
    lastUsedAt: switch (json['lastUsedAt']) {
      final String iso => DateTime.tryParse(iso),
      _ => null,
    },
  );

  final McpMode mode;

  /// The MCP client's name, such as `Claude Desktop`, or null.
  final String? lastUsedBy;

  /// When it last read this budget, in local time.
  final DateTime? lastUsedAt;

  /// This book with [mode], keeping the last-used line.
  McpBook withMode(McpMode mode) =>
      McpBook(mode: mode, lastUsedBy: lastUsedBy, lastUsedAt: lastUsedAt);

  /// This book after [client] used the budget at [at].
  McpBook usedBy(String client, DateTime at) =>
      McpBook(mode: mode, lastUsedBy: client, lastUsedAt: at);

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'lastUsedBy': ?lastUsedBy,
    if (lastUsedAt case final at?) 'lastUsedAt': at.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is McpBook &&
      other.mode == mode &&
      other.lastUsedBy == lastUsedBy &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode => Object.hash(mode, lastUsedBy, lastUsedAt);
}
