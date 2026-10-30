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

/// A budget with [income] in checking, a Bills group and a Rent Category.
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
    rent = _id(
      engine.execute(CreateCategory(groupId: bills, name: 'Rent')),
      'categoryId',
    );
  }

  final log = InMemoryEventLog();
  late final engine = _engine(log);
  final services = AppServices.inMemory();
  final month = thisMonth();
  late final String checking;
  late final String bills;
  late final String rent;

  static CivilDate get due =>
      CivilDate(thisMonth().year, thisMonth().month, 20);

  String schedule({
    String payee = 'Landlord',
    int cents = -100000,
    CivilDate? nextDue,
  }) => _id(
    engine.execute(
      CreateSchedule(
        accountId: checking,
        payee: payee,
        amount: Money(cents),
        category: rent,
        every: 1,
        interval: TargetInterval.months,
        nextDue: nextDue ?? due,
      ),
    ),
    'scheduleId',
  );

  void spend(CivilDate date, int cents, {required String payee}) =>
      engine.execute(
        CreateTransaction(
          accountId: checking,
          date: date,
          payee: payee,
          amount: Money(-cents),
          lines: [LineInput(amount: Money(-cents), category: rent)],
        ),
      );

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine(log), services: services);

  BudgetState get state => BudgetState.replay(log.readAll());
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openSchedules(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('Settings'));
  await _tap(tester, find.text('Scheduled transactions'));
}

void main() {
  testWidgets('a schedule created from Settings counts in nothing until it '
      'happens', (tester) async {
    final seed = _Seed();
    await tester.pumpWidget(seed.app());
    await _openSchedules(tester);

    expect(
      find.textContaining('No scheduled transactions yet'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Add schedule'));
    expect(find.text('New schedule'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('schedule-payee')),
      'Landlord',
    );
    await tester.enterText(
      find.byKey(const ValueKey('schedule-amount')),
      '1000',
    );
    await _tap(tester, find.text('Category'));
    await _tap(tester, find.text('Rent'));
    await _tap(tester, find.text('Save'));

    // Back on the list, with the schedule stored as an outflow.
    expect(find.text('Landlord'), findsOneWidget);
    final schedule = seed.state.schedules.single;
    expect(schedule.payee, 'Landlord');
    expect(schedule.amount, const Money(-100000));
    expect(schedule.category, seed.rent);
    // It starts on the 1st of next month until the date is changed.
    expect(
      schedule.nextDue,
      CivilDate(seed.month.next.year, seed.month.next.month, 1),
    );

    // Nothing counted: no spending, no Available, Ready to Assign intact.
    expect(seed.state.transactions.map((t) => t.payee), ['Starting Balance']);
    expect(seed.state.available(seed.rent, seed.month), Money.zero);
    expect(seed.state.readyToAssign(seed.month), const Money(100000));
  });

  testWidgets('Enter now writes an Unreviewed transaction for the due date '
      'and moves the schedule on', (tester) async {
    final seed = _Seed();
    final id = seed.schedule();
    await tester.pumpWidget(seed.app());
    await _openSchedules(tester);

    await _tap(tester, find.text('Landlord'));
    expect(find.text('Edit schedule'), findsOneWidget);
    // Enter now sits under the form.
    await tester.dragFrom(
      tester.getCenter(find.text('Repeats')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.textContaining('Enter now ·'));

    final state = seed.state;
    final transaction = state.transactions.last;
    expect(transaction.payee, 'Landlord');
    expect(transaction.date, _Seed.due);
    expect(transaction.lines.single.reviewed, isFalse);
    expect(state.reviewQueue, hasLength(1));
    expect(state.schedule(id)!.nextDue, _Seed.due.addMonths(1));
  });

  testWidgets('a repeating charge is only suggested until the person adds it', (
    tester,
  ) async {
    final seed = _Seed();
    for (var i = 0; i < 3; i++) {
      seed.spend(
        CivilDate(seed.month.year, seed.month.month, 10).addMonths(-3 + i),
        1599,
        payee: 'Netflix',
      );
    }
    await tester.pumpWidget(seed.app());
    await _openSchedules(tester);

    expect(find.text('Repeating charges'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    // Suggesting wrote nothing.
    expect(seed.state.schedules, isEmpty);

    await _tap(tester, find.text('Add'));
    expect(find.text('New schedule'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('schedule-payee')))
          .controller!
          .text,
      'Netflix',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('schedule-amount')))
          .controller!
          .text,
      '15.99',
    );
    await _tap(tester, find.text('Save'));

    final schedule = seed.state.schedules.single;
    expect(schedule.payee, 'Netflix');
    expect(schedule.amount, const Money(-1599));
    expect(schedule.category, seed.rent);
  });

  testWidgets('a Driven-by-schedule Target sums the Category\'s schedules, and '
      'the Forecast flags a short month', (tester) async {
    final seed = _Seed(income: 50000);
    seed.schedule(
      cents: -100000,
      nextDue: CivilDate(seed.month.year, seed.month.month, 1),
    );
    await tester.pumpWidget(seed.app());

    await _tap(tester, find.text('Rent'));
    await _tap(tester, find.text('Set'));
    await _tap(tester, find.text('Driven by schedule'));
    expect(find.text('Sums 1 scheduled transaction'), findsOneWidget);
    expect(find.text('1,000.00'), findsOneWidget);
    await _tap(tester, find.text('Save'));
    expect(find.text('Driven by schedule · 1 transaction'), findsOneWidget);
    expect(
      find.text('1,000.00 more needed in ${monthName(seed.month)}'),
      findsOneWidget,
    );

    await _tap(tester, find.byTooltip('Back to budget'));
    await _tap(tester, find.byTooltip('Settings'));
    await _tap(tester, find.text('Forecast'));
    expect(find.text(formatMonth(seed.month)), findsOneWidget);
    expect(
      find.textContaining('cannot cover their scheduled bills'),
      findsOneWidget,
    );
    expect(find.text('Short by 500.00'), findsOneWidget);
  });
}
