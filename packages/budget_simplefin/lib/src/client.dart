import 'dart:convert';
import 'dart:io';

import 'package:budget_core/budget_core.dart';

import 'access.dart';
import 'claim.dart';

/// One HTTP exchange, so tests answer from recorded synthetic responses
/// instead of the network (ticket 10).
abstract interface class SimpleFinTransport {
  Future<SimpleFinReply> send(
    String method,
    Uri url, {
    String? body,
    String? authorization,
  });
}

/// A response's status and body.
final class SimpleFinReply {
  const SimpleFinReply(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// One request a [SimpleFinTransport] was asked to make, as
/// [FakeSimpleFinTransport] records it.
final class SimpleFinRequest {
  const SimpleFinRequest({
    required this.method,
    required this.url,
    this.body,
    this.authorization,
  });

  final String method;
  final Uri url;
  final String? body;
  final String? authorization;
}

/// A claim or fetch that failed, with a message to show the person.
final class SimpleFinException implements Exception {
  const SimpleFinException(this.message, {this.authFailed = false});

  final String message;

  /// True when the bridge refused the access URL itself, which pauses
  /// automatic fetches until the person re-links (ticket 10).
  final bool authFailed;

  @override
  String toString() => message;
}

/// Talks to the SimpleFIN Bridge: claim a setup token, then fetch accounts
/// (ticket 03). It never sees the request budget; the app checks that
/// first.
final class SimpleFinClient {
  const SimpleFinClient(this.transport);

  final SimpleFinTransport transport;

  /// Claims [setupToken], the base64 of a claim URL, and returns the access
  /// URL the bridge answers with. A token can be claimed only once.
  Future<SimpleFinAccess> claim(String setupToken) async {
    final Uri claimUrl;
    try {
      claimUrl = Uri.parse(
        utf8.decode(base64Decode(setupToken.replaceAll(RegExp(r'\s'), ''))),
      );
    } on FormatException {
      throw const SimpleFinException(
        'That setup token doesn’t look right. Copy it again from SimpleFIN.',
      );
    }
    if (!claimUrl.isScheme('https') && !claimUrl.isScheme('http')) {
      throw const SimpleFinException(
        'That setup token doesn’t hold a SimpleFIN claim link.',
      );
    }

    final reply = await transport.send('POST', claimUrl, body: '');
    if (reply.statusCode == 403) {
      throw const SimpleFinException(
        'That setup token was already claimed. Make a new one in SimpleFIN.',
      );
    }
    if (reply.statusCode != 200) {
      throw SimpleFinException(
        'SimpleFIN couldn’t claim that token (${reply.statusCode}).',
      );
    }
    final access = reply.body.trim();
    if (!SimpleFinAccess.isAccessUrl(access)) {
      throw const SimpleFinException(
        'SimpleFIN didn’t send an access URL. Try a new setup token.',
      );
    }
    return SimpleFinAccess(access);
  }

  /// Fetches every account and its transactions from [start] to [end],
  /// pending ones included. [today] dates a pending charge the bridge sends
  /// without a posted time.
  Future<FetchResult> fetch(
    SimpleFinAccess access, {
    required CivilDate start,
    required CivilDate end,
    required CivilDate today,
  }) async {
    final reply = await transport.send(
      'GET',
      access.accountsUri(start: start, end: end),
      authorization: access.authorization,
    );
    if (reply.statusCode == 401 || reply.statusCode == 403) {
      throw const SimpleFinException(
        'SimpleFIN refused the access URL. Re-link your bank.',
        authFailed: true,
      );
    }
    if (reply.statusCode != 200) {
      throw SimpleFinException('SimpleFIN answered ${reply.statusCode}.');
    }

    try {
      final json = jsonDecode(reply.body);
      if (json is! Map) throw const FormatException('Not a JSON object');
      return FetchResult.fromJson(json.cast<String, Object?>(), today: today);
    } on FormatException {
      throw const SimpleFinException(
        'SimpleFIN sent a response this app can’t read.',
      );
    } on TypeError {
      throw const SimpleFinException(
        'SimpleFIN sent a response this app can’t read.',
      );
    }
  }
}

/// The real transport, over `dart:io`'s [HttpClient].
final class HttpSimpleFinTransport implements SimpleFinTransport {
  const HttpSimpleFinTransport();

  @override
  Future<SimpleFinReply> send(
    String method,
    Uri url, {
    String? body,
    String? authorization,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, url);
      if (authorization != null) {
        request.headers.set(HttpHeaders.authorizationHeader, authorization);
      }
      if (body != null) {
        final bytes = utf8.encode(body);
        request.headers.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close();
      return SimpleFinReply(
        response.statusCode,
        await utf8.decoder.bind(response).join(),
      );
    } finally {
      client.close();
    }
  }
}

/// Answers each request from [replies] and records what was asked, so tests
/// run against recorded synthetic responses instead of the network.
final class FakeSimpleFinTransport implements SimpleFinTransport {
  FakeSimpleFinTransport({Map<String, SimpleFinReply> replies = const {}})
    : replies = Map.of(replies);

  /// By `METHOD path`, such as `GET /simplefin/access/xyz/accounts`.
  final Map<String, SimpleFinReply> replies;

  final requests = <SimpleFinRequest>[];

  @override
  Future<SimpleFinReply> send(
    String method,
    Uri url, {
    String? body,
    String? authorization,
  }) async {
    requests.add(
      SimpleFinRequest(
        method: method,
        url: url,
        body: body,
        authorization: authorization,
      ),
    );
    return replies['$method ${url.path}'] ??
        const SimpleFinReply(404, 'No recorded response');
  }
}
