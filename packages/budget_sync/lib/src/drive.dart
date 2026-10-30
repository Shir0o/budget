import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// One entry in the Drive app data folder. Sync reads its name and whether
/// it is a folder, nothing else.
final class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    this.isFolder = false,
  });

  final String id;
  final String name;
  final bool isFolder;
}

/// A Drive call that failed, or a Drive that isn't connected.
final class DriveException implements Exception {
  const DriveException(this.message);

  final String message;

  @override
  String toString() => 'DriveException: $message';
}

/// The Google Drive app data folder, and nothing else (ADR 0002). The app
/// asks for the `drive.appdata` scope only, so it cannot see the person's
/// other files. Tests and previews use `InMemoryDrive`.
///
/// Sync writes each device's files through this, so a file is only ever
/// written under the folder its own device created.
abstract interface class DriveGateway {
  /// The folders and files directly under [folderId]. Null is the app data
  /// folder itself; a folder that doesn't exist yet lists nothing.
  Future<List<DriveFile>> list(String? folderId);

  /// Creates a folder called [name] and returns its id.
  Future<String> createFolder(String name, {String? folderId});

  /// Writes [bytes] as [name] in [folderId].
  Future<void> upload({
    required String name,
    required String folderId,
    required Uint8List bytes,
  });

  /// Reads the file [fileId].
  Future<Uint8List> download(String fileId);

  /// Deletes the file [fileId]. Only a file this device wrote is ever
  /// deleted, so a manifest can be replaced.
  Future<void> delete(String fileId);
}

/// The Google sign-in's access token, which the app keeps in secure
/// storage. Null when this device hasn't connected Google Drive.
abstract interface class DriveAccess {
  Future<String?> accessToken();
}

/// One HTTP round trip, so the Drive calls are testable without a network.
abstract interface class DriveTransport {
  Future<DriveResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Uint8List? body,
  });
}

final class DriveResponse {
  const DriveResponse({required this.status, required this.body});

  final int status;
  final Uint8List body;
}

/// Google Drive through the v3 REST API, with the `drive.appdata` scope
/// (ticket 12). Every call is inside the app data folder: the root it lists
/// is `appDataFolder`, and no other space is ever asked for.
final class GoogleDriveAppData implements DriveGateway {
  GoogleDriveAppData({required this.transport, required this.access});

  /// The hidden app data folder's id, which is also the only parent a
  /// budget folder may have.
  static const appDataFolder = 'appDataFolder';

  static const _folderMime = 'application/vnd.google-apps.folder';

  static final _api = Uri.parse('https://www.googleapis.com/drive/v3/files');
  static final _uploadApi = Uri.parse(
    'https://www.googleapis.com/upload/drive/v3/files',
  );

  final DriveTransport transport;
  final DriveAccess access;

  @override
  Future<List<DriveFile>> list(String? folderId) async {
    final response = await _send(
      'GET',
      _api,
      query: {
        // Only the app data folder, never the person's own Drive.
        if (folderId == null) 'spaces': appDataFolder,
        'q': folderId == null
            ? 'trashed = false'
            : "'$folderId' in parents and trashed = false",
        'fields': 'files(id,name,mimeType)',
        'pageSize': '1000',
      },
    );
    final body = _json(response);
    return [
      for (final file in (body['files'] as List? ?? const []).cast<Map>())
        DriveFile(
          id: file['id'] as String,
          name: file['name'] as String,
          isFolder: file['mimeType'] == _folderMime,
        ),
    ];
  }

  @override
  Future<String> createFolder(String name, {String? folderId}) async {
    final response = await _send(
      'POST',
      _api,
      query: {'fields': 'id'},
      headers: {'content-type': 'application/json; charset=UTF-8'},
      body: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'name': name,
            'mimeType': _folderMime,
            'parents': [folderId ?? appDataFolder],
          }),
        ),
      ),
    );
    return _json(response)['id'] as String;
  }

  @override
  Future<void> upload({
    required String name,
    required String folderId,
    required Uint8List bytes,
  }) async {
    // A multipart upload carries the name in the metadata part and the
    // sealed bytes in the media part, in one request.
    final boundary = 'budget-${_randomHex(16)}';
    final metadata = jsonEncode({
      'name': name,
      'parents': [folderId],
    });
    final body = BytesBuilder()
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '$metadata\r\n'
          '--$boundary\r\n'
          'Content-Type: application/octet-stream\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    await _send(
      'POST',
      _uploadApi,
      query: {'uploadType': 'multipart', 'fields': 'id'},
      headers: {'content-type': 'multipart/related; boundary=$boundary'},
      body: body.takeBytes(),
    );
  }

  @override
  Future<Uint8List> download(String fileId) async {
    final response = await _send(
      'GET',
      _api.replace(path: '${_api.path}/$fileId'),
      query: {'alt': 'media'},
    );
    return response.body;
  }

  @override
  Future<void> delete(String fileId) async {
    await _send('DELETE', _api.replace(path: '${_api.path}/$fileId'));
  }

  Future<DriveResponse> _send(
    String method,
    Uri uri, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Uint8List? body,
  }) async {
    final token = await access.accessToken();
    if (token == null || token.isEmpty) {
      throw const DriveException('Google Drive isn’t connected on this device');
    }
    final response = await transport.send(
      method: method,
      uri: query == null || query.isEmpty
          ? uri
          : uri.replace(queryParameters: {...uri.queryParameters, ...query}),
      headers: {'authorization': 'Bearer $token', ...?headers},
      body: body,
    );
    if (response.status < 200 || response.status >= 300) {
      throw DriveException('Google Drive answered ${response.status}');
    }
    return response;
  }

  static Map<String, Object?> _json(DriveResponse response) =>
      (jsonDecode(utf8.decode(response.body)) as Map).cast<String, Object?>();

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return [
      for (var i = 0; i < bytes; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

/// [DriveTransport] over `dart:io`, for Android and macOS.
final class HttpDriveTransport implements DriveTransport {
  const HttpDriveTransport({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;

  @override
  Future<DriveResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Uint8List? body,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      for (final MapEntry(:key, :value) in headers.entries) {
        request.headers.set(key, value);
      }
      if (body != null) request.add(body);
      final response = await request.close().timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
      }
      return DriveResponse(
        status: response.statusCode,
        body: bytes.takeBytes(),
      );
    } on TimeoutException {
      throw const DriveException('Google Drive timed out');
    } on SocketException {
      throw const DriveException('Couldn’t reach Google Drive');
    } finally {
      client.close();
    }
  }
}
