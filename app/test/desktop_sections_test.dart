import 'dart:convert';

import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BudgetEngine _engine(EventLog log, {Actor actor = Actor.userAndroid}) =>
    BudgetEngine(log: log, deviceId: 'test-device', actor: actor);

String _id(CommandResult result, String field) =>
    (result as Accepted).events.first.payload[field] as String;

Future<void> _pumpAt(WidgetTester tester, Size size, Widget app) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _section(Section section) =>
    find.byKey(ValueKey('section-${section.name}'));

/// A synthetic budget with 4,210.55 in Checking and three Scheduled
/// Transactions due today: Rent 1,000.00 and Internet 60.00 out, a 500.00
/// paycheck in.
final class _Planning {
  _Planning() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(421055),
        asOf: CivilDate(month.year, month.month, 1),
      ),
    );
    checking = engine.state.accounts.single.id;
    bills = _id(
      engine.execute(const CreateCategoryGroup(name: 'Bills')),
      'categoryGroupId',
    );
    housing = _id(
      engine.execute(CreateCategory(groupId: bills, name: 'Housing')),
      'categoryId',
    );
    utilities = _id(
      engine.execute(CreateCategory(groupId: bills, name: 'Utilities')),
      'categoryId',
    );
    rentSchedule = schedule(payee: 'Rent', cents: -100000, category: housing);
    schedule(payee: 'Internet', cents: -6000, category: utilities);
    schedule(payee: 'Paycheck', cents: 50000, category: readyToAssignCategory);
  }

  final log = InMemoryEventLog();
  late final engine = _engine(log);
  final services = AppServices.inMemory();
  final month = thisMonth();
  late final String checking;
  late final String bills;
  late final String housing;
  late final String utilities;
  late final String rentSchedule;

  String schedule({
    required String payee,
    required int cents,
    required String category,
  }) => _id(
    engine.execute(
      CreateSchedule(
        accountId: checking,
        payee: payee,
        amount: Money(cents),
        category: category,
        every: 1,
        interval: TargetInterval.months,
        nextDue: today(),
      ),
    ),
    'scheduleId',
  );

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine(log), services: services);

  BudgetState get state => BudgetState.replay(log.readAll());
}

/// A synthetic business year: a 1,500.00 client payment, a 48.21 lunch, a
/// 40.00 gift to Dana, and one charge still waiting for Review.
final class _Studio {
  _Studio() {
    engine.execute(const CreateBudget(name: 'Studio'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(500000),
        asOf: CivilDate(year, 1, 5),
      ),
    );
    checking = engine.state.accounts.single.id;
    engine.execute(const CreateCategoryGroup(name: 'Everyday'));
    final group = engine.state.categoryGroups.single.id;
    engine.execute(CreateCategory(groupId: group, name: 'Advertising'));
    final advertising = engine.state.categories.single.id;
    engine.execute(
      CreateTransaction(
        accountId: checking,
        date: CivilDate(year, 1, 5),
        amount: const Money(150000),
        payee: 'Client',
        lines: [
          const LineInput(
            amount: Money(150000),
            category: readyToAssignCategory,
            business: Business('Self-employment income'),
          ),
        ],
      ),
    );
    void spend(
      int cents,
      String tag,
      CivilDate date,
      String payee, {
      String? recipient,
    }) => engine.execute(
      CreateTransaction(
        accountId: checking,
        date: date,
        amount: Money(-cents),
        payee: payee,
        lines: [
          LineInput(
            amount: Money(-cents),
            category: advertising,
            business: Business(tag),
            recipient: recipient,
          ),
        ],
      ),
    );
    spend(4821, 'Meals', CivilDate(year, 1, 20), 'Corner Bistro');
    spend(4000, giftsTag, CivilDate(year, 2, 1), 'Florist', recipient: 'Dana');
    engine.execute(
      CreateTransaction(
        accountId: checking,
        date: CivilDate(year, 3, 1),
        amount: const Money(-1200),
        payee: 'Mystery charge',
        lines: [const LineInput(amount: Money(-1200))],
      ),
    );
  }

  final log = InMemoryEventLog();
  late final engine = _engine(log);
  final services = AppServices.inMemory();
  final year = today().year;
  late final String checking;

  Widget app() => BudgetApp(engine: _engine(log), services: services);

  BudgetState get state => BudgetState.replay(log.readAll());
}

/// A synthetic budget whose changes came from three Actors: the person, bank
/// sync and an AI app.
final class _Actors {
  _Actors() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
        asOf: today(),
      ),
    );
    final group = _id(
      engine.execute(const CreateCategoryGroup(name: 'Everyday')),
      'categoryGroupId',
    );
    groceries = _id(
      engine.execute(CreateCategory(groupId: group, name: 'Groceries')),
      'categoryId',
    );
    dining = _id(
      engine.execute(CreateCategory(groupId: group, name: 'Dining out')),
      'categoryId',
    );
    rent = _id(
      engine.execute(CreateCategory(groupId: group, name: 'Rent')),
      'categoryId',
    );
    assign(Actor.userAndroid, groceries, 10000);
    assign(Actor.bankSync, dining, 5000);
    assign(const Actor.fromValue('mcp:Claude Desktop'), rent, 20000);
  }

  final log = InMemoryEventLog();
  late final engine = _engine(log);
  late final String groceries;
  late final String dining;
  late final String rent;

  /// One change by [actor], as its own engine over the one log.
  void assign(Actor actor, String categoryId, int cents) =>
      _engine(log, actor: actor).execute(
        SetAssignment(
          categoryId: categoryId,
          month: thisMonth(),
          amount: Money(cents),
        ),
      );

  Widget app() => BudgetApp(engine: _engine(log));
}

void main() {
  testWidgets('the desktop Forecast shows the balance chart, today, the '
      'lowest point, predicted expenses and Coming up', (tester) async {
    final seed = _Planning();
    await _pumpAt(tester, const Size(1280, 820), seed.app());
    await _tap(tester, _section(Section.forecast));

    expect(find.byKey(const ValueKey('forecast-chart')), findsOneWidget);

    // Today's balance, the low point in the next 30 days, and what the
    // schedules spend in them.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('forecast-today'))).data,
      '\$4,210.55',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('forecast-lowest'))).data,
      '\$3,650.55',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('forecast-expenses'))).data,
      '\$1,060.00',
    );

    // Coming up lists the schedules due, beside the chart.
    final coming = find.byKey(const ValueKey('forecast-coming'));
    for (final payee in ['Rent', 'Internet', 'Paycheck']) {
      expect(
        find.descendant(of: coming, matching: find.text(payee)),
        findsOneWidget,
        reason: payee,
      );
    }

    // A year looks further ahead: a lower low and more predicted expenses.
    await _tap(tester, find.text('1 year'));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('forecast-lowest'))).data,
      '−\$2,509.45',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('forecast-expenses'))).data,
      '\$12,720.00',
    );

    // Back to 30 days.
    await _tap(tester, find.text('30 days'));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('forecast-expenses'))).data,
      '\$1,060.00',
    );
  });

  testWidgets('the desktop Business report shows tag totals, the selected '
      'tag\'s lines, a Review flag and Export CSV', (tester) async {
    final seed = _Studio();
    await _pumpAt(tester, const Size(1280, 820), seed.app());
    await _tap(tester, _section(Section.businessReport));

    final report = seed.state.businessReport(seed.year);
    // The year's totals.
    expect(find.text('\$1,500.00'), findsWidgets);
    expect(find.text('\$49.10'), findsOneWidget);
    expect(find.text('\$1,450.90'), findsOneWidget);

    // A tag per row, and the selected tag's lines beside them.
    for (final row in report.rows) {
      expect(
        find.byKey(ValueKey('business-tag-row-${row.tag.name}')),
        findsOneWidget,
        reason: row.tag.name,
      );
    }
    await _tap(tester, find.byKey(const ValueKey('business-tag-row-Meals')));
    final lines = find.byKey(const ValueKey('business-tag-lines'));
    expect(
      find.descendant(of: lines, matching: find.text('Corner Bistro')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lines, matching: find.text('deductible \$24.10')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lines, matching: find.text('Florist')),
      findsNothing,
    );

    // Another tag swaps the lines.
    await _tap(tester, find.byKey(const ValueKey('business-tag-row-Gifts')));
    expect(
      find.descendant(of: lines, matching: find.text('Florist')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lines, matching: find.text('Corner Bistro')),
      findsNothing,
    );

    // The charge still waiting for Review is flagged.
    expect(find.byKey(const ValueKey('business-review-flag')), findsOneWidget);
    expect(
      find.textContaining('1 Unreviewed line in ${seed.year}'),
      findsOneWidget,
    );

    // Export CSV saves the same file the phone's summary export does.
    await _tap(tester, find.byKey(const ValueKey('business-export')));
    final saved = (seed.services.saver as InMemoryFileSaver).saved;
    expect(
      utf8.decode(saved['business-summary-${seed.year}.csv']!),
      businessSummaryCsv(report),
    );
  });

  testWidgets('desktop Change History groups by day, labels each Actor and '
      'filters by Actor', (tester) async {
    final seed = _Actors();
    await _pumpAt(tester, const Size(1280, 820), seed.app());
    await _tap(tester, _section(Section.history));

    // Every entry is under today's heading, with its Actor's label.
    expect(find.text('TODAY'), findsOneWidget);
    for (final (label, summary) in [
      ('You', 'Assigned \$100.00 to Groceries'),
      ('Bank sync', 'Assigned \$50.00 to Dining out'),
      ('MCP · Claude Desktop', 'Assigned \$200.00 to Rent'),
    ]) {
      expect(find.text(summary), findsOneWidget, reason: summary);
      expect(find.text(label), findsWidgets, reason: label);
    }

    // Filtering by Actor shows only that Actor's entries.
    await _tap(tester, find.byKey(const ValueKey('history-filter-Bank sync')));
    expect(find.text('Assigned \$50.00 to Dining out'), findsOneWidget);
    expect(find.text('Assigned \$100.00 to Groceries'), findsNothing);
    expect(find.text('Assigned \$200.00 to Rent'), findsNothing);

    await _tap(tester, find.byKey(const ValueKey('history-filter-MCP')));
    expect(find.text('Assigned \$200.00 to Rent'), findsOneWidget);
    expect(find.text('Assigned \$50.00 to Dining out'), findsNothing);

    // All brings every Actor's entries back.
    await _tap(tester, find.byKey(const ValueKey('history-filter-All')));
    expect(find.text('Assigned \$100.00 to Groceries'), findsOneWidget);
    expect(find.text('Assigned \$50.00 to Dining out'), findsOneWidget);
    expect(find.text('Assigned \$200.00 to Rent'), findsOneWidget);
  });

  testWidgets('Go back to a date shows a read-only budget with a Back to '
      'today bar', (tester) async {
    final seed = _Actors();
    final count = seed.log.readAll().length;
    final now = DateTime.now();
    final yesterday = CivilDate.fromDateTime(
      DateTime(now.year, now.month, now.day - 1),
    );
    await _pumpAt(tester, const Size(1280, 820), seed.app());
    await _tap(tester, _section(Section.history));

    await _tap(tester, find.text('Go back to a date'));
    await _tap(tester, find.text('OK')); // Yesterday, as the picker opens.

    expect(
      find.text('Viewing ${formatDate(yesterday)} · read-only'),
      findsOneWidget,
    );
    expect(find.text('Back to today'), findsOneWidget);
    // The whole budget, read-only: nothing was written.
    expect(seed.log.readAll(), hasLength(count));

    await _tap(tester, find.text('Back to today'));
    expect(find.text('Change History'), findsOneWidget);
    expect(seed.log.readAll(), hasLength(count));
  });

  testWidgets('desktop Schedules is a table, and a row opens Edit schedule as '
      'a sheet', (tester) async {
    final seed = _Planning();
    await _pumpAt(tester, const Size(1280, 820), seed.app());
    await _tap(tester, _section(Section.forecast));

    // Schedules opens from the Forecast's Coming up card.
    await _tap(tester, find.byKey(const ValueKey('forecast-schedules')));

    final table = find.byKey(const ValueKey('schedules-table'));
    expect(table, findsOneWidget);
    for (final column in [
      'NEXT DATE',
      'PAYEE',
      'REPEAT',
      'ACCOUNT',
      'CATEGORY',
      'AMOUNT',
    ]) {
      expect(
        find.descendant(of: table, matching: find.text(column)),
        findsOneWidget,
        reason: column,
      );
    }
    for (final payee in ['Rent', 'Internet', 'Paycheck']) {
      expect(
        find.descendant(of: table, matching: find.text(payee)),
        findsOneWidget,
        reason: payee,
      );
    }
    // The sidebar stays beside it.
    expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);

    await _tap(
      tester,
      find.byKey(ValueKey('schedule-row-${seed.rentSchedule}')),
    );
    expect(find.byKey(const ValueKey('flow-sheet')), findsOneWidget);
    expect(find.text('Edit schedule'), findsOneWidget);
    // The sheet carries the schedule's payee.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('schedule-payee')))
          .controller!
          .text,
      'Rent',
    );
  });

  testWidgets('every section still lays out in the narrowest Mac window', (
    tester,
  ) async {
    final studio = _Studio();
    // Just above the desktop breakpoint: the sidebar leaves 660 px.
    await _pumpAt(tester, const Size(900, 820), studio.app());
    for (final section in [
      Section.forecast,
      Section.businessReport,
      Section.history,
    ]) {
      await _tap(tester, _section(section));
      expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);
    }

    // With Schedules due, Coming up stacks under the chart.
    final planning = _Planning();
    await _pumpAt(tester, const Size(900, 820), planning.app());
    await _tap(tester, _section(Section.forecast));
    expect(find.byKey(const ValueKey('forecast-coming')), findsOneWidget);
    expect(find.text('Coming up'), findsOneWidget);

    // The Schedules table scrolls inside its card instead of squeezing its
    // columns out of line.
    await _tap(tester, find.byKey(const ValueKey('forecast-schedules')));
    expect(find.byKey(const ValueKey('schedules-table')), findsOneWidget);
    expect(find.text('PAYEE'), findsOneWidget);
  });

  testWidgets('a phone keeps the existing Forecast layout', (tester) async {
    final seed = _Planning();
    // Below the desktop breakpoint, so the phone layouts still apply.
    await _pumpAt(tester, const Size(800, 800), seed.app());

    await _tap(tester, find.byTooltip('Settings'));
    await tester.scrollUntilVisible(find.text('Forecast'), 200);
    await _tap(tester, find.text('Forecast'));

    expect(find.text('STARTING BALANCE'), findsOneWidget);
    expect(find.byKey(const ValueKey('forecast-chart')), findsNothing);
    expect(find.text('1 year'), findsNothing);
  });

  testWidgets('a phone keeps the existing Schedules list', (tester) async {
    final seed = _Planning();
    await _pumpAt(tester, const Size(800, 800), seed.app());

    await _tap(tester, find.byTooltip('Settings'));
    await tester.scrollUntilVisible(find.text('Scheduled transactions'), 200);
    await _tap(tester, find.text('Scheduled transactions'));

    // The phone's list, not the desktop table.
    expect(find.byKey(const ValueKey('schedules-table')), findsNothing);
    expect(find.text('NEXT DATE'), findsNothing);
    expect(find.text('Rent'), findsOneWidget);
  });
}
