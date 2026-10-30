import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:test/test.dart';

final _today = CivilDate(2026, 11, 12);
final _morning = DateTime.utc(2026, 11, 12, 8);
const _accessUrl = 'https://user:pass@bridge.example/simplefin/access/xyz';

LinkedAccount _link() => LinkedAccount(
  simpleFinId: 'acct-1',
  institution: 'Sample Bank',
  name: 'Everyday Checking ...1234',
  linkedFrom: _today.addDays(-30),
  accountId: 'app-1',
);

SimpleFinBook _book({
  DateTime? lastAttempt,
  RequestCount requests = const RequestCount(),
  AuthState auth = AuthState.linked,
  List<BankError> errors = const [],
}) => SimpleFinBook(
  accessUrl: _accessUrl,
  links: [_link()],
  requests: requests,
  schedule: FetchSchedule(lastAttempt: lastAttempt),
  auth: auth,
  errors: errors,
);

void main() {
  group('FetchSchedule', () {
    test('is due before the first automatic fetch', () {
      expect(const FetchSchedule().isDue(_morning), isTrue);
    });

    test('waits the full 6 hours between automatic fetches', () {
      final schedule = FetchSchedule(lastAttempt: _morning);

      expect(schedule.isDue(_morning.add(const Duration(hours: 5))), isFalse);
      expect(
        schedule.isDue(
          _morning.add(const Duration(hours: 5, minutes: 59, seconds: 59)),
        ),
        isFalse,
      );
      expect(schedule.isDue(_morning.add(const Duration(hours: 6))), isTrue);
    });

    test('reads a local clock against a UTC attempt', () {
      final schedule = FetchSchedule(lastAttempt: _morning);
      final local = _morning.toLocal().add(const Duration(hours: 6));

      expect(schedule.isDue(local), isTrue);
    });

    test('records the attempt in UTC and round-trips it', () {
      final schedule = const FetchSchedule().attemptedAt(_morning.toLocal());
      final restored = FetchSchedule.fromJson(schedule.toJson());

      expect(schedule.lastAttempt!.isUtc, isTrue);
      expect(restored.lastAttempt, _morning);
      expect(restored.isDue(_morning.add(const Duration(hours: 5))), isFalse);
    });
  });

  group('automatic fetches', () {
    test('run on a linked book once 6 hours have passed', () {
      final due = _book(lastAttempt: _morning.add(const Duration(hours: -6)));

      expect(due.automaticFetchDue(_morning), isTrue);
      expect(
        due
            .attemptedAutomatically(_morning)
            .automaticFetchDue(_morning.add(const Duration(hours: 1))),
        isFalse,
      );
    });

    test('stop when the day’s request budget is spent', () {
      final spent = _book(
        requests: RequestCount(day: _today, used: RequestCount.dailyLimit),
      );

      expect(spent.automaticFetchDue(_morning), isFalse);
      expect(spent.requests.remaining(_today), 0);
    });

    test('are paused after an auth failure, until a re-link', () {
      final refused = _book().needsRelink();

      expect(refused.auth, AuthState.needsRelink);
      expect(refused.automaticPaused, isTrue);
      expect(refused.automaticFetchDue(_morning), isFalse);
      // The link and the access URL stay, so re-linking keeps the accounts.
      expect(refused.connected, isTrue);
      expect(refused.linkedAccounts, hasLength(1));

      final relinked = refused.withAccess(_accessUrl);
      expect(relinked.auth, AuthState.linked);
      expect(relinked.automaticPaused, isFalse);
      expect(relinked.automaticFetchDue(_morning), isTrue);
    });

    test('resume after a successful fetch proves the link works', () {
      final book = _book(auth: AuthState.needsRelink).resumed();

      expect(book.auth, AuthState.linked);
      expect(book.automaticFetchDue(_morning), isTrue);
    });

    test('need a connected book', () {
      expect(const SimpleFinBook().automaticFetchDue(_morning), isFalse);
    });
  });

  group('bank errors and auth state', () {
    test('round-trip through JSON', () {
      final book = _book(
        lastAttempt: _morning,
        auth: AuthState.needsRelink,
        errors: [
          BankError(
            message: 'Re-authenticate with your bank.',
            day: _today,
            auth: true,
          ),
        ],
      );

      final restored = SimpleFinBook.fromJson(book.toJson());

      expect(restored.auth, AuthState.needsRelink);
      expect(restored.schedule.lastAttempt, _morning);
      expect(restored.errors.single.message, 'Re-authenticate with your bank.');
      expect(restored.errors.single.day, _today);
      expect(restored.errors.single.auth, isTrue);
    });

    test('a later fetch replaces them', () {
      final book = _book(
        errors: [BankError(message: 'Old', day: _today)],
      );

      final replaced = book.withErrors([
        BankError(message: 'New', day: _today),
      ]);

      expect(replaced.errors.map((error) => error.message), ['New']);
    });

    test('a re-link clears the messages an auth failure left', () {
      final book = _book(
        auth: AuthState.needsRelink,
        errors: [BankError(message: 'Re-link', day: _today, auth: true)],
      ).withAccess(_accessUrl);

      expect(book.errors, isEmpty);
      expect(book.auth, AuthState.linked);
    });

    test('an old book reads as linked with no errors', () {
      final book = SimpleFinBook.fromJson({
        'accessUrl': _accessUrl,
        'links': <Object?>[],
      });

      expect(book.auth, AuthState.linked);
      expect(book.errors, isEmpty);
      expect(book.schedule.lastAttempt, isNull);
    });
  });
}
