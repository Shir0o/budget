import 'dart:convert';

import 'package:budget/app.dart';
import 'package:budget/screens/settings_screen.dart';
import 'package:budget/services.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Home, with a checking account that starts at 4,210.55
/// and a Groceries Category.
(BudgetEngine, AppServices) _home() {
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
  final group =
      (engine.execute(
            const CreateCategoryGroup(name: 'Everyday'),
          ) as Accepted).events.single.payload['categoryGroupId']
          as String;
  engine.execute(CreateCategory(groupId: group, name: 'Groceries'));
  return (engine, AppServices.inMemory());
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  BudgetEngine engine,
  AppServices services,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BudgetApp(engine: engine, services: services));
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

Finder _pane(String label) => find.byKey(ValueKey('settings-pane-$label'));

final _content = find.byKey(const ValueKey('settings-pane-content'));

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(_pane(label));
  await tester.pumpAndSettle();
}

const _paneLabels = [
  'Budgets',
  'Bank connection',
  'Encrypted sync',
  'Devices and recovery phrase',
  'Business Tags',
  'Import and export',
  'AI apps',
  'App lock',
  'Redact a value',
];

const _accessUrl = 'https://user:pass@bridge.example/simplefin/access/xyz';

/// The bridge's answer: one synthetic checking account with one charge.
String _fetchJson() {
  final posted = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({
    'errors': const <String>[],
    'accounts': [
      {
        'org': {'name': 'Sample Bank'},
        'id': 'acct-1',
        'name': 'Everyday Checking ...1234',
        'currency': 'USD',
        'balance': '1234.56',
        'available-balance': '1200.06',
        'balance-date': posted,
        'transactions': [
          {
            'id': 'tx-1',
            'posted': posted,
            'amount': '-48.20',
            'description': 'CORNER BISTRO',
            'payee': 'Corner Bistro',
            'memo': 'Lunch',
          },
        ],
      },
    ],
  });
}

void main() {
  testWidgets('the Settings button opens a window with every pane listed', (
    tester,
  ) async {
    final (engine, services) = _home();
    await _pumpAt(tester, const Size(1280, 820), engine, services);
    await _openSettings(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
    for (final label in _paneLabels) {
      expect(_pane(label), findsOneWidget, reason: label);
    }

    // Budgets is the first pane: this device's budgets are listed.
    expect(
      find.descendant(of: _content, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _content, matching: find.text('New budget')),
      findsOneWidget,
    );

    // Back returns to the section the window was on.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
  });

  testWidgets('choosing a pane shows that pane\'s content', (tester) async {
    final (engine, services) = _home();
    await _pumpAt(tester, const Size(1280, 820), engine, services);
    await _openSettings(tester);

    Future<void> expectContent(List<String> texts) async {
      for (final text in texts) {
        expect(
          find.descendant(of: _content, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
    }

    await _choose(tester, 'Bank connection');
    await expectContent(['Status', 'Not connected', 'Connect bank']);

    await _choose(tester, 'Encrypted sync');
    await expectContent(['Status', 'This device only', 'Last sync']);

    await _choose(tester, 'Devices and recovery phrase');
    await expectContent(['Pair a device', 'Recovery phrase']);

    await _choose(tester, 'Business Tags');
    await expectContent(['Business tags', '19 tags']);

    await _choose(tester, 'Import and export');
    await expectContent([
      'Export & backup',
      'Import from Actual',
      'Import & compare',
    ]);

    await _choose(tester, 'AI apps');
    await expectContent(['AI apps (MCP)', 'Off']);

    await _choose(tester, 'App lock');
    expect(
      find.descendant(of: _content, matching: find.text('Off')),
      findsOneWidget,
    );

    await _choose(tester, 'Redact a value');
    await expectContent(['Checking · Name', 'Checking']);
  });

  testWidgets('Connect bank opens as a sheet on desktop', (tester) async {
    final (engine, services) = _home();
    await _pumpAt(tester, const Size(1280, 820), engine, services);
    await _openSettings(tester);
    await _choose(tester, 'Bank connection');

    await tester.tap(
      find.descendant(of: _content, matching: find.text('Connect bank')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flow-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-token')), findsOneWidget);
    // The Settings panes stay behind the sheet.
    expect(_pane('Bank connection'), findsOneWidget);
  });

  testWidgets('bank errors show as a problem card with a fix action', (
    tester,
  ) async {
    final (engine, services) = _home();
    await services.prefs.writeSimpleFinBook(
      const SimpleFinBook().withErrors([
        BankError(
          message: 'SimpleFIN refused the access URL.',
          day: CivilDate(2026, 11, 1),
          auth: true,
        ),
      ]),
    );
    await _pumpAt(tester, const Size(1280, 820), engine, services);
    await _openSettings(tester);
    await _choose(tester, 'Bank connection');

    expect(find.byKey(const ValueKey('settings-bank-problem')), findsOneWidget);
    expect(
      find.descendant(
        of: _content,
        matching: find.text('SimpleFIN refused the access URL.'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.descendant(of: _content, matching: find.text('Fix')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flow-sheet')), findsOneWidget);
  });

  testWidgets('Link accounts also opens as a sheet', (tester) async {
    final (engine, _) = _home();
    final services = AppServices(
      keys: InMemoryBudgetKeyStore(),
      prefs: InMemoryDevicePrefs(),
      saver: InMemoryFileSaver(),
      authenticator: FakeAuthenticator(),
      simpleFin: FakeSimpleFinTransport(
        replies: {
          'GET /simplefin/access/xyz/accounts': SimpleFinReply(
            200,
            _fetchJson(),
          ),
        },
      ),
    );
    await services.prefs.writeSimpleFinBook(
      const SimpleFinBook(accessUrl: _accessUrl),
    );
    await _pumpAt(tester, const Size(1280, 820), engine, services);
    await _openSettings(tester);
    await _choose(tester, 'Bank connection');
    await tester.tap(
      find.descendant(of: _content, matching: find.text('Connect bank')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('link-accounts')));
    await tester.pumpAndSettle();

    expect(find.text('Everyday Checking ...1234'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-links')), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-sheet')), findsNWidgets(2));
  });

  testWidgets('phone Settings is unchanged', (tester) async {
    final (engine, services) = _home();
    // The default test window is below the desktop breakpoint; the test font
    // is wider than IBM Plex, so a phone-width window overflows its rows.
    await _pumpAt(tester, const Size(800, 600), engine, services);
    await _openSettings(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-panes')), findsNothing);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Export & backup'), findsOneWidget);
    expect(find.text('Import & compare'), findsOneWidget);
  });
}
