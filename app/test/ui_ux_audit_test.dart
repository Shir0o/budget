import 'package:budget/app.dart';
import 'package:budget/screens/accounts_screen.dart';
import 'package:budget/screens/budget_screen.dart';
import 'package:budget/screens/category_screen.dart';
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
Future<SemanticsHandle> _pump(
  WidgetTester tester,
  BudgetEngine engine, {
  Size size = _phone,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  _recordLayoutErrors();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  // Both guidelines walk the semantics tree, so it has to be on. The caller
  // disposes the handle: the framework checks at the end of the test body, so
  // a tear-down would be too late.
  final semantics = tester.ensureSemantics();

  await tester.pumpWidget(BudgetApp(engine: engine));
  await tester.pumpAndSettle();
  return semantics;
}

/// Fails the pass if the screen on camera breaks a tap target or a contrast
/// rule, naming the screen the pass was on.
///
/// Both guidelines are evaluated and their reasons combined, so one run
/// reports every problem on a screen instead of only the first.
Future<void> _expectGuidelines(WidgetTester tester, String view) async {
  final failures = <String>[];
  for (final guideline in <AccessibilityGuideline>[
    androidTapTargetGuideline,
    textContrastGuideline,
  ]) {
    final result = await guideline.evaluate(tester);
    if (result.passed) continue;
    failures.add('${guideline.description}:\n${result.reason}');
  }
  expect(
    failures,
    isEmpty,
    reason: 'Accessibility on $view:\n\n${failures.join('\n\n')}',
  );
}

/// Opens a Category from the Budget month, opens the Archive dialog (its
/// Available is not 0.00, so the app explains why it cannot archive), and
/// returns to the month.
Future<void> _openCategoryAndDialog(
  WidgetTester tester,
  String view, {
  required String capture,
}) async {
  final groceries = find.descendant(
    of: find.byType(BudgetScreen),
    matching: find.text('Groceries'),
  );
  // On the small phone the Groups start below the fold.
  await tester.scrollUntilVisible(
    groceries,
    120,
    scrollable: find
        .descendant(
          of: find.byType(BudgetScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  // Scrolling stops with the row merely built; put it fully in the viewport so
  // the tap cannot land under the bottom navigation.
  await tester.ensureVisible(groceries);
  await tester.pumpAndSettle();
  await tester.tap(groceries);
  await tester.pumpAndSettle();
  expect(find.byType(CategoryScreen), findsOneWidget);
  _expectNoOverflow(tester, '$view: Groceries');
  await _expectGuidelines(tester, '$view: Groceries');
  await _capture(tester, capture);

  await tester.tap(find.byTooltip('Category options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Archive category'));
  await tester.pumpAndSettle();
  expect(find.text('Move its money first'), findsOneWidget);
  _expectNoOverflow(tester, '$view: archive dialog');
  await _expectGuidelines(tester, '$view: archive dialog');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  expect(find.text('Move its money first'), findsNothing);

  await tester.tap(find.byTooltip('Back to budget'));
  await tester.pumpAndSettle();
  expect(find.byType(CategoryScreen), findsNothing);
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

/// Opens the budget switcher sheet by tapping the budget's name, checks it,
/// then taps the open budget's row, which closes the sheet without switching
/// or creating anything.
Future<void> _openBudgetSwitcher(WidgetTester tester, String view) async {
  await tester.tap(find.text('Home'));
  await tester.pumpAndSettle();
  expect(find.text('Budgets'), findsOneWidget);
  expect(find.text('New budget'), findsOneWidget);
  _expectNoOverflow(tester, '$view: budget switcher');
  await _expectGuidelines(tester, '$view: budget switcher');
  // Header and sheet both say Home; the sheet's row is the last one.
  await tester.tap(find.text('Home').last);
  await tester.pumpAndSettle();
  expect(find.text('Budgets'), findsNothing);
}

/// Picks a Category for the line in Review: the sheet opens, the Category is
/// tapped, and the sheet closes with the button now showing it.
Future<void> _pickReviewCategory(WidgetTester tester, String view) async {
  await tester.tap(find.byKey(const ValueKey('review-category')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('category-search')), findsOneWidget);
  _expectNoOverflow(tester, '$view: category picker');
  await _expectGuidelines(tester, '$view: category picker');
  await tester.tap(find.text('Groceries').first);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('category-search')), findsNothing);
  expect(find.text('Groceries'), findsOneWidget);
}

/// Errors the framework reported while laying out since the last checkpoint. A
/// RenderFlex overflow arrives here as a `FlutterError` during layout.
final _layoutErrors = <String>[];

/// Records every error a frame reports for the rest of the test, instead of only
/// the frame a view happens to end on. The handler the binding installed stays
/// underneath: it is what turns a failure into a test failure, and it asserts
/// that it saw any `expect` this test raises.
void _recordLayoutErrors() {
  _layoutErrors.clear();
  final reported = FlutterError.onError;
  FlutterError.onError = (details) {
    _layoutErrors.add(details.exceptionAsString());
    reported?.call(details);
  };
}

/// Fails the pass if any frame overflowed or otherwise failed to lay out,
/// naming the screen the pass was on.
void _expectNoOverflow(WidgetTester tester, String view) {
  final errors = [..._layoutErrors];
  _layoutErrors.clear();
  // The binding keeps its own copy of each error; hand it back so the next one
  // reported is not read as a second, unrelated failure.
  tester.takeException();
  expect(
    errors,
    isEmpty,
    reason: 'Layout errors on $view:\n\n${errors.join('\n\n')}',
  );
}

/// Goldens are generated with `flutter test --update-goldens` and compared only
/// on a run that was asked to write them. An ordinary `flutter test` therefore
/// audits every screen and every scale factor without needing the images, and
/// passes when they are missing or were drawn on another platform.
bool get _comparesGoldens => autoUpdateGoldenFiles;

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_comparesGoldens) return;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

/// A primary-view pass: every tab the phone has, in order, ending back where it
/// started. Each hop is a real tap on the bottom navigation; every screen and
/// every dialog opened on the way is checked for layout errors and both
/// guidelines before the next one is opened.
///
/// The three dialogs the flow reaches are tapped through as well: the budget
/// switcher, Review's Category picker and a Category's Archive explanation.
Future<void> _capturePrimaryViews(
  WidgetTester tester,
  String prefix, {
  required String home,
}) async {
  final view = '$prefix: Budget';
  _expectNoOverflow(tester, view);
  await _expectGuidelines(tester, view);
  expect(find.byType(BudgetScreen), findsOneWidget);
  expect(find.text('READY TO ASSIGN'), findsOneWidget);
  await _capture(tester, home);

  // The budget switcher, opened from the header and closed on its own row.
  await _openBudgetSwitcher(tester, view);
  _expectNoOverflow(tester, '$view after the budget switcher');

  // A Category and its Archive dialog, then back to the month.
  await _openCategoryAndDialog(tester, view, capture: '${prefix}_category');
  _expectNoOverflow(tester, '$view after the category dialog');

  await _open(tester, Section.review);
  _expectNoOverflow(tester, '$prefix: Review');
  await _expectGuidelines(tester, '$prefix: Review');
  expect(find.byType(ReviewScreen), findsOneWidget);
  await _capture(tester, '${prefix}_review');

  // Review's Category picker: a real tap on the sheet, then a real choice.
  await _pickReviewCategory(tester, '$prefix: Review');
  _expectNoOverflow(tester, '$prefix: Review after the category picker');
  await _expectGuidelines(tester, '$prefix: Review with a category chosen');

  await _open(tester, Section.accounts);
  _expectNoOverflow(tester, '$prefix: Accounts');
  await _expectGuidelines(tester, '$prefix: Accounts');
  expect(find.byType(AccountsScreen), findsOneWidget);
  expect(find.text('Budget accounts'), findsOneWidget);
  await _capture(tester, '${prefix}_accounts');

  await _open(tester, Section.history);
  _expectNoOverflow(tester, '$prefix: History');
  await _expectGuidelines(tester, '$prefix: History');
  expect(find.byType(HistoryScreen), findsOneWidget);
  expect(find.text('Change History'), findsOneWidget);
  await _capture(tester, '${prefix}_history');

  // Back to where the pass started, so the round trip is exercised too.
  await _open(tester, Section.budget);
  _expectNoOverflow(tester, '$prefix: Budget again');
  await _expectGuidelines(tester, '$prefix: Budget again');
  expect(find.byType(BudgetScreen), findsOneWidget);
}

/// One full audit pass: pumps the app on a fresh budget at [size], with
/// [textScale] and [brightness], taps through every primary view, and hands
/// the semantics handle back when it is done.
Future<void> _audit(
  WidgetTester tester,
  String prefix, {
  Size size = _phone,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final semantics = await _pump(
    tester,
    _seed(),
    size: size,
    textScale: textScale,
    brightness: brightness,
  );
  try {
    await _capturePrimaryViews(tester, prefix, home: '${prefix}_home');
    _expectNoOverflow(tester, '$prefix: final frame');
  } finally {
    semantics.dispose();
  }
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
    await _audit(tester, 'light');
  });

  testWidgets('dark mode, 390 x 844', (tester) async {
    await _audit(tester, 'dark', brightness: Brightness.dark);
  });

  testWidgets('small phone, 320 x 568, 1.6x text', (tester) async {
    await _audit(tester, 'small_scale', size: _smallPhone, textScale: 1.6);
  });
}
