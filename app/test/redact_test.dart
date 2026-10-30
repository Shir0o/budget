import 'package:budget/app.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Checking with 500.00, Groceries, and one outflow
/// whose payee and memo hold nothing a bank would send, only values a
/// person typed by mistake.
final class _Seed {
  _Seed() {
    engine.execute(const CreateBudget(name: 'Home'));
    engine.execute(
      AddAccount(
        name: 'Checking',
        type: AccountType.checking,
        startingBalance: const Money(50000),
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
    transactionId =
        (engine.execute(
              CreateTransaction(
                accountId: state.accounts.single.id,
                date: today(),
                amount: const Money(-4820),
                payee: 'Sunset Storage',
                memo: 'Gate code 7781',
                lines: [
                  LineInput(amount: const Money(-4820), category: groceries),
                ],
              ),
            ) as Accepted).events.single.payload['transactionId']
            as String;
  }

  final log = InMemoryEventLog();
  late final engine = _engine();
  late final String groceries;
  late final String transactionId;

  BudgetEngine _engine() =>
      BudgetEngine(log: log, deviceId: 'test-device', actor: Actor.userAndroid);

  /// The app over the seeded log, as it opens after a restart.
  Widget app() => BudgetApp(engine: _engine());

  BudgetState get state => BudgetState.replay(log.readAll());

  Transaction get transaction => state.transaction(transactionId)!;
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the transaction menu redacts a field everywhere', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());

    await _tap(tester, find.text('Accounts'));
    await _tap(tester, find.text('Checking'));
    await _tap(tester, find.text('Sunset Storage'));
    await _tap(tester, find.byTooltip('Transaction options'));
    await _tap(tester, find.text('Redact a field'));

    expect(find.text('Redact a field'), findsOneWidget);
    expect(find.textContaining('It can’t be undone'), findsOneWidget);
    expect(find.text('Sunset Storage'), findsOneWidget);
    expect(find.text('Gate code 7781'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Redact field'),
          )
          .onPressed,
      isNull,
    );

    await _tap(tester, find.text('Sunset Storage'));
    await _tap(tester, find.text('Redact field'));
    expect(find.text('Redact this field?'), findsOneWidget);
    await _tap(tester, find.text('Redact'));

    // Back on the register, with the value gone from the projection.
    expect(seed.transaction.payee, redactedValue);
    expect(seed.transaction.memo, 'Gate code 7781');
    expect(find.text(redactedValue), findsOneWidget);
    expect(
      seed.log.readAll().map((event) => event.payload.toString()).join(),
      isNot(contains('Sunset Storage')),
    );

    // Change History names what was redacted and cannot revert it.
    await _tap(tester, find.byTooltip('Back'));
    await _tap(tester, find.text('History'));
    expect(
      find.text('Redacted the payee of $redactedValue −48.20'),
      findsOneWidget,
    );
    final card = find
        .ancestor(
          of: find.text('Redacted the payee of $redactedValue −48.20'),
          matching: find.byType(Container),
        )
        .first;
    expect(
      find.descendant(
        of: card,
        matching: find.widgetWithText(OutlinedButton, 'Revert'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.text('Payee  $redactedValue')),
      findsOneWidget,
    );
  });

  testWidgets('Change History offers a redaction, and says what is left', (
    tester,
  ) async {
    final seed = _Seed();
    await _pump(tester, seed.app());

    await _tap(tester, find.text('History'));
    final added = find
        .ancestor(
          of: find.text('Added Sunset Storage −48.20'),
          matching: find.byType(Container),
        )
        .first;
    await _tap(
      tester,
      find.descendant(
        of: added,
        matching: find.widgetWithText(TextButton, 'Redact'),
      ),
    );
    expect(find.text('Redact a field'), findsOneWidget);
    expect(find.text('Memo'), findsOneWidget);
    expect(find.text('Gate code 7781'), findsOneWidget);

    await _tap(tester, find.text('Memo'));
    await _tap(tester, find.text('Redact field'));
    await _tap(tester, find.text('Redact'));

    expect(seed.transaction.memo, redactedValue);
    expect(
      find.text('Redacted the memo of Sunset Storage −48.20'),
      findsOneWidget,
    );
    expect(find.text('Memo  [redacted]'), findsOneWidget);

    // The payee is still there, so a redaction is still offered, now with
    // only the payee left to choose.
    final redacted = find
        .ancestor(
          of: find.text('Redacted the memo of Sunset Storage −48.20'),
          matching: find.byType(Container),
        )
        .first;
    await _tap(
      tester,
      find.descendant(
        of: redacted,
        matching: find.widgetWithText(TextButton, 'Redact'),
      ),
    );
    expect(find.text('Payee'), findsOneWidget);
    expect(find.text('Memo'), findsNothing);
  });
}
