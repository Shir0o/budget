import 'package:budget/app.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [app] on a phone-sized screen, like the canvas's 390 × 844.
Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Go back to a date views the past read-only and restores it', (
    tester,
  ) async {
    final now = DateTime.now();
    final yesterday = CivilDate.fromDateTime(
      DateTime(now.year, now.month, now.day - 1),
    );
    final month = CalendarMonth.of(yesterday);
    // A synthetic budget made two days ago, changed again today.
    var clock = DateTime(now.year, now.month, now.day - 2, 9);
    final log = InMemoryEventLog();
    final engine = BudgetEngine(
      log: log,
      deviceId: 'test-device',
      actor: Actor.userAndroid,
      nowMs: () => (clock = clock.add(
        const Duration(seconds: 1),
      )).millisecondsSinceEpoch,
    );
    String created(Command command, String key) =>
        (engine.execute(command) as Accepted).events.first.payload[key]
            as String;
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
        asOf: yesterday,
      ),
    );
    final group = created(
      const CreateCategoryGroup(name: 'Everyday'),
      'categoryGroupId',
    );
    final groceries = created(
      CreateCategory(groupId: group, name: 'Groceries'),
      'categoryId',
    );
    engine.execute(
      SetAssignment(
        categoryId: groceries,
        month: month,
        amount: const Money(10000),
      ),
    );
    clock = DateTime(now.year, now.month, now.day, 0, 0, 1);
    engine.execute(
      SetAssignment(
        categoryId: groceries,
        month: month,
        amount: const Money(25000),
      ),
    );
    engine.execute(CreateCategory(groupId: group, name: 'Dining out'));
    final count = log.readAll().length;

    await _pump(tester, BudgetApp(engine: engine));
    await _tap(tester, find.text('History'));
    await _tap(tester, find.text('Go back to a date'));
    await _tap(tester, find.text('OK')); // Yesterday, as the picker opens.

    expect(
      find.text('Viewing ${formatDate(yesterday)} · read-only'),
      findsOneWidget,
    );
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('100.00'), findsNWidgets(2)); // Assigned, Available
    expect(find.text('Dining out'), findsNothing);
    expect(find.byType(MainNav), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('Undoes 2 changes as one group, which you can revert.'),
      findsOneWidget,
    );
    expect(log.readAll(), hasLength(count), reason: 'viewing is read-only');

    await _tap(tester, find.text('Restore to ${formatDay(yesterday)}'));

    expect(find.text('Change History'), findsOneWidget);
    expect(find.text('Restored to ${formatDate(yesterday)}'), findsOneWidget);
    final state = BudgetState.replay(log.readAll());
    expect(state.assigned(groceries, month), const Money(10000));
    expect(state.categories.map((c) => c.name), ['Groceries']);
    final restore = engine.history.entries().first;
    expect(restore.events.map((e) => e.groupId).toSet(), hasLength(1));
    expect(restore.canRevert, isTrue);
  });
}
