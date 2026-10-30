import 'dart:typed_data';

import 'drive.dart';

/// A Drive that lives in memory, for tests and previews.
///
/// It keeps the folder tree a real one would, so a test can prove that a
/// device wrote only inside the folder it made, and that a second device
/// sees exactly what the first uploaded.
final class InMemoryDrive implements DriveGateway {
  InMemoryDrive();

  /// The app data folder's id, as Drive names it.
  static const root = GoogleDriveAppData.appDataFolder;

  final _entries = <String, _Entry>{};
  var _nextId = 0;

  /// Every upload, in order: the folder it went into and its name.
  final uploads = <({String folderId, String name})>[];

  /// Every folder created, in order.
  final folders = <({String folderId, String name})>[];

  @override
  Future<List<DriveFile>> list(String? folderId) async {
    final parent = folderId ?? root;
    return [
      for (final MapEntry(key: id, value: entry) in _entries.entries)
        if (entry.parentId == parent)
          DriveFile(id: id, name: entry.name, isFolder: entry.isFolder),
    ];
  }

  @override
  Future<String> createFolder(String name, {String? folderId}) async {
    final id = 'folder-${++_nextId}';
    final parent = folderId ?? root;
    if (parent != root && !(_entries[parent]?.isFolder ?? false)) {
      throw const DriveException('No such folder');
    }
    _entries[id] = _Entry(name: name, parentId: parent, isFolder: true);
    folders.add((folderId: parent, name: name));
    return id;
  }

  @override
  Future<void> upload({
    required String name,
    required String folderId,
    required Uint8List bytes,
  }) async {
    if (!(_entries[folderId]?.isFolder ?? false)) {
      throw const DriveException('No such folder');
    }
    final existing = _find(folderId, name);
    if (existing != null) _entries.remove(existing);
    _entries['file-${++_nextId}'] = _Entry(
      name: name,
      parentId: folderId,
      bytes: Uint8List.fromList(bytes),
    );
    uploads.add((folderId: folderId, name: name));
  }

  @override
  Future<Uint8List> download(String fileId) async {
    final entry = _entries[fileId];
    if (entry == null || entry.bytes == null) {
      throw const DriveException('No such file');
    }
    return Uint8List.fromList(entry.bytes!);
  }

  @override
  Future<void> delete(String fileId) async {
    final entry = _entries[fileId];
    if (entry == null || entry.isFolder) {
      throw const DriveException('No such file');
    }
    _entries.remove(fileId);
  }

  /// The id of the folder at [path], such as `budgetId/deviceId`, or null.
  String? folderAt(List<String> path) {
    var parent = root;
    for (final name in path) {
      final id = _find(parent, name);
      if (id == null || !(_entries[id]!.isFolder)) return null;
      parent = id;
    }
    return parent;
  }

  /// Every file in the folder at [path], by name.
  List<String> filesAt(List<String> path) {
    final id = folderAt(path);
    if (id == null) return const [];
    return [
      for (final MapEntry(key: _, value: entry) in _entries.entries)
        if (entry.parentId == id && !entry.isFolder) entry.name,
    ];
  }

  /// The bytes of [name] in the folder at [path], or null.
  Uint8List? readBytes({required List<String> path, required String name}) {
    final id = folderAt(path);
    if (id == null) return null;
    final fileId = _find(id, name);
    final bytes = fileId == null ? null : _entries[fileId]?.bytes;
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  /// Plants a file, as another device or an older build would have.
  void seed({
    required List<String> path,
    required String name,
    required Uint8List bytes,
  }) {
    var parent = root;
    for (final part in path) {
      final id = _find(parent, part);
      if (id != null) {
        parent = id;
        continue;
      }
      parent = 'folder-${++_nextId}';
      _entries[parent] = _Entry(name: part, parentId: parent, isFolder: true);
    }
    _entries['file-${++_nextId}'] = _Entry(
      name: name,
      parentId: parent,
      bytes: Uint8List.fromList(bytes),
    );
  }

  String? _find(String parentId, String name) {
    for (final MapEntry(key: id, value: entry) in _entries.entries) {
      if (entry.parentId == parentId && entry.name == name) return id;
    }
    return null;
  }
}

final class _Entry {
  _Entry({
    required this.name,
    required this.parentId,
    this.isFolder = false,
    this.bytes,
  });

  final String name;
  final String parentId;
  final bool isFolder;
  final Uint8List? bytes;
}
