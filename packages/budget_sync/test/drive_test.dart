import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_sync/budget_sync.dart';
import 'package:test/test.dart';

typedef _Request = ({
  String method,
  Uri uri,
  Map<String, String> headers,
  Uint8List? body,
});

/// A transport that records each request and answers from [reply].
final class _FakeTransport implements DriveTransport {
  _FakeTransport(this.reply);

  final DriveResponse Function() reply;
  final requests = <_Request>[];

  @override
  Future<DriveResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Uint8List? body,
  }) async {
    requests.add((method: method, uri: uri, headers: headers, body: body));
    return reply();
  }
}

DriveResponse _json(Object value) => DriveResponse(
  status: 200,
  body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
);

final class _Token implements DriveAccess {
  _Token(this.token);

  String? token;

  @override
  Future<String?> accessToken() async => token;
}

GoogleDriveAppData _drive(_FakeTransport transport, {String? token = 'tok'}) =>
    GoogleDriveAppData(transport: transport, access: _Token(token));

void main() {
  test('lists the app data folder, never another space', () async {
    final transport = _FakeTransport(() => _json({'files': []}));
    await _drive(transport).list(null);

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.host, 'www.googleapis.com');
    expect(request.uri.path, '/drive/v3/files');
    expect(request.uri.queryParameters['spaces'], 'appDataFolder');
    expect(request.uri.queryParameters['q'], 'trashed = false');
    expect(request.headers['authorization'], 'Bearer tok');
  });

  test('lists a folder by parent, with no other space named', () async {
    final transport = _FakeTransport(
      () => _json({
        'files': [
          {'id': 'file-1', 'name': 'seg-000001.bin'},
          {
            'id': 'folder-1',
            'name': 'device-a',
            'mimeType': 'application/vnd.google-apps.folder',
          },
        ],
      }),
    );
    final entries = await _drive(transport).list('budget-folder');

    final query = transport.requests.single.uri.queryParameters;
    expect(query['q'], "'budget-folder' in parents and trashed = false");
    expect(query.containsKey('spaces'), isFalse);
    expect(entries.map((e) => e.name), ['seg-000001.bin', 'device-a']);
    expect(entries.last.isFolder, isTrue);
  });

  test('makes a folder in the folder it is given', () async {
    final transport = _FakeTransport(() => _json({'id': 'folder-9'}));
    final id = await _drive(transport).createFolder('device-a', folderId: 'b');

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.headers['content-type'], contains('application/json'));
    final body = jsonDecode(utf8.decode(request.body!)) as Map;
    expect(body['name'], 'device-a');
    expect(body['parents'], ['b']);
    expect(body['mimeType'], 'application/vnd.google-apps.folder');
    expect(id, 'folder-9');
  });

  test('uploads sealed bytes as a multipart file in its folder', () async {
    final transport = _FakeTransport(() => _json({'id': 'file-2'}));
    final bytes = Uint8List.fromList([1, 2, 3, 0xFF]);
    await _drive(
      transport,
    ).upload(name: 'seg-000001.bin', folderId: 'device-folder', bytes: bytes);

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/upload/drive/v3/files');
    expect(request.uri.queryParameters['uploadType'], 'multipart');
    expect(request.headers['content-type'], startsWith('multipart/related'));
    final body = request.body!;
    expect(String.fromCharCodes(body), contains('"name":"seg-000001.bin"'));
    expect(String.fromCharCodes(body), contains('"parents":["device-folder"]'));
    // The media part is the sealed file, byte for byte.
    final media = body.indexOf(0x01);
    expect(body.sublist(media, media + 4), [1, 2, 3, 0xFF]);
  });

  test('downloads, deletes, and reports what failed', () async {
    final transport = _FakeTransport(
      () => DriveResponse(status: 200, body: Uint8List.fromList([9, 8])),
    );
    expect(await _drive(transport).download('file-2'), [9, 8]);
    expect(transport.requests.single.uri.queryParameters['alt'], 'media');

    await _drive(transport).delete('file-2');
    expect(transport.requests.last.method, 'DELETE');
    expect(transport.requests.last.uri.path, '/drive/v3/files/file-2');
  });

  test('says so when Drive is not connected', () async {
    final transport = _FakeTransport(() => _json({'files': []}));
    expect(
      () => _drive(transport, token: null).list(null),
      throwsA(
        isA<DriveException>().having(
          (e) => e.message,
          'message',
          'Google Drive isn’t connected on this device',
        ),
      ),
    );
    expect(transport.requests, isEmpty);
  });

  test('reports an unaccepted answer', () async {
    final transport = _FakeTransport(
      () => DriveResponse(status: 401, body: Uint8List(0)),
    );
    expect(
      () => _drive(transport).list(null),
      throwsA(
        isA<DriveException>().having(
          (e) => e.message,
          'message',
          'Google Drive answered 401',
        ),
      ),
    );
  });
}
