import 'dart:io';

import 'package:budget/app.dart';
import 'package:budget/screens/accounts_screen.dart';
import 'package:budget/screens/budget_screen.dart';
import 'package:budget/screens/history_screen.dart';
import 'package:budget/screens/review_screen.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone canvases the app is audited at: the 390 x 844 the screens were
/// drawn at, and a small 320 x 568 phone at 1.6x text.
const _phone = Size(390, 844);
const _smallPhone = Size(320, 568);

/// A synthetic budget with something to see in every primary view: an
/// on-budget checking account, a card and a tracking account, a Target, and
/// two lines still to Review.
BudgetEngine _seed() {
  final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'test-device',
    actor: Actor.userAndroid,
    // A fixed clock keeps History's day grouping and times out of the
    // goldens (and out of today's date).
    nowMs: () => DateTime(2026, 11, 1, 9, 30).millisecondsSinceEpoch,
  );
  final month = thisMonth();
  final asOf = CivilDate(month.year, month.month, 1);
  engine.execute(const CreateBudget(name: 'Home'));
  engine.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: const Money(421055),
      asOf: asOf,
    ),
  );
  engine.execute(
    AddAccount(
      name: 'Visa',
      type: AccountType.creditCard,
      startingBalance: const Money(-45000),
      asOf: asOf,
    ),
  );
  engine.execute(
    AddAccount(
      name: 'Brokerage',
      type: AccountType.tracking,
      startingBalance: const Money(100000),
      asOf: asOf,
    ),
  );

  final group =
      (engine.execute(
            const CreateCategoryGroup(name: 'Everyday'),
          ) as Accepted).events.single.payload['categoryGroupId']
          as String;
  final groceries =
      (engine.execute(
            CreateCategory(groupId: group, name: 'Groceries'),
          ) as Accepted).events.single.payload['categoryId']
          as String;
  final dining =
      (engine.execute(
            CreateCategory(groupId: group, name: 'Dining out'),
          ) as Accepted).events.single.payload['categoryId']
          as String;
  engine.execute(
    SetTarget(
      categoryId: groceries,
      target: const KeepAtLeastTarget(amount: Money(10000)),
    ),
  );
  engine.execute(
    SetAssignment(categoryId: groceries, month: month, amount: Money(6000)),
  );
  engine.execute(
    SetAssignment(categoryId: dining, month: month, amount: Money(2000)),
  );

  final checking = engine.state.accounts
      .firstWhere((account) => account.type == AccountType.checking)
      .id;
  engine.execute(
    CreateTransaction(
      accountId: checking,
      date: CivilDate(month.year, month.month, 2),
      amount: const Money(-1200),
      payee: 'Paper & Co.',
      lines: [const LineInput(amount: Money(-1200))],
    ),
  );
  engine.execute(
    CreateTransaction(
      accountId: checking,
      date: CivilDate(month.year, month.month, 3),
      amount: const Money(-850),
      payee: 'Cafe',
      lines: [const LineInput(amount: Money(-850))],
    ),
  );
  return engine;
}

/// Pumps the app at [size], with the platform in [brightness] and text at
/// [textScale].
///
/// The app currently ships one light theme (`BudgetApp` passes only `theme:`),
/// so the dark pass renders the same light UI under a dark platform. Its
/// goldens are still a baseline: they change the moment a dark theme lands.
Future<void> _pump(
  WidgetTester tester,
  BudgetEngine engine, {
  Size size = _phone,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(BudgetApp(engine: engine));
  await tester.pumpAndSettle();
}

/// Taps a tab in the phone's bottom navigation.
Future<void> _open(WidgetTester tester, Section section) async {
  await tester.tap(
    find.descendant(
      of: find.byType(MainNav),
      matching: find.text(section.label),
    ),
  );
  await tester.pumpAndSettle();
}

/// Fails the test on a RenderFlex (or other layout) exception, naming the
/// view it happened in.
void _expectNoOverflow(WidgetTester tester, String view) {
  final error = tester.takeException();
  expect(error, isNull, reason: 'Layout error on $view: $error');
}

/// Goldens are compared on the platform that generated them. Font
/// rasterisation differs on Linux/Windows, so CI still runs every view and
/// the overflow checks, and only macOS compares the images.
bool get _comparesGoldens => Platform.isMacOS;

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_comparesGoldens) return;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

/// A primary-view pass: the four tabs every phone has, in order.
Future<void> _capturePrimaryViews(
  WidgetTester tester,
  String prefix, {
  required String home,
}) async {
  _expectNoOverflow(tester, '$prefix: Budget');
  expect(find.byType(BudgetScreen), findsOneWidget);
  expect(find.text('READY TO ASSIGN'), findsOneWidget);
  await _capture(tester, home);

  await _open(tester, Section.review);
  _expectNoOverflow(tester, '$prefix: Review');
  expect(find.byType(ReviewScreen), findsOneWidget);
  await _capture(tester, '${prefix}_review');

  await _open(tester, Section.accounts);
  _expectNoOverflow(tester, '$prefix: Accounts');
  expect(find.byType(AccountsScreen), findsOneWidget);
  expect(find.text('Budget accounts'), findsOneWidget);
  await _capture(tester, '${prefix}_accounts');

  await _open(tester, Section.history);
  _expectNoOverflow(tester, '$prefix: History');
  expect(find.byType(HistoryScreen), findsOneWidget);
  expect(find.text('Change History'), findsOneWidget);
  await _capture(tester, '${prefix}_history');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Without this the goldens would be Ahem boxes. The app bundles IBM Plex;
    // loading it here makes the captured screens the ones people see.
    Future<void> load(String family, List<String> assets) async {
      final loader = FontLoader(family);
      for (final asset in assets) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }

    await load('IBMPlexSans', const [
      'assets/fonts/IBMPlexSans-Regular.ttf',
      'assets/fonts/IBMPlexSans-Medium.ttf',
      'assets/fonts/IBMPlexSans-SemiBold.ttf',
      'assets/fonts/IBMPlexSans-Bold.ttf',
    ]);
    await load('IBMPlexMono', const [
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-SemiBold.ttf',
    ]);
    // `uses-material-design` bundles the icon font; without it icons capture
    // as empty boxes. Only the golden run needs it.
    if (_comparesGoldens) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });

  testWidgets('light mode, 390 x 844', (tester) async {
    await _pump(tester, _seed());
    await _capturePrimaryViews(tester, 'light', home: 'light_home');
    _expectNoOverflow(tester, 'light: final frame');
  });

  testWidgets('dark mode, 390 x 844', (tester) async {
    await _pump(tester, _seed(), brightness: Brightness.dark);
    await _capturePrimaryViews(tester, 'dark', home: 'dark_home');
    _expectNoOverflow(tester, 'dark: final frame');
  });

  testWidgets('small phone, 320 x 568, 1.6x text', (tester) async {
    await _pump(tester, _seed(), size: _smallPhone, textScale: 1.6);
    await _capturePrimaryViews(tester, 'small_scale', home: 'small_scale_home');
    _expectNoOverflow(tester, 'small_scale: final frame');
  });
}
