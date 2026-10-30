import 'dart:convert';

import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Studio, with Checking, a 1,500.00 client payment,
/// a 48.21 lunch, a 40.00 gift to Dana, and one Unreviewed charge.
BudgetEngine _studio() {
  final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  engine.execute(const CreateBudget(name: 'Studio'));
  engine.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: const Money(500000),
      asOf: CivilDate(2026, 1, 5),
    ),
  );
  final checking = engine.state.accounts.single.id;
  engine.execute(const CreateCategoryGroup(name: 'Everyday'));
  final group = engine.state.categoryGroups.single.id;
  engine.execute(CreateCategory(groupId: group, name: 'Advertising'));
  final advertising = engine.state.categories.single.id;

  void spend(
    int cents,
    String tag,
    CivilDate date,
    String payee, {
    String? recipient,
  }) {
    engine.execute(
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
  }

  engine.execute(
    CreateTransaction(
      accountId: checking,
      date: CivilDate(2026, 1, 5),
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
  spend(4821, 'Meals', CivilDate(2026, 1, 20), 'Corner Bistro');
  spend(4000, giftsTag, CivilDate(2026, 2, 1), 'Florist', recipient: 'Dana');
  // Its business-use % isn't set, so the report warns and deducts nothing.
  spend(10000, 'Car & truck', CivilDate(2026, 2, 10), 'Metro Fuel');
  engine.execute(
    CreateTransaction(
      accountId: checking,
      date: CivilDate(2026, 3, 1),
      amount: const Money(-1200),
      payee: 'Mystery charge',
      lines: [const LineInput(amount: Money(-1200))],
    ),
  );
  return engine;
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String row) async {
  await _openSettings(tester);
  await tester.scrollUntilVisible(find.text(row), 200);
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
}

void main() {
  group('Business tags', () {
    testWidgets('set a business-use % for the tax year', (tester) async {
      final engine = _studio();
      await tester.pumpWidget(BudgetApp(engine: engine));
      await _open(tester, 'Business tags');

      expect(find.text('Business tags'), findsOneWidget);
      expect(find.text('Car & truck'), findsOneWidget);
      expect(find.text('Set %'), findsNWidgets(2));

      await tester.tap(find.text('Car & truck'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('business-use-percent')),
        '80',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(engine.state.businessUse('Car & truck', 2026), 80);
      expect(find.text('80%'), findsOneWidget);
    });

    testWidgets('add a custom tag with its own line and rule', (tester) async {
      final engine = _studio();
      await tester.pumpWidget(BudgetApp(engine: engine));
      await _open(tester, 'Business tags');

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('add-business-tag')),
        300,
      );
      await tester.tap(find.byKey(const ValueKey('add-business-tag')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('business-tag-name')),
        'Studio rent',
      );
      await tester.tap(find.byKey(const ValueKey('business-line')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule C line 20b').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final tag = engine.state.businessTag('Studio rent')!;
      expect(tag.line, '20b');
      expect(tag.custom, isTrue);
      expect(tag.rule, isA<FullDeduction>());
      expect(find.text('Studio rent'), findsOneWidget);
    });
  });

  group('Business report', () {
    testWidgets('shows the year, warnings, totals and both CSVs', (
      tester,
    ) async {
      final engine = _studio();
      final services = AppServices.inMemory();
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await _open(tester, 'Business report');

      expect(find.text('Business report'), findsOneWidget);
      expect(find.textContaining('1 Unreviewed line in 2026'), findsOneWidget);
      expect(
        find.textContaining('Set a business-use % for Car & truck in 2026'),
        findsOneWidget,
      );
      expect(find.text('\$1,500.00'), findsWidgets);
      expect(find.text('\$49.10'), findsOneWidget);
      expect(find.text('\$1,450.90'), findsOneWidget);
      expect(find.text('Meals'), findsOneWidget);
      expect(find.textContaining('deductible \$24.10'), findsWidgets);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('business-summary-export')),
        300,
      );
      await tester.tap(find.byKey(const ValueKey('business-summary-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('business-detail-export')));
      await tester.pumpAndSettle();

      final saved = (services.saver as InMemoryFileSaver).saved;
      final report = engine.state.businessReport(2026);
      expect(
        utf8.decode(saved['business-summary-2026.csv']!),
        businessSummaryCsv(report),
      );
      expect(
        utf8.decode(saved['business-detail-2026.csv']!),
        businessDetailCsv(report),
      );
      expect(find.text('Saved business-summary-2026.csv'), findsOneWidget);
      expect(find.text(businessReportFooter), findsOneWidget);
    });

    testWidgets('clears the missing business-use warning once it is set', (
      tester,
    ) async {
      final engine = _studio();
      await tester.pumpWidget(BudgetApp(engine: engine));
      await _open(tester, 'Business tags');

      await tester.scrollUntilVisible(find.text('Car & truck'), 200);
      await tester.tap(find.text('Car & truck'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('business-use-percent')),
        '100',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Business report'), 200);
      await tester.tap(find.text('Business report'));
      await tester.pumpAndSettle();

      expect(engine.state.businessReport(2026).warnings, hasLength(1));
      expect(
        find.textContaining('business-use % for Car & truck'),
        findsNothing,
      );
      expect(find.text('\$149.10'), findsOneWidget);
    });
  });
}
