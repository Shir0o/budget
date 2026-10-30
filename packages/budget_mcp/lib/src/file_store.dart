import 'dart:convert';
import 'dart:io';

import 'budgets.dart';

/// The app's budgets and MCP settings in one small JSON file next to the
/// encrypted store files (macOS only). It holds no amounts, payees or keys,
/// only ids, names, settings and file names.
final class FileMcpStore implements McpStore {
  FileMcpStore(this.directory);

  final String directory;

  /// `mcp.json` in [directory].
  File get file => File('$directory/mcp.json');

  @override
  Future<List<McpBudget>> read() async {
    final file = this.file;
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString()) as Map;
      return [
        for (final budget
            in (decoded['budgets'] as List? ?? const []).cast<Map>())
          McpBudget.fromJson(budget.cast<String, Object?>()),
      ];
    } on FormatException {
      // A file someone edited by hand reads as no budgets, so every budget
      // is Off rather than open by accident.
      return [];
    } on TypeError {
      return [];
    }
  }

  @override
  Future<void> write(List<McpBudget> budgets) async {
    await Directory(directory).create(recursive: true);
    final temp = File('$directory/mcp.json.tmp');
    await temp.writeAsString(
      jsonEncode({
        'budgets': [for (final budget in budgets) budget.toJson()],
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }
}
