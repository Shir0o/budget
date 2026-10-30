import 'package:budget/app.dart';
import 'package:budget/desktop.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget so the app opens on the Budget screen.
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
  return engine;
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BudgetApp(engine: _home()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a desktop window runs the same screens in one column', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1400, 900));

    final scaffold = tester.getSize(find.byType(Scaffold).first);
    expect(scaffold.width, desktopContentWidth);
    expect(scaffold.height, 900);
    // The same Budget screen as on a phone.
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
  });

  testWidgets('a phone window is unchanged', (tester) async {
    await _pumpAt(tester, const Size(390, 844));

    expect(tester.getSize(find.byType(Scaffold).first).width, 390);
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
  });
}
