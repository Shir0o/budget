import 'package:budget/app.dart';
import 'package:budget/screens/account_register_screen.dart';
import 'package:budget/screens/accounts_screen.dart';
import 'package:budget/screens/budget_screen.dart';
import 'package:budget/screens/business_report_screen.dart';
import 'package:budget/screens/forecast_screen.dart';
import 'package:budget/screens/history_screen.dart';
import 'package:budget/screens/review_screen.dart';
import 'package:budget/screens/welcome_screen.dart';
import 'package:budget/theme.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
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

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  BudgetEngine engine,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BudgetApp(engine: engine));
  await tester.pumpAndSettle();
}

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

  testWidgets('a phone window is unchanged', (tester) async {
    await _pumpAt(tester, const Size(390, 844), _home());

    expect(tester.getSize(find.byType(Scaffold).first).width, 390);
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
    // The bottom navigation, and no sidebar.
    expect(find.byType(MainNav), findsOneWidget);
    expect(_sidebar, findsNothing);
    expect(find.text('Forecast'), findsNothing);
  });
}
