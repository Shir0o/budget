/// Encrypted Event sync through Google Drive's app data folder: one folder
/// per device, every file sealed with the Budget Key (ticket 12, ADR 0002).
library;

export 'src/drive.dart';
export 'src/envelope.dart';
export 'src/in_memory_drive.dart';
export 'src/merge.dart';
export 'src/segment.dart';
export 'src/sync_book.dart';
export 'src/sync_client.dart';
