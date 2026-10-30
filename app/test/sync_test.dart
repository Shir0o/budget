import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Home, Checking at 4,210.55, and Groceries in
/// Everyday.
final class _Seed {
  _Seed() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(421055),
        asOf: today(),
      ),
    );
    final group =
        (engine.execute(
              const CreateCategoryGroup(name: 'Everyday'),
            ) as Accepted).events.single.payload['categoryGroupId']
            as String;
    groceries =
        (engine.execute(
              CreateCategory(groupId: group, name: 'Groceries'),
            ) as Accepted).events.single.payload['categoryId']
            as String;
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  late final String groceries;

  /// An outflow to Corner Bistro, returning its id.
  String spend() =>
      (engine.execute(
            CreateTransaction(
              accountId: engine.state.accounts.single.id,
              date: today(),
              amount: const Money(-4820),
              payee: 'Corner Bistro',
              lines: [
                LineInput(
                  amount: const Money(-4820),
                  category: groceries,
                  business: const Personal(),
                ),
              ],
            ),
          ) as Accepted).events.single.payload['transactionId']
          as String;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openSync(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('Settings'));
  await _tap(tester, find.text('Encrypted sync'));
}

/// One hand-written Event, as the other device wrote it.
Event _fromPhone(String type, Map<String, Object?> payload, int wallMs) =>
    Event(
      id: 'phone-$wallMs-$type',
      budgetId: 'phone-budget',
      deviceId: 'phone',
      hlc: Hlc(wallMs, 0, 'phone'),
      actor: const Actor.fromValue('user@android'),
      groupId: 'phone-$wallMs',
      type: type,
      payload: payload,
    );

void main() {
  testWidgets('Turn on sync writes sealed files and then shows the state', (
    tester,
  ) async {
    final seed = _Seed();
    seed.spend();
    final services = AppServices.inMemory();
    await tester.pumpWidget(BudgetApp(engine: seed.engine, services: services));

    await _openSync(tester);
    expect(find.text('Turn on sync'), findsWidgets);
    expect(find.text('Sync now'), findsNothing);

    await _tap(tester, find.byKey(const ValueKey('turn-on-sync')));

    // The screen switched to the on state and synced once.
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('This device only'), findsOneWidget);
    expect(find.textContaining('from this one'), findsOneWidget);

    // Every file went into this device's folder, named by an id only.
    final drive = services.drive as InMemoryDrive;
    expect(drive.uploads, isNotEmpty);
    for (final upload in drive.uploads) {
      expect(
        upload.name == DeviceManifest.fileName ||
            upload.name.startsWith('seg-'),
        isTrue,
        reason: '${upload.name} should reveal only an id',
      );
    }
    final book = await services.prefs.readSyncBook(
      seed.engine.state.budget!.id,
    );
    expect(book.enabled, isTrue);

    // Settings shows it on.
    await _tap(tester, find.byTooltip('Back'));
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('turning sync off stops this device and leaves the budget', (
    tester,
  ) async {
    final seed = _Seed();
    final services = AppServices.inMemory();
    await tester.pumpWidget(BudgetApp(engine: seed.engine, services: services));
    await _openSync(tester);
    await _tap(tester, find.byKey(const ValueKey('turn-on-sync')));

    await _tap(tester, find.byKey(const ValueKey('turn-off-sync')));
    await _tap(tester, find.text('Turn off'));

    expect(find.text('Turn on sync'), findsWidgets);
    expect(find.text('Sync is off on this device.'), findsOneWidget);
    expect(seed.engine.state.budget, isNotNull);
    final book = await services.prefs.readSyncBook(
      seed.engine.state.budget!.id,
    );
    expect(book.enabled, isFalse);
  });

  testWidgets('a merge that breaks an invariant is a Review item', (
    tester,
  ) async {
    final seed = _Seed();
    seed.engine.merge([
      _fromPhone(EventType.transactionCreated, {
        'transactionId': 'broken-split',
        'accountId': seed.engine.state.accounts.single.id,
        'date': '2026-11-12',
        'payee': 'Hardware',
        'amountCents': -3000,
        'lines': [
          {'lineId': 'line-1', 'amountCents': -2000, 'category': null},
        ],
      }, DateTime.now().millisecondsSinceEpoch + 1000),
    ]);
    await tester.pumpWidget(BudgetApp(engine: seed.engine));

    await _tap(tester, find.text('Review'));
    expect(
      find.byKey(const ValueKey('review-needs-attention')),
      findsOneWidget,
    );
    expect(find.text('Needs attention'), findsOneWidget);
    expect(
      find.text('The lines of “Hardware” don’t add up to its amount.'),
      findsOneWidget,
    );
    // The transaction itself is kept, not dropped.
    expect(seed.engine.state.transaction('broken-split'), isNotNull);
  });

  testWidgets('History says a losing value was overwritten by sync', (
    tester,
  ) async {
    final seed = _Seed();
    final id = seed.spend();
    seed.engine.execute(EditTransaction(transactionId: id, payee: 'Bistro'));
    seed.engine.merge([
      _fromPhone(EventType.transactionFieldsSet, {
        'transactionId': id,
        'fields': {'payee': 'Cafe Bistro'},
      }, DateTime.now().millisecondsSinceEpoch + 1000),
    ]);
    await tester.pumpWidget(BudgetApp(engine: seed.engine));

    await _tap(tester, find.text('History'));
    expect(find.textContaining('overwritten by sync'), findsOneWidget);
    expect(find.textContaining('Cafe Bistro'), findsWidgets);
    expect(seed.engine.state.transaction(id)!.payee, 'Cafe Bistro');
  });
}
