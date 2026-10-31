import 'package:budget/app.dart';
import 'package:budget/screens/accounts_screen.dart';
import 'package:budget/screens/budget_screen.dart';
import 'package:budget/screens/forecast_screen.dart';
import 'package:budget/screens/history_screen.dart';
import 'package:budget/screens/review_screen.dart';
import 'package:budget/screens/settings_screen.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  final month = thisMonth();
  late final String group;
  late final String groceries;
  late final String dining;

  void assign(String categoryId, int cents) => engine.execute(
    SetAssignment(categoryId: categoryId, month: month, amount: Money(cents)),
  );

  Widget app() => BudgetApp(engine: engine);

  BudgetState get state => engine.state;
}

String _id(CommandResult result, String field) =>
    (result as Accepted).events.single.payload[field] as String;

Future<void> _pumpAt(WidgetTester tester, Size size, Widget app) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// A Mac key with Cmd held, as on the platform.
Future<void> _cmd(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

/// The menu bar's menus, in order.
List<PlatformMenu> _menus(WidgetTester tester) => [
  for (final menu
      in tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus)
    menu as PlatformMenu,
];

/// One menu's items, groups flattened. The platform's own items carry no
/// label, so they are left out of the labelled lists below.
List<PlatformMenuItem> _items(PlatformMenu menu) => [
  for (final item in menu.menus)
    if (item case final PlatformMenuItemGroup group) ...group.members else item,
];

PlatformMenu _menu(WidgetTester tester, String label) =>
    _menus(tester).firstWhere((menu) => menu.label == label);

/// One menu's item, by the words it shows.
PlatformMenuItem _item(PlatformMenu menu, String label) =>
    _items(menu).firstWhere((item) => item.label == label);

List<String> _labels(PlatformMenu menu) => [
  for (final item in _items(menu))
    if (item.label.isNotEmpty) item.label,
];

/// The key [item] is bound to, when it has a shortcut.
LogicalKeyboardKey? _shortcut(PlatformMenuItem item) =>
    (item.shortcut as SingleActivator?)?.trigger;

void main() {
  testWidgets('a Mac window carries the seven menus with their shortcuts', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1280, 820), _MonthSeed().app());

    expect(
      [for (final menu in _menus(tester)) menu.label],
      ['Budget', 'File', 'Edit', 'View', 'Transaction', 'Window', 'Help'],
    );

    // Every menu the app fills has something in it. Window and Help hold only
    // the platform's own items, which carry no words of the app's.
    for (final label in ['Budget', 'File', 'Edit', 'View', 'Transaction']) {
      expect(_labels(_menu(tester, label)), isNotEmpty, reason: label);
    }

    // The keys the ticket names, on the items that run them.
    final expected = {
      'Edit': {
        'Undo': LogicalKeyboardKey.keyZ,
        'Search Transactions': LogicalKeyboardKey.keyF,
      },
      'Transaction': {'New transaction…': LogicalKeyboardKey.keyN},
      'Budget': {'Settings…': LogicalKeyboardKey.comma},
      'View': {
        'Budget': LogicalKeyboardKey.digit1,
        'Review': LogicalKeyboardKey.digit2,
        'Accounts': LogicalKeyboardKey.digit3,
        'History': LogicalKeyboardKey.digit4,
        'Forecast': LogicalKeyboardKey.digit5,
        'Previous month': LogicalKeyboardKey.bracketLeft,
        'Next month': LogicalKeyboardKey.bracketRight,
      },
    };
    for (final MapEntry(key: label, value: keys) in expected.entries) {
      final items = {
        for (final item in _items(_menu(tester, label)))
          if (item.label.isNotEmpty) item.label: item,
      };
      for (final MapEntry(key: item, value: key) in keys.entries) {
        expect(items, contains(item), reason: '$label → $item');
        expect(_shortcut(items[item]!), key, reason: '$label → $item');
      }
    }

    // Go to Review and Business report are in View, the one without a digit.
    expect(_labels(_menu(tester, 'View')), contains('Business report'));
    expect(_labels(_menu(tester, 'Transaction')), contains('Go to Review'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a menu item runs the button it names', (tester) async {
    final seed = _MonthSeed();
    await _pumpAt(tester, const Size(1280, 820), seed.app());

    Future<void> choose(String menu, String item) async {
      _item(_menu(tester, menu), item).onSelected!();
      await tester.pumpAndSettle();
    }

    // File → New account… is the sidebar's Add account.
    await choose('File', 'New account…');
    expect(find.byKey(const ValueKey('account-last4')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-last4')), findsNothing);

    // Transaction → New transaction… is the toolbar's button.
    await choose('Transaction', 'New transaction…');
    expect(find.byKey(const ValueKey('transaction-amount')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transaction-amount')), findsNothing);

    // Edit → Search Transactions puts the cursor in the toolbar's field.
    await choose('Edit', 'Search Transactions');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('toolbar-search')))
          .focusNode!
          .hasFocus,
      isTrue,
    );

    // View → a section is the sidebar; View → Next month is the switcher.
    await choose('View', 'History');
    expect(find.byType(HistoryScreen), findsOneWidget);
    await choose('View', 'Budget');
    expect(find.byType(BudgetScreen), findsOneWidget);
    await choose('View', 'Next month');
    expect(find.text(formatMonth(thisMonth().next)), findsOneWidget);
    await choose('View', 'Previous month');
    expect(find.text(formatMonth(thisMonth())), findsOneWidget);

    // Budget → Settings… is the toolbar's Settings button.
    await choose('Budget', 'Settings…');
    expect(find.byType(SettingsScreen), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Cmd+1 to Cmd+5 switch sections', (tester) async {
    await _pumpAt(tester, const Size(1280, 820), _MonthSeed().app());
    expect(find.byType(BudgetScreen), findsOneWidget);

    final digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ];
    final screens = [
      BudgetScreen,
      ReviewScreen,
      AccountsScreen,
      HistoryScreen,
      ForecastScreen,
    ];
    // Every section, and back to Budget, exactly as the sidebar does.
    for (final (digit, screen) in [
      for (var i = 0; i < digits.length; i++) (digits[i], screens[i]),
      (LogicalKeyboardKey.digit1, BudgetScreen),
    ]) {
      await _cmd(tester, digit);
      expect(find.byType(screen), findsOneWidget, reason: '$digit');
      expect(find.byTooltip('Back'), findsNothing, reason: '$digit');
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Cmd+[ and Cmd+] change the month', (tester) async {
    await _pumpAt(tester, const Size(1280, 820), _MonthSeed().app());
    expect(find.text(formatMonth(thisMonth())), findsOneWidget);

    await _cmd(tester, LogicalKeyboardKey.bracketRight);
    expect(find.text(formatMonth(thisMonth().next)), findsOneWidget);

    await _cmd(tester, LogicalKeyboardKey.bracketLeft);
    await _cmd(tester, LogicalKeyboardKey.bracketLeft);
    expect(find.text(formatMonth(thisMonth().previous)), findsOneWidget);

    await _cmd(tester, LogicalKeyboardKey.bracketRight);
    expect(find.text(formatMonth(thisMonth())), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Cmd+N opens New transaction and Cmd+, opens Settings', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAt(tester, const Size(1280, 820), seed.app());
    final sheet = find.byKey(const ValueKey('flow-sheet'));

    await _cmd(tester, LogicalKeyboardKey.keyN);
    expect(sheet, findsOneWidget);
    expect(find.byKey(const ValueKey('transaction-amount')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    await _cmd(tester, LogicalKeyboardKey.comma);
    expect(find.byType(SettingsScreen), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Cmd+F focuses the toolbar search', (tester) async {
    await _pumpAt(tester, const Size(1280, 820), _MonthSeed().app());
    final field = find.byKey(const ValueKey('toolbar-search'));
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);

    await _cmd(tester, LogicalKeyboardKey.keyF);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    // What is typed next goes into the search field.
    await tester.enterText(field, 'Corner');
    expect(tester.widget<TextField>(field).controller!.text, 'Corner');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Cmd+Z reverts the latest change through Change History', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAt(tester, const Size(1280, 820), seed.app());
    expect(
      tester
          .widget<AvailablePill>(
            find.descendant(
              of: find.byKey(ValueKey('category-${seed.groceries}')),
              matching: find.byType(AvailablePill),
            ),
          )
          .amount,
      const Money(6000),
    );

    // A change made by hand: $20.00 moved from Groceries to Dining out.
    await tester.tap(find.byKey(ValueKey('category-${seed.groceries}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move money'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('pick-${seed.dining}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('move-amount')), '20.00');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move \$20.00'));
    await tester.pumpAndSettle();
    expect(seed.state.available(seed.groceries, seed.month), const Money(4000));

    await _cmd(tester, LogicalKeyboardKey.keyZ);

    // The numbers are back, and the undo is itself an Event in the log.
    expect(seed.state.available(seed.groceries, seed.month), const Money(6000));
    expect(seed.state.available(seed.dining, seed.month), const Money(-3000));
    expect(
      tester
          .widget<AvailablePill>(
            find.descendant(
              of: find.byKey(ValueKey('category-${seed.groceries}')),
              matching: find.byType(AvailablePill),
            ),
          )
          .amount,
      const Money(6000),
    );
    final undo = seed.engine.history.entries().first;
    expect(undo.isRevert, isTrue);
    expect(
      seed.log.readAll().where(
        (event) => event.type == EventType.groupReverted,
      ),
      hasLength(1),
    );

    // Change History lists it, and the change it undid is marked Reverted.
    await _cmd(tester, LogicalKeyboardKey.digit4);
    expect(find.textContaining('Undid'), findsOneWidget);
    expect(find.text('Reverted'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a phone window gets no menu bar and no shortcuts', (
    tester,
  ) async {
    final seed = _MonthSeed();
    await _pumpAt(tester, const Size(390, 844), seed.app());
    final transactions = seed.state.transactions.length;

    expect(find.byType(PlatformMenuBar), findsNothing);
    expect(find.byKey(const ValueKey('sidebar')), findsNothing);

    // Every key the window answers does nothing here.
    for (final key in [
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.comma,
      LogicalKeyboardKey.keyZ,
      LogicalKeyboardKey.bracketRight,
    ]) {
      await _cmd(tester, key);
    }

    expect(find.byType(BudgetScreen), findsOneWidget);
    expect(find.byType(ReviewScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byKey(const ValueKey('flow-sheet')), findsNothing);
    expect(seed.state.transactions, hasLength(transactions));
    expect(
      seed.engine.history.entries().where((entry) => entry.isRevert),
      isEmpty,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
