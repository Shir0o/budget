import 'package:budget/app.dart';
import 'package:budget/budget_library.dart';
import 'package:budget/screens/account_register_screen.dart';
import 'package:budget/screens/accounts_screen.dart';
import 'package:budget/screens/budget_screen.dart';
import 'package:budget/screens/business_report_screen.dart';
import 'package:budget/screens/forecast_screen.dart';
import 'package:budget/screens/history_screen.dart';
import 'package:budget/screens/review_screen.dart';
import 'package:budget/screens/settings_screen.dart';
import 'package:budget/screens/welcome_screen.dart';
import 'package:budget/services.dart';
import 'package:budget/theme.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: a checking account, a card with a balance owed, a
/// tracking account, and two lines still to Review.
BudgetEngine _home() {
  final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  engine.execute(const CreateBudget(name: 'Home'));
  engine.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: const Money(421055),
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  engine.execute(
    AddAccount(
      name: 'Visa',
      type: AccountType.creditCard,
      startingBalance: const Money(-45000),
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  engine.execute(
    AddAccount(
      name: 'Brokerage',
      type: AccountType.tracking,
      startingBalance: const Money(100000),
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  final checking = engine.state.accounts
      .firstWhere((account) => account.type == AccountType.checking)
      .id;
  for (final payee in ['Paper & Co.', 'Cafe']) {
    engine.execute(
      CreateTransaction(
        accountId: checking,
        date: CivilDate(2026, 11, 2),
        amount: const Money(-1200),
        payee: payee,
        lines: [const LineInput(amount: Money(-1200))],
      ),
    );
  }
  return engine;
}

/// A device with no budget yet, so the app opens on Welcome.
BudgetEngine _empty() => BudgetEngine(
  log: InMemoryEventLog(),
  deviceId: 'test-device',
  actor: Actor.userAndroid,
);

BudgetEngine _engine(EventLog log) =>
    BudgetEngine(log: log, deviceId: 'test-device', actor: Actor.userAndroid);

String _id(CommandResult result, String field) =>
    (result as Accepted).events.single.payload[field] as String;

/// A synthetic Budget month: $500.00 in checking, an Everyday group with
/// Groceries (a $100.00 Target) and Dining out, $80.00 assigned and $50.00
/// spent on Dining out, so it is $30.00 overspent.
final class _MonthSeed {
  _MonthSeed() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
        asOf: CivilDate(month.year, month.month, 1),
      ),
    );
    group = _id(
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
    engine.execute(
      SetTarget(
        categoryId: groceries,
        target: const KeepAtLeastTarget(amount: Money(10000)),
      ),
    );
    assign(groceries, 6000);
    assign(dining, 2000);
    engine.execute(
      CreateTransaction(
        accountId: engine.state.accounts.single.id,
        date: CivilDate(month.year, month.month, 2),
        amount: const Money(-5000),
        payee: 'Corner Bistro',
        lines: [LineInput(amount: const Money(-5000), category: dining)],
      ),
    );
  }

  final log = InMemoryEventLog();
  late final engine = _engine(log);
  final month = thisMonth();
  late final String group;
  late final String groceries;
  late final String dining;

  void assign(String categoryId, int cents) => engine.execute(
    SetAssignment(categoryId: categoryId, month: month, amount: Money(cents)),
  );

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine(log));

  BudgetState get state => BudgetState.replay(log.readAll());
}

Future<void> _pumpAppAt(WidgetTester tester, Size size, Widget app) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// A device with two saved synthetic budgets, the first one open.
Future<(BudgetLibrary, AppServices)> _twoBudgets(WidgetTester tester) async {
  final services = AppServices.inMemory();
  final library = await tester.runAsync(() async {
    final library = await BudgetLibrary.load(
      storage: InMemoryBudgetStorage(),
      prefs: services.prefs,
      deviceId: 'test-device',
      actor: Actor.userAndroid,
    );
    for (final (name, cents) in [
      ('Personal', 41200),
      ('Side business', 9900),
    ]) {
      final draft = library.startNew();
      draft.execute(CreateBudget(name: name));
      draft.execute(
        AddAccount(
          name: 'Checking',
          type: AccountType.checking,
          startingBalance: Money(cents),
          asOf: today(),
        ),
      );
      await library.commit(draft);
    }
    await library.switchTo(library.entries.first.id);
    return library;
  });
  return (library!, services);
}

Future<void> _pumpLibraryAt(
  WidgetTester tester,
  Size size,
  BudgetLibrary library,
  AppServices services,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BudgetApp(library: library, services: services));
  await tester.pumpAndSettle();
}

/// Adds a Reviewed "Green Grocer" line with the memo "Weekly shop" to
/// [_home]'s checking account, so search has something to find.
void _addGroceries(BudgetEngine engine) {
  final group =
      (engine.execute(
            const CreateCategoryGroup(name: 'Everyday'),
          ) as Accepted).events.single.payload['categoryGroupId']
          as String;
  engine.execute(CreateCategory(groupId: group, name: 'Groceries'));
  final checking = _account(engine, 'Checking');
  engine.execute(
    CreateTransaction(
      accountId: checking.id,
      date: today(),
      amount: const Money(-2500),
      payee: 'Green Grocer',
      memo: 'Weekly shop',
      lines: [const LineInput(amount: Money(-2500))],
    ),
  );
  final shop = engine.state.transactions.firstWhere(
    (transaction) => transaction.payee == 'Green Grocer',
  );
  engine.execute(
    ReviewLine(
      transactionId: shop.id,
      lineId: shop.lines.single.id,
      category: engine.state.categories
          .firstWhere((category) => category.name == 'Groceries')
          .id,
      business: const Personal(),
    ),
  );
}

Future<void> _pumpAt(WidgetTester tester, Size size, BudgetEngine engine) =>
    _pumpAppAt(tester, size, BudgetApp(engine: engine));

Finder _sectionRow(Section section) =>
    find.byKey(ValueKey('section-${section.name}'));

/// The sidebar, as opposed to a section's own screen in the content area.
final _sidebar = find.byKey(const ValueKey('sidebar'));

Finder _inSidebar(String text) =>
    find.descendant(of: _sidebar, matching: find.text(text));

/// Whether the sidebar shows [section] as the one on screen.
bool _highlighted(WidgetTester tester, Section section) {
  final label = tester.widget<Text>(
    find.descendant(
      of: _sectionRow(section),
      matching: find.text(section.label),
    ),
  );
  return label.style?.fontWeight == FontWeight.w600;
}

/// The Review badge's count, or null when no badge shows.
String? _reviewBadge(WidgetTester tester) {
  final badge = find.byKey(const ValueKey('Review-badge'));
  if (badge.evaluate().isEmpty) return null;
  return tester
      .widget<Text>(find.descendant(of: badge, matching: find.byType(Text)))
      .data;
}

Account _account(BudgetEngine engine, String name) =>
    engine.state.accounts.firstWhere((account) => account.name == name);

void main() {
  testWidgets('a desktop window shows the toolbar, every section and account', (
    tester,
  ) async {
    final engine = _home();
    await _pumpAt(tester, const Size(1280, 820), engine);

    // The window fills the screen, with the toolbar above the sidebar.
    expect(tester.getSize(find.byType(Scaffold).first), const Size(1280, 820));
    expect(find.text('Home'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'New transaction'),
      findsOneWidget,
    );
    expect(find.byTooltip('Settings'), findsOneWidget);
    // The phone's bottom navigation is the sidebar's job here.
    expect(
      find.descendant(of: find.byType(MainNav), matching: find.byType(Text)),
      findsNothing,
    );

    // The month switcher moves the window's month.
    expect(find.text(formatMonth(thisMonth())), findsOneWidget);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text(formatMonth(thisMonth().next)), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text(formatMonth(thisMonth())), findsOneWidget);

    // Every section, in the one model the phone's navigation reads too.
    for (final section in Section.values) {
      expect(_sectionRow(section), findsOneWidget, reason: section.label);
    }

    // Review's badge is the Unreviewed count.
    expect(engine.state.reviewQueue, hasLength(2));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('Review-badge')),
        matching: find.text('${engine.state.reviewQueue.length}'),
      ),
      findsOneWidget,
    );

    // Budget accounts with their total, and Tracking Accounts apart.
    expect(_inSidebar('Budget accounts'), findsOneWidget);
    expect(_inSidebar('Tracking accounts'), findsOneWidget);
    final total = engine.state.accounts
        .where((account) => account.type.onBudget)
        .fold(Money.zero, (sum, a) => sum + engine.state.balance(a.id));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('budget-accounts-total')))
          .data,
      total.format(),
    );
    for (final name in ['Checking', 'Visa', 'Brokerage']) {
      final account = _account(engine, name);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('account-${account.id}')),
          matching: find.text(engine.state.balance(account.id).format()),
        ),
        findsOneWidget,
        reason: name,
      );
    }

    // Add account and the sync line close the sidebar.
    expect(_inSidebar('Add account'), findsOneWidget);
    expect(find.textContaining('Sync off'), findsOneWidget);
  });

  testWidgets('clicking each section shows it and highlights it', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1280, 820), _home());

    expect(_highlighted(tester, Section.budget), isTrue);
    expect(find.byType(BudgetScreen), findsOneWidget);

    for (final (section, screen) in [
      (Section.review, ReviewScreen),
      (Section.accounts, AccountsScreen),
      (Section.history, HistoryScreen),
      (Section.forecast, ForecastScreen),
      (Section.businessReport, BusinessReportScreen),
      (Section.budget, BudgetScreen),
    ]) {
      await tester.tap(_sectionRow(section));
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: section.label);
      expect(find.byTooltip('Back'), findsNothing, reason: section.label);
      for (final other in Section.values) {
        expect(
          _highlighted(tester, other),
          other == section,
          reason: '${section.label} highlighted, ${other.label} not',
        );
      }
      // The sidebar stays beside the section.
      expect(_inSidebar('Budget accounts'), findsOneWidget);
    }
  });

  testWidgets('the sidebar follows the budget as it changes', (tester) async {
    final engine = _home();
    await _pumpAt(tester, const Size(1280, 820), engine);
    expect(_reviewBadge(tester), '2');

    // A new line waiting for Review updates the badge beside the section.
    final checking = _account(engine, 'Checking');
    engine.execute(
      CreateTransaction(
        accountId: checking.id,
        date: CivilDate(2026, 11, 3),
        amount: const Money(-999),
        payee: 'Bookshop',
        lines: [const LineInput(amount: Money(-999))],
      ),
    );
    // A tap that writes an Event always redraws; the sidebar follows the
    // frame after it.
    tester.binding.scheduleFrame();
    await tester.pumpAndSettle();

    expect(engine.state.reviewQueue, hasLength(3));
    expect(_reviewBadge(tester), '3');
  });

  testWidgets('an account in the sidebar opens its register', (tester) async {
    final engine = _home();
    await _pumpAt(tester, const Size(1280, 820), engine);

    final checking = _account(engine, 'Checking');
    await tester.tap(find.byKey(ValueKey('account-${checking.id}')));
    await tester.pumpAndSettle();

    expect(find.byType(AccountRegisterScreen), findsOneWidget);
    // The sidebar stays beside the register.
    expect(_sidebar, findsOneWidget);
    expect(find.text('Visa'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountRegisterScreen), findsNothing);
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
  });

  testWidgets('a card with a negative balance is in the problem color', (
    tester,
  ) async {
    final engine = _home();
    await _pumpAt(tester, const Size(1280, 820), engine);

    final card = _account(engine, 'Visa');
    expect(engine.state.balance(card.id).isNegative, isTrue);
    final balance = tester.widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('account-${card.id}')),
        matching: find.text(engine.state.balance(card.id).format()),
      ),
    );
    expect(balance.style?.color, Palette.problemText);
  });

  testWidgets('Welcome fills the window with no sidebar', (tester) async {
    await _pumpAt(tester, const Size(1280, 820), _empty());

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(_sidebar, findsNothing);
    expect(_sectionRow(Section.budget), findsNothing);
  });

  testWidgets('the first account opens the window on the new budget', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1280, 820), _empty());

    await tester.enterText(find.byKey(const ValueKey('budget-name')), 'Home');
    await tester.tap(find.text('Add your first account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-balance')),
      '4,210.55',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The window is there, on the budget just made.
    expect(_sidebar, findsOneWidget);
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
    expect(_inSidebar('Checking'), findsOneWidget);
  });

  testWidgets('the budget name opens a popover that switches budgets', (
    tester,
  ) async {
    final (library, services) = await _twoBudgets(tester);
    await _pumpLibraryAt(tester, const Size(1280, 820), library, services);
    final (personal, side) = (library.entries.first, library.entries.last);

    // The toolbar shows the open budget's name.
    expect(find.text('Personal'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('budget-accounts-total')))
          .data,
      const Money(41200).format(),
    );

    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();

    // Every budget, with the open one checked, then the two actions.
    expect(find.text('Side business'), findsOneWidget);
    expect(find.byKey(ValueKey('budget-check-${personal.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('budget-check-${side.id}')), findsNothing);
    expect(find.text('New budget…'), findsOneWidget);
    expect(find.text('Manage budgets…'), findsOneWidget);

    await tester.tap(find.text('Side business'));
    await tester.pumpAndSettle();

    // The window is on the other budget, and the popover is closed.
    expect(find.text('New budget…'), findsNothing);
    expect(library.current.state.budget?.name, 'Side business');
    expect(find.text('Side business'), findsOneWidget);
    expect(find.text('Personal'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('budget-accounts-total')))
          .data,
      const Money(9900).format(),
    );
    expect(find.byType(BudgetScreen), findsOneWidget);
  });

  testWidgets('the popover opens New budget and Manage budgets', (
    tester,
  ) async {
    final (library, services) = await _twoBudgets(tester);
    await _pumpLibraryAt(tester, const Size(1280, 820), library, services);

    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New budget…'));
    await tester.pumpAndSettle();

    // A new budget goes through Welcome and leaves the others alone.
    expect(find.text('Give every dollar a job'), findsOneWidget);
    expect(library.entries, hasLength(2));
  });

  testWidgets('Manage budgets opens Settings', (tester) async {
    final (library, services) = await _twoBudgets(tester);
    await _pumpLibraryAt(tester, const Size(1280, 820), library, services);

    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage budgets…'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the toolbar search finds a transaction by payee or memo', (
    tester,
  ) async {
    final engine = _home();
    _addGroceries(engine);
    await _pumpAt(tester, const Size(1280, 820), engine);

    Future<void> search(String text) async {
      await tester.enterText(
        find.byKey(const ValueKey('toolbar-search')),
        text,
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-search')));
      await tester.pumpAndSettle();
    }

    // A memo finds its transaction, and only that one.
    await search('weekly');
    expect(find.text('Green Grocer'), findsOneWidget);
    expect(find.text('Paper & Co.'), findsNothing);
    expect(find.text('Cafe'), findsNothing);

    final shop = engine.state.transactions.firstWhere(
      (transaction) => transaction.payee == 'Green Grocer',
    );
    await tester.tap(find.byKey(ValueKey('search-${shop.id}')));
    await tester.pumpAndSettle();

    // A Reviewed line opens in its register.
    expect(find.byType(AccountRegisterScreen), findsOneWidget);
    expect(find.text('Green Grocer'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // A payee finds it too, and a line still to Review opens Review.
    await search('paper');
    expect(find.text('Paper & Co.'), findsOneWidget);
    expect(find.text('Cafe'), findsNothing);

    final paper = engine.state.transactions.firstWhere(
      (transaction) => transaction.payee == 'Paper & Co.',
    );
    await tester.tap(find.byKey(ValueKey('search-${paper.id}')));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.text('Paper & Co.'), findsOneWidget);
  });

  testWidgets('a phone window is unchanged', (tester) async {
    await _pumpAt(tester, const Size(390, 844), _home());

    expect(tester.getSize(find.byType(Scaffold).first).width, 390);
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
    // The bottom navigation, and no sidebar.
    expect(find.byType(MainNav), findsOneWidget);
    expect(_sidebar, findsNothing);
    expect(find.text('Forecast'), findsNothing);
  });

  testWidgets('the desktop Budget month shows the table, group totals and '
      'status', (tester) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(1280, 820), seed.app());

    // Ready to Assign, with what this month's Overspending takes from next
    // month.
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
    expect(find.text('\$420.00'), findsOneWidget);
    expect(
      find.text(
        '\$30.00 of Overspending comes out of '
        '${monthName(seed.month.next)}’s Ready to Assign',
      ),
      findsOneWidget,
    );

    // Assigned, Activity and Available above the Categories.
    for (final label in ['CATEGORY', 'ASSIGNED', 'ACTIVITY', 'AVAILABLE']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // The group's totals are the sum of its Categories.
    final group = find.byKey(ValueKey('group-${seed.group}'));
    for (final total in ['80.00', '−50.00', '30.00']) {
      expect(
        find.descendant(of: group, matching: find.text(total)),
        findsOneWidget,
        reason: total,
      );
    }

    // Each row's pill is the engine's Available.
    for (final id in [seed.groceries, seed.dining]) {
      final pill = find.descendant(
        of: find.byKey(ValueKey('category-$id')),
        matching: find.byType(AvailablePill),
      );
      expect(
        tester.widget<AvailablePill>(pill).amount,
        seed.state.available(id, seed.month),
        reason: id,
      );
    }

    // One status line per Category.
    expect(
      tester.widget<Text>(find.byKey(ValueKey('status-${seed.dining}'))).data,
      'Overspent · \$30.00 comes out of ${monthName(seed.month.next)}’s '
      'Ready to Assign',
    );
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('status-${seed.groceries}')))
          .data,
      'Target · 40.00 more needed in ${monthName(seed.month)}',
    );
  });

  testWidgets('selecting a Category shows its panel beside the table', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(1280, 820), seed.app());
    expect(find.byKey(const ValueKey('category-panel')), findsNothing);

    await tester.tap(find.byKey(ValueKey('category-${seed.groceries}')));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('category-panel'));
    final table = find.byKey(const ValueKey('budget-table'));
    expect(panel, findsOneWidget);
    // The month stays visible beside the panel.
    expect(table, findsOneWidget);
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
    expect(
      tester.getTopLeft(panel).dx,
      greaterThan(tester.getTopLeft(table).dx),
    );

    // Its Available, Target progress with Edit, and recent activity.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('panel-available'))).data,
      '\$60.00',
    );
    expect(
      find.descendant(of: panel, matching: find.text('Edit')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text('Keep at least · \$100.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Recent activity')),
      findsOneWidget,
    );

    // Choosing another Category swaps the panel in place.
    await tester.tap(find.byKey(ValueKey('category-${seed.dining}')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('panel-available'))).data,
      '−\$30.00',
    );
    expect(
      find.descendant(of: panel, matching: find.text('Corner Bistro')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close panel'));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });

  testWidgets('changing Automation Mode in the panel records an Event', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(1280, 820), seed.app());
    await tester.tap(find.byKey(ValueKey('category-${seed.groceries}')));
    await tester.pumpAndSettle();

    expect(seed.state.automationMode(seed.groceries), AutomationMode.suggest);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();

    // The Event is the state change (ADR 0001), and the panel shows the mode.
    expect(seed.state.automationMode(seed.groceries), AutomationMode.auto);
    final events = [
      for (final event in seed.log.readAll())
        if (event.type == EventType.automationModeSet) event,
    ];
    expect(events, hasLength(1));
    expect(events.single.payload['categoryId'], seed.groceries);
    expect(events.single.payload['mode'], 'auto');
    expect(
      find.text(
        'Assigns to its Target on each run. Saved to Change History as '
        'automation.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a narrow window wraps the panel below the table', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(900, 820), seed.app());
    await tester.tap(find.byKey(ValueKey('category-${seed.dining}')));
    await tester.pumpAndSettle();

    final table = find.byKey(const ValueKey('budget-table'));
    final panel = find.byKey(const ValueKey('category-panel'));
    expect(panel, findsOneWidget);
    expect(
      tester.getTopLeft(panel).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(table).dy),
    );
  });

  testWidgets('the phone Budget month keeps its list', (tester) async {
    final seed = _MonthSeed();
    await _pumpAt(tester, const Size(800, 900), seed.engine);

    // No wide table, no side panel, and the same column labels as before.
    expect(find.byKey(const ValueKey('budget-table')), findsNothing);
    expect(find.byKey(const ValueKey('category-panel')), findsNothing);
    expect(find.text('ACTIVITY'), findsNothing);
    expect(find.text('AVAILABLE'), findsOneWidget);

    // A Category still opens its own screen.
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to budget'), findsOneWidget);
  });

  testWidgets('New transaction opens as a sheet and updates Available', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(1280, 820), seed.app());
    final sheet = find.byKey(const ValueKey('flow-sheet'));

    await tester.tap(find.widgetWithText(FilledButton, 'New transaction'));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '25.00',
    );
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('pick-${seed.groceries}')));
    await tester.pumpAndSettle();

    // The sheet shows the Category's Available, and Split and Repeat.
    expect(find.text('60.00 available'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(sheet, findsNothing);
    expect(seed.state.available(seed.groceries, seed.month), const Money(3500));
    expect(
      tester
          .widget<AvailablePill>(
            find.descendant(
              of: find.byKey(ValueKey('category-${seed.groceries}')),
              matching: find.byType(AvailablePill),
            ),
          )
          .amount,
      const Money(3500),
    );
  });

  testWidgets('Esc closes a sheet without saving anything', (tester) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(1280, 820), seed.app());
    final sheet = find.byKey(const ValueKey('flow-sheet'));
    final transactions = seed.state.transactions.length;

    await tester.tap(find.widgetWithText(FilledButton, 'New transaction'));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '25.00',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(sheet, findsNothing);
    expect(seed.state.transactions, hasLength(transactions));
    expect(seed.state.readyToAssign(seed.month), const Money(42000));
    expect(find.text('\$420.00'), findsOneWidget);
  });

  testWidgets('Assign is a sheet with Ready to Assign before and after', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(1280, 820), seed.app());
    final sheet = find.byKey(const ValueKey('flow-sheet'));

    await tester.tap(find.widgetWithText(FilledButton, 'Assign'));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);

    String amount(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    // Ready to Assign before, and after the whole batch.
    expect(amount('assign-before'), '\$420.00');
    expect(amount('assign-after'), '\$380.00');

    // Unticking the line gives its money back.
    await tester.tap(find.byKey(ValueKey('assign-${seed.groceries}')));
    await tester.pumpAndSettle();
    expect(amount('assign-after'), '\$420.00');

    await tester.tap(find.byKey(ValueKey('assign-${seed.groceries}')));
    await tester.pumpAndSettle();
    expect(amount('assign-after'), '\$380.00');

    await tester.tap(find.textContaining('Accept 1 line'));
    await tester.pumpAndSettle();

    expect(sheet, findsNothing);
    expect(seed.state.readyToAssign(seed.month), const Money(38000));
    expect(find.text('\$380.00'), findsOneWidget);
  });

  testWidgets('Esc on Assign writes nothing, even with a Category on Auto', (
    tester,
  ) async {
    final seed = _MonthSeed();
    final engine = _engine(seed.log);
    await _pumpAppAt(tester, const Size(1280, 820), BudgetApp(engine: engine));
    // Auto is switched on after the first-open run, so a run is still due.
    engine.execute(
      SetAutomationMode(categoryId: seed.groceries, mode: AutomationMode.auto),
    );
    final events = seed.log.readAll().length;
    final ready = seed.state.readyToAssign(seed.month);

    await tester.tap(find.widgetWithText(FilledButton, 'Assign'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flow-sheet')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flow-sheet')), findsNothing);
    expect(seed.log.readAll(), hasLength(events));
    expect(seed.state.readyToAssign(seed.month), ready);
  });

  testWidgets('Assign shows the month the window is on', (tester) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(1280, 820), seed.app());

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Assign'));
    await tester.pumpAndSettle();

    final next = seed.month.next;
    expect(find.text('Assign · ${monthName(next)}'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('assign-before'))).data,
      seed.state.readyToAssign(next).formatDollars(),
    );
  });

  testWidgets('Move money opens as a sheet and updates both Categories', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(1280, 820), seed.app());

    await tester.tap(find.byKey(ValueKey('category-${seed.groceries}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move money'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flow-sheet')), findsOneWidget);

    await tester.tap(find.text('Choose a Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('pick-${seed.dining}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('move-amount')), '20.00');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move \$20.00'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flow-sheet')), findsNothing);
    for (final (id, cents) in [(seed.groceries, 4000), (seed.dining, -1000)]) {
      expect(
        tester
            .widget<AvailablePill>(
              find.descendant(
                of: find.byKey(ValueKey('category-$id')),
                matching: find.byType(AvailablePill),
              ),
            )
            .amount,
        Money(cents),
        reason: id,
      );
    }
  });

  testWidgets('Add account is a sheet that asks only for the last 4 digits', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAppAt(tester, const Size(1280, 820), seed.app());

    await tester.tap(_inSidebar('Add account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flow-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-last4')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('account-name')),
      'Savings',
    );
    await tester.enterText(find.byKey(const ValueKey('account-last4')), '4321');
    await tester.enterText(
      find.byKey(const ValueKey('account-balance')),
      '100.00',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flow-sheet')), findsNothing);
    expect(_inSidebar('Savings ••4321'), findsOneWidget);
    expect(
      seed.state.accounts.any((account) => account.name == 'Savings ••4321'),
      isTrue,
    );
  });

  testWidgets('a phone still opens a flow as a full-screen route', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAt(tester, const Size(390, 844), seed.engine);

    final button = find.widgetWithText(OutlinedButton, 'New transaction');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flow-sheet')), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byKey(const ValueKey('transaction-amount')), findsOneWidget);
  });

  testWidgets(
    'a phone tab, then a wider window, is the window on that '
    'section',
    (tester) async {
      await _pumpAt(tester, const Size(390, 844), _home());
      await tester.tap(
        find.descendant(
          of: find.byType(MainNav),
          matching: find.text('Review'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);

      tester.view.physicalSize = const Size(1280, 820);
      await tester.pumpAndSettle();

      expect(_sidebar, findsOneWidget);
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(_highlighted(tester, Section.review), isTrue);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
  );
}
