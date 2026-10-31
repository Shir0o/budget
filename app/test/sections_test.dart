import 'package:budget/screens/accounts_screen.dart';
import 'package:budget/screens/budget_screen.dart';
import 'package:budget/screens/business_report_screen.dart';
import 'package:budget/screens/forecast_screen.dart';
import 'package:budget/screens/history_screen.dart';
import 'package:budget/screens/review_screen.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget with one uncategorized line, so Review has something to
/// badge.
BudgetEngine _engine() {
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
      startingBalance: Money.zero,
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  engine.execute(
    CreateTransaction(
      accountId: engine.state.accounts.single.id,
      date: CivilDate(2026, 11, 2),
      amount: const Money(-1200),
      payee: 'Paper & Co.',
      lines: [const LineInput(amount: Money(-1200))],
    ),
  );
  return engine;
}

void main() {
  test('the bottom navigation shows four sections, in order', () {
    expect(
      [
        for (final section in Section.values)
          if (section.inBottomNav) section,
      ],
      [Section.budget, Section.review, Section.accounts, Section.history],
    );
  });

  test('the one model also covers Forecast and Business report', () {
    expect(
      [for (final section in Section.values) section.label],
      [
        'Budget',
        'Review',
        'Accounts',
        'History',
        'Forecast',
        'Business report',
      ],
    );
  });

  test('Review badges the Unreviewed count and no other section does', () {
    final state = _engine().state;
    expect(state.reviewQueue, hasLength(1));
    expect(Section.review.badge(state), 1);
    for (final section in Section.values) {
      if (section == Section.review) continue;
      expect(section.badge(state), 0, reason: section.label);
    }
  });

  test('each section builds its screen', () {
    final engine = _engine();
    final services = AppServices.inMemory();
    expect(Section.budget.screen(engine, services), isA<BudgetScreen>());
    expect(Section.review.screen(engine, services), isA<ReviewScreen>());
    expect(Section.accounts.screen(engine, services), isA<AccountsScreen>());
    expect(Section.history.screen(engine, services), isA<HistoryScreen>());
    expect(Section.forecast.screen(engine, services), isA<ForecastScreen>());
    expect(
      Section.businessReport.screen(engine, services),
      isA<BusinessReportScreen>(),
    );
  });
}
