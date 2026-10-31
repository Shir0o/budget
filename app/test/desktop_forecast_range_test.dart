import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _id(CommandResult result, String field) =>
    (result as Accepted).events.first.payload[field] as String;

/// A synthetic budget with 100.00 in Checking, and the Scheduled
/// Transactions a test adds.
final class _Seed {
  _Seed() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(10000),
        asOf: today(),
      ),
    );
    checking = engine.state.accounts.single.id;
    final group = _id(
      engine.execute(const CreateCategoryGroup(name: 'Bills')),
      'categoryGroupId',
    );
    bills = _id(
      engine.execute(CreateCategory(groupId: group, name: 'Housing')),
      'categoryId',
    );
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  late final String checking;
  late final String bills;

  void schedule(
    String payee,
    int cents,
    int daysFromToday, {
    int every = 1,
    TargetInterval interval = TargetInterval.months,
  }) => engine.execute(
    CreateSchedule(
      accountId: checking,
      payee: payee,
      amount: Money(cents),
      category: cents < 0 ? bills : readyToAssignCategory,
      every: every,
      interval: interval,
      nextDue: today().addDays(daysFromToday),
    ),
  );
}

Future<void> _open(
  WidgetTester tester,
  void Function(_Seed seed) seed, {
  String range = '30 days',
}) async {
  final s = _Seed();
  seed(s);
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    BudgetApp(
      engine: BudgetEngine(
        log: s.log,
        deviceId: 'test-device',
        actor: Actor.userAndroid,
      ),
      services: AppServices.inMemory(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('section-forecast')));
  await tester.pumpAndSettle();
  if (range != '30 days') {
    await tester.tap(find.text(range));
    await tester.pumpAndSettle();
  }
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  testWidgets('a weekly schedule comes up every week of 90 days', (
    tester,
  ) async {
    await _open(
      tester,
      (s) => s.schedule('Gym', -1000, 0, interval: TargetInterval.weeks),
      range: '90 days',
    );
    final coming = find.byKey(const ValueKey('forecast-coming'));
    // Days 0, 7, ... 84 of the 90.
    expect(
      find.descendant(of: coming, matching: find.text('Gym')),
      findsNWidgets(13),
    );
    expect(_text(tester, 'forecast-expenses'), '\$130.00');
  });

  testWidgets('LOWEST catches a bill due the day before payday', (
    tester,
  ) async {
    await _open(tester, (s) {
      s.schedule('Rent', -25000, 9);
      s.schedule('Paycheck', 30000, 10);
    });
    // 100.00 - 250.00 on day 9, before the 300.00 arrives on day 10.
    expect(_text(tester, 'forecast-lowest'), '−\$150.00');
    expect(_text(tester, 'forecast-expenses'), '\$250.00');
  });

  testWidgets('30 days are 30 real days, not the rest of the month', (
    tester,
  ) async {
    await _open(tester, (s) {
      s.schedule('Last day', -1000, 29);
      s.schedule('Too late', -5000, 30);
    });
    final coming = find.byKey(const ValueKey('forecast-coming'));
    expect(
      find.descendant(of: coming, matching: find.text('Last day')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: coming, matching: find.text('Too late')),
      findsNothing,
    );
    expect(_text(tester, 'forecast-expenses'), '\$10.00');
    expect(_text(tester, 'forecast-lowest'), '\$90.00');
  });

  testWidgets('an overdue schedule is listed as overdue and counted', (
    tester,
  ) async {
    await _open(tester, (s) => s.schedule('Late bill', -2000, -3));
    expect(find.textContaining('Overdue'), findsOneWidget);
    // The overdue bill, then the next one 27 days on.
    expect(_text(tester, 'forecast-expenses'), '\$40.00');
    expect(_text(tester, 'forecast-lowest'), '\$60.00');
  });
}
