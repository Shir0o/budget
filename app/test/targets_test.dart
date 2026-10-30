import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BudgetEngine _engine(EventLog log) =>
    BudgetEngine(log: log, deviceId: 'test-device', actor: Actor.userAndroid);

String _id(CommandResult result, String field) =>
    (result as Accepted).events.first.payload[field] as String;

/// A budget with [income] in checking and a Bills group.
final class _Seed {
  _Seed({int income = 100000}) {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: Money(income),
        asOf: CivilDate(month.year, month.month, 1),
      ),
    );
    checking = engine.state.accounts.single.id;
    bills = _id(
      engine.execute(const CreateCategoryGroup(name: 'Bills')),
      'categoryGroupId',
    );
  }

  final log = InMemoryEventLog();
  late final engine = _engine(log);
  final services = AppServices.inMemory();
  final month = thisMonth();
  late final String checking;
  late final String bills;

  String category(String name, {Target? target, AutomationMode? mode}) {
    final id = _id(
      engine.execute(CreateCategory(groupId: bills, name: name)),
      'categoryId',
    );
    if (target != null) {
      engine.execute(SetTarget(categoryId: id, target: target));
    }
    if (mode != null) {
      engine.execute(SetAutomationMode(categoryId: id, mode: mode));
    }
    return id;
  }

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine(log), services: services);

  BudgetState get state => BudgetState.replay(log.readAll());
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

KeepAtLeastTarget _keep(int cents) => KeepAtLeastTarget(amount: Money(cents));

void main() {
  testWidgets('sets a Repeating Target and shows what it needs this month', (
    tester,
  ) async {
    final seed = _Seed();
    final car = seed.category('Car insurance');
    await tester.pumpWidget(seed.app());

    await _tap(tester, find.text('Car insurance'));
    await _tap(tester, find.text('Set'));
    expect(find.text('Target · Car insurance'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('target-amount')), '600');
    await tester.enterText(find.byKey(const ValueKey('target-every')), '6');
    await tester.pumpAndSettle();

    // Due on the 1st of next month: two months share it.
    final month = seed.month;
    expect(find.text('Needed in ${monthName(month)}'), findsOneWidget);
    expect(
      find.text(
        '600.00 over 2 months, '
        '${formatMonth(month).substring(0, 3)}–'
        '${formatMonth(month.next).substring(0, 3)}',
      ),
      findsOneWidget,
    );
    expect(find.text('300.00'), findsOneWidget);
    await _tap(tester, find.text('Save'));

    expect(find.text('Repeating · \$600.00 every 6 months'), findsOneWidget);
    expect(
      find.text('300.00 more needed in ${monthName(month)}'),
      findsOneWidget,
    );
    final target = seed.state.target(car) as RepeatingTarget;
    expect(target.every, 6);
    expect(target.interval, TargetInterval.months);

    await _tap(tester, find.text('Auto'));
    expect(seed.state.automationMode(car), AutomationMode.auto);
    expect(find.textContaining('Assigns to its Target'), findsOneWidget);
  });

  testWidgets('Assign accepts the checked lines of the Suggestion Batch as '
      'the person', (tester) async {
    final seed = _Seed(income: 41200);
    final month = seed.month;
    final electric = seed.category('Electric', target: _keep(9000));
    final phone = seed.category('Phone', target: _keep(4500));
    final rent = seed.category(
      'Rent',
      target: RepeatingTarget(
        amount: const Money(160000),
        every: 1,
        interval: TargetInterval.months,
        nextDue: CivilDate(month.year, month.month, 28),
      ),
    );
    await tester.pumpWidget(seed.app());

    await _tap(tester, find.text('Assign'));
    expect(find.text('Assign · ${monthName(month)}'), findsOneWidget);
    expect(find.text('Tops up to 90.00 · has 0.00'), findsOneWidget);
    expect(
      find.text(
        'Partial · 1,323.00 still needed by '
        '${formatDay(CivilDate(month.year, month.month, 28))}',
      ),
      findsOneWidget,
    );
    expect(find.text('Accept 3 lines · \$412.00'), findsOneWidget);

    await _tap(tester, find.text('Phone'));
    expect(find.text('Accept 2 lines · \$367.00'), findsOneWidget);
    await _tap(tester, find.text('Accept 2 lines · \$367.00'));

    final state = seed.state;
    expect(state.assigned(electric, month), const Money(9000));
    expect(state.assigned(rent, month), const Money(27700));
    expect(state.assigned(phone, month), Money.zero);
    final accepted = seed.log.readAll().toList().reversed.take(2).toList();
    expect(accepted.map((e) => e.groupId).toSet(), hasLength(1));
    expect(accepted.map((e) => e.actor).toSet(), {Actor.userAndroid});
    expect(accepted.map((e) => e.payload['note']).toSet(), {
      'accepted automation suggestion',
    });
  });

  testWidgets('auto Categories fill on the first open of a month, as '
      'automation', (tester) async {
    final seed = _Seed();
    final phone = seed.category(
      'Phone',
      target: _keep(4500),
      mode: AutomationMode.auto,
    );
    await tester.pumpWidget(seed.app());
    await tester.pumpAndSettle();

    expect(seed.state.assigned(phone, seed.month), const Money(4500));
    expect(seed.log.readAll().last.actor, Actor.automation);

    // Taken back by hand, it stays taken back on the next open.
    _engine(seed.log).execute(
      SetAssignment(categoryId: phone, month: seed.month, amount: Money.zero),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(seed.app());
    await tester.pumpAndSettle();
    expect(seed.state.assigned(phone, seed.month), Money.zero);
  });

  testWidgets('Categories & priority sets the order by drag', (tester) async {
    final seed = _Seed();
    final rent = seed.category('Rent');
    final electric = seed.category('Electric');
    final phone = seed.category('Phone', mode: AutomationMode.auto);
    await tester.pumpWidget(seed.app());

    await _tap(tester, find.byTooltip('Settings'));
    await _tap(tester, find.text('Category priority'));
    expect(find.text('Categories & priority'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);

    final gesture = await tester.startGesture(
      // Phone's handle.
      tester.getCenter(find.byIcon(Icons.drag_indicator).last),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      [for (final c in seed.state.priority) c.id],
      [phone, rent, electric],
    );
  });

  testWidgets('Assign lists overspending to Cover and card debt to Fund', (
    tester,
  ) async {
    final seed = _Seed();
    final month = seed.month;
    final dining = seed.category('Dining out');
    seed.engine.execute(
      CreateTransaction(
        accountId: seed.checking,
        date: CivilDate(month.year, month.month, 1),
        amount: const Money(-3000),
        lines: [LineInput(amount: const Money(-3000), category: dining)],
      ),
    );
    seed.engine.execute(
      AddAccount(
        name: 'Visa',
        type: AccountType.creditCard,
        startingBalance: const Money(-5000),
        asOf: CivilDate(month.year, month.month, 1),
      ),
    );
    final visa = seed.engine.state.accounts.last.id;
    final payment = seed.engine.state.cardPaymentCategory(visa)!.id;
    await tester.pumpWidget(seed.app());

    await _tap(tester, find.text('Assign'));
    expect(find.text('Not covered by this batch'), findsOneWidget);
    expect(find.text('Overspent −30.00'), findsOneWidget);
    expect(find.text('50.00 not funded · automation off'), findsOneWidget);

    await _tap(tester, find.text('Fund'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('assign-amount')))
          .controller!
          .text,
      '50.00',
    );
    await _tap(tester, find.text('Save'));
    expect(seed.state.assigned(payment, month), const Money(5000));

    await _tap(tester, find.text('Cover'));
    await _tap(tester, find.text('Ready to Assign'));
    await _tap(tester, find.text('Save'));
    expect(seed.state.available(dining, month), Money.zero);
    expect(find.text('Not covered by this batch'), findsNothing);
  });
}
