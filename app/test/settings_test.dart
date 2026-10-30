import 'dart:convert';

import 'package:budget/app.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic budget: Home, with a checking account that starts at 4,210.55.
(BudgetEngine, InMemoryEventLog) _home() {
  final log = InMemoryEventLog();
  final engine = BudgetEngine(
    log: log,
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
  return (engine, log);
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

Future<void> _openExport(WidgetTester tester) async {
  await _openSettings(tester);
  await tester.tap(find.text('Export & backup'));
  await tester.pumpAndSettle();
}

Future<void> _openAppLock(WidgetTester tester) async {
  await _openSettings(tester);
  await tester.tap(find.text('App lock'));
  await tester.pumpAndSettle();
}

InMemoryFileSaver _saver(AppServices services) =>
    services.saver as InMemoryFileSaver;

FakeAuthenticator _auth(AppServices services) =>
    services.authenticator as FakeAuthenticator;

void main() {
  group('Settings', () {
    testWidgets('opens from the Budget screen and lists what exists today', (
      tester,
    ) async {
      final (engine, _) = _home();
      await tester.pumpWidget(BudgetApp(engine: engine));
      await _openSettings(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Export & backup'), findsOneWidget);
      expect(find.text('App lock'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Category priority'), findsOneWidget);
      // Rows for features that aren't built yet stay hidden.
      for (final hidden in [
        'Business tags',
        'Business report',
        'Forecast',
        'Bank sync',
        'Encrypted sync',
        'AI apps (MCP)',
        'Import & compare',
      ]) {
        expect(find.text(hidden), findsNothing);
      }
    });
  });

  group('Export & backup', () {
    testWidgets('saves the transactions CSV from the core', (tester) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory();
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await _openExport(tester);

      await tester.tap(find.byKey(const ValueKey('export-transactions')));
      await tester.pumpAndSettle();

      final file = _saver(services).saved.entries.single;
      expect(file.key, startsWith('budget-transactions-'));
      expect(file.key, endsWith('.csv'));
      expect(utf8.decode(file.value), transactionsCsv(engine.state));
      expect(find.text('Saved ${file.key}'), findsOneWidget);
    });

    testWidgets('saves the assignments CSV and the JSON state', (tester) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory();
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await _openExport(tester);

      await tester.tap(find.byKey(const ValueKey('export-assignments')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-json')));
      await tester.pumpAndSettle();

      final saved = _saver(services).saved;
      final csv = saved.keys.singleWhere((n) => n.contains('assignments'));
      final json = saved.keys.singleWhere((n) => n.endsWith('.json'));
      expect(utf8.decode(saved[csv]!), assignmentsCsv(engine.state));
      expect(
        utf8.decode(saved[json]!),
        stateJson(engine.state, month: thisMonth()),
      );
    });

    testWidgets('seals the backup with the Budget Key, kept out of the log', (
      tester,
    ) async {
      final (engine, log) = _home();
      final services = AppServices.inMemory();
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await _openExport(tester);
      expect(find.text('No backup yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('export-backup')));
      await tester.pumpAndSettle();

      final file = _saver(services).saved.entries.single;
      expect(file.key, endsWith('.budgetbackup'));

      // Only the budget's own key opens it, and it restores every Event.
      final key = await services.keys.keyFor(engine.state.budget!.id);
      final restored = await Backup.open(file.value, key);
      expect(
        restored.map((e) => e.toJson()),
        engine.events.map((e) => e.toJson()),
      );
      await expectLater(
        Backup.open(file.value, BudgetKey.generate()),
        throwsA(isA<BackupException>()),
      );

      // The key never entered the Event log.
      final logText = jsonEncode([for (final e in log.readAll()) e.toJson()]);
      expect(logText, isNot(contains(key.toHex())));

      // The screen and the saved date both note the backup.
      expect(find.textContaining('Last backup: '), findsOneWidget);
      expect(await services.prefs.readLastBackup(), isNotNull);
    });

    testWidgets('backing out of the file dialog is not a backup', (
      tester,
    ) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory();
      _saver(services).accepts = false;
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await _openExport(tester);

      await tester.tap(find.byKey(const ValueKey('export-backup')));
      await tester.pumpAndSettle();

      expect(find.text('No backup yet'), findsOneWidget);
      expect(await services.prefs.readLastBackup(), isNull);
    });
  });

  group('App lock', () {
    testWidgets('is off by default and the app opens straight in', (
      tester,
    ) async {
      final (engine, _) = _home();
      await tester.pumpWidget(BudgetApp(engine: engine));

      expect(find.text('Budget is locked'), findsNothing);
      expect(find.text('READY TO ASSIGN'), findsOneWidget);
    });

    testWidgets('turns on after the phone confirms it is you', (tester) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory();
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await _openAppLock(tester);

      await tester.tap(find.byKey(const ValueKey('app-lock-switch')));
      await tester.pumpAndSettle();

      // The screen lock counts as well as the fingerprint.
      expect(_auth(services).calls, [false]);
      expect(services.appLockEnabled.value, isTrue);
      expect(await services.prefs.readAppLockEnabled(), isTrue);
      // Turning it on doesn't lock the app you are using.
      expect(find.text('Budget is locked'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('On'), findsOneWidget);
    });

    testWidgets('stays off if the check fails', (tester) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory();
      _auth(services).succeeds = false;
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await _openAppLock(tester);

      await tester.tap(find.byKey(const ValueKey('app-lock-switch')));
      await tester.pumpAndSettle();

      expect(services.appLockEnabled.value, isFalse);
      expect(await services.prefs.readAppLockEnabled(), isFalse);
    });

    testWidgets('asks to set up a screen lock when the phone has none', (
      tester,
    ) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory();
      _auth(services).supported = false;
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await _openAppLock(tester);

      await tester.tap(find.byKey(const ValueKey('app-lock-switch')));
      await tester.pumpAndSettle();

      expect(services.appLockEnabled.value, isFalse);
      expect(
        find.textContaining('Set up a fingerprint or screen lock'),
        findsOneWidget,
      );
    });

    testWidgets('launches locked and unlocks with the fingerprint', (
      tester,
    ) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory()..appLockEnabled.value = true;
      final auth = _auth(services)..succeeds = false;
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await tester.pumpAndSettle();

      // The budget is covered, not shown behind the lock.
      expect(find.text('Budget is locked'), findsOneWidget);
      expect(find.text('READY TO ASSIGN'), findsNothing);

      auth.succeeds = true;
      await tester.tap(find.byIcon(Icons.fingerprint));
      await tester.pumpAndSettle();

      expect(auth.calls.last, isTrue); // fingerprint only
      expect(find.text('Budget is locked'), findsNothing);
      expect(find.text('READY TO ASSIGN'), findsOneWidget);
    });

    testWidgets('"Use screen lock" accepts the phone\'s screen lock', (
      tester,
    ) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory()..appLockEnabled.value = true;
      final auth = _auth(services)..succeeds = false;
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      await tester.pumpAndSettle();

      auth.succeeds = true;
      await tester.tap(find.text('Use screen lock'));
      await tester.pumpAndSettle();

      expect(auth.calls.last, isFalse);
      expect(find.text('READY TO ASSIGN'), findsOneWidget);
    });

    testWidgets('locks again when the app goes to the background', (
      tester,
    ) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory();
      final auth = _auth(services)..succeeds = false;
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));

      // Off: leaving the app changes nothing.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text('Budget is locked'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      services.appLockEnabled.value = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text('Budget is locked'), findsOneWidget);

      auth.succeeds = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Budget is locked'), findsNothing);
    });

    testWidgets('does not lock while the file dialog is open', (tester) async {
      final (engine, _) = _home();
      final services = AppServices.inMemory();
      await tester.pumpWidget(BudgetApp(engine: engine, services: services));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      services.appLockEnabled.value = true;

      await services.keepUnlocked(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
      });

      expect(find.text('Budget is locked'), findsNothing);
    });
  });
}
