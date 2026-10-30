import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:test/test.dart';

/// One hand-written Event, as a device or an older build would have written
/// it.
Event _event(
  String type,
  Map<String, Object?> payload, {
  required String deviceId,
  required int wallMs,
  String budgetId = 'budget-1',
  String? actor,
}) => Event(
  id: '$deviceId-$wallMs-$type',
  budgetId: budgetId,
  deviceId: deviceId,
  hlc: Hlc(wallMs, 0, deviceId),
  actor: Actor.fromValue(actor ?? 'user@android'),
  groupId: '$deviceId-$wallMs',
  type: type,
  payload: payload,
);

Map<String, Object?> _line(int cents, {String? category}) => {
  'lineId': 'line-$cents',
  'amountCents': cents,
  'category': category,
};

/// A log with one of each broken invariant.
List<Event> _brokenLog() => [
  _event(EventType.budgetCreated, {'name': 'Home'}, deviceId: 'a', wallMs: 1),
  _event(
    EventType.accountCreated,
    {'accountId': 'checking', 'name': 'Checking', 'accountType': 'checking'},
    deviceId: 'a',
    wallMs: 2,
  ),
  // A credit card whose Card Payment Category never arrived.
  _event(
    EventType.accountCreated,
    {'accountId': 'visa', 'name': 'Visa', 'accountType': 'creditCard'},
    deviceId: 'a',
    wallMs: 3,
  ),
  // Lines that don't add up to the amount.
  _event(
    EventType.transactionCreated,
    {
      'transactionId': 'wrong-sum',
      'accountId': 'checking',
      'date': '2026-11-12',
      'payee': 'Corner Bistro',
      'amountCents': -3000,
      'lines': [_line(-2000)],
    },
    deviceId: 'a',
    wallMs: 4,
  ),
  // A transfer whose other side isn't here.
  _event(
    EventType.transactionCreated,
    {
      'transactionId': 'lonely-transfer',
      'accountId': 'checking',
      'date': '2026-11-12',
      'payee': '',
      'amountCents': -1000,
      'transferAccountId': 'visa',
      'transferTransactionId': 'gone',
      'lines': [_line(-1000)],
    },
    deviceId: 'b',
    wallMs: 5,
  ),
];

void main() {
  group('needsAttention', () {
    test('reports every invariant a merge left broken', () {
      final state = BudgetState.replay(_brokenLog());
      final items = needsAttention(state);

      expect(items.map((item) => item.kind), [
        AttentionKind.splitSum,
        AttentionKind.transferPair,
        AttentionKind.cardPayment,
      ]);
      expect(
        items[0].message,
        'The lines of “Corner Bistro” don’t add up to its amount.',
      );
      expect(items[0].transactionId, 'wrong-sum');
      expect(items[1].message, 'The other side of Checking is missing.');
      expect(items[1].transactionId, 'lonely-transfer');
      expect(items[2].message, 'Visa has no Card Payment Category.');
    });

    test('reports nothing for a sound budget', () {
      final log = InMemoryEventLog();
      final engine = BudgetEngine(
        log: log,
        deviceId: 'a',
        actor: Actor.userAndroid,
      );
      engine.execute(const CreateBudget(name: 'Home'));
      engine.execute(
        AddAccount(
          name: 'Checking',
          type: AccountType.checking,
          startingBalance: const Money(100000),
          asOf: CivilDate(2026, 11, 1),
        ),
      );
      expect(needsAttention(engine.state), isEmpty);
    });
  });

  group('BudgetEngine.merge', () {
    late BudgetEngine engine;

    setUp(() {
      engine = BudgetEngine(
        log: InMemoryEventLog(),
        deviceId: 'a',
        actor: Actor.userAndroid,
      );
      engine.execute(const CreateBudget(name: 'Home'));
    });

    test('keeps an Event type this version does not know', () {
      final before = stateJson(engine.state, month: CalendarMonth(2026, 11));
      final now = DateTime.now().millisecondsSinceEpoch;
      final added = engine.merge([
        _event('SomethingNewer', {'x': 1}, deviceId: 'b', wallMs: now + 1000),
      ]);
      expect(added, hasLength(1));
      expect(engine.events, contains(added.single));
      // Replay skips it, so the projection is untouched.
      expect(stateJson(engine.state, month: CalendarMonth(2026, 11)), before);
      expect(
        engine.history.entries().any(
          (entry) =>
              entry.summary == 'A change this version of the app doesn’t know',
        ),
        isTrue,
      );
    });

    test('adds each Event once, in HLC order', () {
      final base = DateTime.now().millisecondsSinceEpoch + 1000;
      final earlier = _event(
        EventType.budgetCreated,
        {'name': 'Other'},
        deviceId: 'b',
        wallMs: base,
      );
      final later = _event(
        EventType.budgetCreated,
        {'name': 'Other'},
        deviceId: 'b',
        wallMs: base + 1,
      );
      engine.merge([later, earlier]);
      engine.merge([later, earlier]);
      expect(engine.events.map((e) => e.id).toSet(), hasLength(3));
      expect(engine.events[1].id, earlier.id);
      expect(engine.events[2].id, later.id);
      // This device's next Event sorts after everything merged.
      engine.execute(const CreateCategoryGroup(name: 'Everyday'));
      expect(engine.events.last.id, isNot(later.id));
      expect(engine.events.last.hlc.compareTo(later.hlc) > 0, isTrue);
    });
  });
}
