import 'dart:convert';
import 'dart:io';

import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:test/test.dart';

final _today = CivilDate(2026, 11, 12);
final _start = CivilDate(2026, 8, 14);

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// The setup token a person pastes: base64 of the claim URL.
String _setupToken(String claimUrl) => base64Encode(utf8.encode(claimUrl));

SimpleFinReply _reply(String body, {int status = 200}) =>
    SimpleFinReply(status, body);

void main() {
  group('claim', () {
    test('posts the setup token and returns the access URL', () async {
      final transport = FakeSimpleFinTransport(
        replies: {
          'POST /simplefin/claim/abc123': _reply(
            'https://user:pass@bridge.example/simplefin/access/xyz\n',
          ),
        },
      );
      final client = SimpleFinClient(transport);

      final access = await client.claim(
        _setupToken('https://bridge.example/simplefin/claim/abc123'),
      );

      expect(
        access.value,
        'https://user:pass@bridge.example/simplefin/access/xyz',
      );
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.url.host, 'bridge.example');
      expect(request.url.path, '/simplefin/claim/abc123');
    });

    test('a claimed token fails with a message to show the person', () async {
      final client = SimpleFinClient(
        FakeSimpleFinTransport(
          replies: {'POST /simplefin/claim/abc123': _reply('', status: 403)},
        ),
      );

      await expectLater(
        client.claim(
          _setupToken('https://bridge.example/simplefin/claim/abc123'),
        ),
        throwsA(
          isA<SimpleFinException>().having(
            (error) => error.message,
            'message',
            contains('already claimed'),
          ),
        ),
      );
    });

    test('rejects a token that is not base64', () async {
      final client = SimpleFinClient(FakeSimpleFinTransport());

      await expectLater(
        client.claim('not a token'),
        throwsA(isA<SimpleFinException>()),
      );
    });
  });

  group('fetch', () {
    late FakeSimpleFinTransport transport;
    late FetchResult result;

    setUp(() async {
      transport = FakeSimpleFinTransport(
        replies: {
          'GET /simplefin/access/xyz/accounts': _reply(_fixture('fetch.json')),
        },
      );
      result = await SimpleFinClient(transport).fetch(
        SimpleFinAccess(
          'https://user:pass@bridge.example/simplefin/access/xyz',
        ),
        start: _start,
        end: _today,
        today: _today,
      );
    });

    test('asks for the window with pending=1 and basic auth', () {
      final request = transport.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/simplefin/access/xyz/accounts');
      // 2026-08-14 00:00 UTC to the end of 2026-11-12 UTC.
      expect(request.url.queryParameters['start-date'], '1786665600');
      expect(request.url.queryParameters['end-date'], '1794527999');
      expect(request.url.queryParameters['pending'], '1');
      expect(request.url.userInfo, isEmpty);
      expect(
        request.authorization,
        'Basic ${base64Encode(utf8.encode('user:pass'))}',
      );
    });

    test('parses balances and amounts to exact cents', () {
      final checking = result.accounts.first;
      expect(checking.id, 'acct-1');
      expect(checking.institution, 'Sample Bank');
      expect(checking.name, 'Everyday Checking ...1234');
      expect(checking.balance, const Money(123456));
      expect(checking.available, const Money(120006));
      expect(checking.balanceDate, _today);
      expect(checking.transactions, hasLength(2));

      final lunch = checking.transactions.first;
      expect(lunch.id, 'tx-1');
      expect(lunch.date, CivilDate(2026, 11, 10));
      expect(lunch.amount, const Money(-4820));
      expect(lunch.description, 'Corner Bistro');
      expect(lunch.memo, 'Lunch');
      expect(lunch.pending, isFalse);

      final card = result.accounts.last;
      expect(card.balance, const Money(-30215));
      expect(card.available, isNull);
    });

    test('dates a pending charge by transacted_at when posted is 0', () {
      final pending = result.accounts.first.transactions.last;
      expect(pending.pending, isTrue);
      expect(pending.date, _today);
      expect(pending.amount, const Money(-1200));
    });

    test('keeps at most the last four digits of a bank name', () {
      expect(result.accounts.last.displayName, 'Card ••••1111');
      expect(result.accounts.first.displayName, 'Everyday Checking ...1234');
    });

    test('shows the bridge’s errors', () async {
      final client = SimpleFinClient(
        FakeSimpleFinTransport(
          replies: {
            'GET /simplefin/access/xyz/accounts': _reply(
              '{"errors":["Re-authenticate with your bank"],"accounts":[]}',
            ),
          },
        ),
      );

      final answered = await client.fetch(
        SimpleFinAccess(
          'https://user:pass@bridge.example/simplefin/access/xyz',
        ),
        start: _start,
        end: _today,
        today: _today,
      );

      expect(answered.errors, ['Re-authenticate with your bank']);
      expect(answered.accounts, isEmpty);
    });

    test(
      'a refused access URL fails with a message to show the person',
      () async {
        final client = SimpleFinClient(
          FakeSimpleFinTransport(
            replies: {
              'GET /simplefin/access/xyz/accounts': _reply('', status: 403),
            },
          ),
        );

        await expectLater(
          client.fetch(
            SimpleFinAccess(
              'https://user:pass@bridge.example/simplefin/access/xyz',
            ),
            start: _start,
            end: _today,
            today: _today,
          ),
          throwsA(
            isA<SimpleFinException>().having(
              (error) => error.message,
              'message',
              contains('Re-link'),
            ),
          ),
        );
      },
    );

    test(
      'an amount with more than two decimals is refused, not rounded',
      () async {
        final client = SimpleFinClient(
          FakeSimpleFinTransport(
            replies: {
              'GET /simplefin/access/xyz/accounts': _reply(
                '{"errors":[],"accounts":[{"org":{"name":"Sample Bank"},'
                '"id":"acct-1","name":"Checking","currency":"USD",'
                '"balance":"1.234","balance-date":1794441600,'
                '"transactions":[]}]}',
              ),
            },
          ),
        );

        await expectLater(
          client.fetch(
            SimpleFinAccess(
              'https://user:pass@bridge.example/simplefin/access/xyz',
            ),
            start: _start,
            end: _today,
            today: _today,
          ),
          throwsA(isA<SimpleFinException>()),
        );
      },
    );
  });
}
