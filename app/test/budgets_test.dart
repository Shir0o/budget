import 'package:budget/app.dart';
import 'package:budget/budget_library.dart';
import 'package:budget/services.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _nov = CalendarMonth(2026, 11);

Future<BudgetLibrary> _load(InMemoryBudgetStorage storage, DevicePrefs prefs) =>
    BudgetLibrary.load(
      storage: storage,
      prefs: prefs,
      deviceId: 'test-device',
      actor: Actor.userAndroid,
    );

/// Saves a synthetic budget with one checking account, the way the Welcome
/// flow does.
Future<BudgetEngine> _saveBudget(
  BudgetLibrary library,
  String name,
  Money balance,
) async {
  final draft = library.startNew();
  draft.execute(CreateBudget(name: name));
  draft.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: balance,
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  return library.commit(draft);
}

void main() {
  group('BudgetLibrary', () {
    test('gives each budget its own id, store and Budget Key', () async {
      final storage = InMemoryBudgetStorage();
      final services = AppServices.inMemory();
      final library = await _load(storage, services.prefs);
      final personal = await _saveBudget(library, 'Personal', const Money(100));
      final side = await _saveBudget(library, 'Side business', const Money(5));

      final personalId = personal.state.budget!.id;
      final sideId = side.state.budget!.id;
      expect(personalId, isNot(sideId));
      expect(
        (await storage.openLog(personalId)).readAll().map((e) => e.budgetId),
        everyElement(personalId),
      );
      expect(
        (await storage.openLog(sideId)).readAll().map((e) => e.budgetId),
        everyElement(sideId),
      );
      expect(
        (await services.keys.keyFor(personalId)).toHex(),
        isNot((await services.keys.keyFor(sideId)).toHex()),
      );
      expect(
        personal.state.readyToAssign(_nov),
        isNot(side.state.readyToAssign(_nov)),
      );
    });

    test('reopens the budget that was open last', () async {
      final storage = InMemoryBudgetStorage();
      final prefs = InMemoryDevicePrefs();
      final first = await _load(storage, prefs);
      final personal = await _saveBudget(first, 'Personal', const Money(100));
      await _saveBudget(first, 'Side business', const Money(5));
      await first.switchTo(personal.state.budget!.id);

      final restarted = await _load(storage, prefs);

      expect(restarted.current.state.budget?.name, 'Personal');
      expect(restarted.entries.map((e) => e.name), [
        'Personal',
        'Side business',
      ]);
      expect(restarted.current.state.readyToAssign(_nov), const Money(100));
    });

    test('a new budget is not stored until it is committed', () async {
      final prefs = InMemoryDevicePrefs();
      final library = await _load(InMemoryBudgetStorage(), prefs);
      await _saveBudget(library, 'Personal', const Money(100));

      library.startNew().execute(const CreateBudget(name: 'Abandoned'));

      expect(library.entries.map((e) => e.name), ['Personal']);
      expect(await prefs.readBudgetIds(), hasLength(1));
    });
  });

  group('Budget switcher', () {
    Future<(BudgetLibrary, InMemoryDevicePrefs)> twoBudgets(
      WidgetTester tester,
      AppServices services,
    ) async {
      final prefs = InMemoryDevicePrefs();
      final library = await tester.runAsync(() async {
        final library = await _load(InMemoryBudgetStorage(), prefs);
        await _saveBudget(library, 'Personal', const Money(41200));
        await _saveBudget(library, 'Side business', const Money(9900));
        await library.switchTo(library.entries.first.id);
        return library;
      });
      return (library!, prefs);
    }

    testWidgets('lists the budgets and opens the one tapped', (tester) async {
      final services = AppServices.inMemory();
      final (library, prefs) = await twoBudgets(tester, services);
      await tester.pumpWidget(BudgetApp(library: library, services: services));
      expect(find.text('\$412.00'), findsOneWidget);

      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();

      expect(find.text('Budgets'), findsOneWidget);
      expect(find.text('Open now'), findsOneWidget);
      expect(find.text('This phone only'), findsOneWidget);
      expect(find.text('New budget'), findsOneWidget);

      await tester.tap(find.text('Side business'));
      await tester.pumpAndSettle();

      expect(find.text('Budgets'), findsNothing);
      expect(find.text('\$99.00'), findsOneWidget);
      expect(library.current.state.budget?.name, 'Side business');
      expect(await prefs.readLastBudgetId(), library.current.state.budget!.id);
    });

    testWidgets('New budget goes through Welcome and keeps the others', (
      tester,
    ) async {
      final services = AppServices.inMemory();
      final (library, _) = await twoBudgets(tester, services);
      await tester.pumpWidget(BudgetApp(library: library, services: services));

      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New budget'));
      await tester.pumpAndSettle();

      expect(find.text('Give every dollar a job'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('budget-name')),
        'Vacation',
      );
      await tester.tap(find.text('Add your first account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('account-balance')),
        '250',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Vacation'), findsOneWidget);
      expect(find.text('\$250.00'), findsOneWidget);
      expect(library.entries.map((e) => e.name), [
        'Personal',
        'Side business',
        'Vacation',
      ]);
      final ids = library.entries.map((e) => e.id).toSet();
      expect(ids, hasLength(3));
      expect(library.current.state.budget?.name, 'Vacation');
    });
  });
}
