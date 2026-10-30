import 'package:budget/app.dart';
import 'package:budget/budget_library.dart';
import 'package:budget/services.dart';
import 'package:budget/widgets.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:budget/screens/pair_device_screen.dart';

/// A synthetic budget: Home, with a Checking account of 4,210.55.
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
  }

  final log = InMemoryEventLog();
  late final engine = BudgetEngine(
    log: log,
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
}

/// The device's services, sharing [drive] with another device when a test
/// pairs two of them.
AppServices _services([DriveGateway? drive]) => AppServices(
  keys: InMemoryBudgetKeyStore(),
  prefs: InMemoryDevicePrefs(),
  saver: InMemoryFileSaver(),
  authenticator: FakeAuthenticator(),
  drive: drive ?? InMemoryDrive(),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

Future<void> _openSync(WidgetTester tester) async {
  await _openSettings(tester);
  await _tap(tester, find.text('Encrypted sync'));
}

/// Turns sync on and dismisses the phrase it shows once.
Future<void> _turnOnSync(WidgetTester tester) async {
  await _openSync(tester);
  await _tap(tester, find.byKey(const ValueKey('turn-on-sync')));
  await tester.pageBack();
  await tester.pumpAndSettle();
}

/// The 24 words as they are on screen.
List<String> _wordsOnScreen(WidgetTester tester) => [
  for (final element
      in find
          .descendant(
            of: find.byKey(const ValueKey('recovery-words')),
            matching: find.byType(Text),
          )
          .evaluate())
    (element.widget as Text).data!,
].where((text) => !RegExp(r'^\d+$').hasMatch(text)).toList();

void main() {
  testWidgets('the pairing QR carries the key and the Drive budget id', (
    tester,
  ) async {
    final seed = _Seed();
    final services = _services();
    final budgetId = seed.engine.state.budget!.id;
    await tester.pumpWidget(BudgetApp(engine: seed.engine, services: services));
    await _turnOnSync(tester);

    await _tap(tester, find.byKey(const ValueKey('pair-device')));

    final payload = tester.widget<PairingQr>(find.byType(PairingQr)).payload;
    // The square draws exactly that payload's code.
    expect(find.byType(QrImageView), findsOneWidget);
    expect(payload.budgetId, budgetId);
    expect(payload.key.toHex(), (await services.keys.keyFor(budgetId)).toHex());
    // The code on screen is the same thing the QR holds, and it names no key.
    expect(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('pairing-code')))
          .data,
      payload.code,
    );
    expect(payload.code, isNot(contains(payload.key.toHex())));
  });

  testWidgets('a new device joins the budget from that code', (tester) async {
    final seed = _Seed();
    final first = _services();
    await tester.pumpWidget(BudgetApp(engine: seed.engine, services: first));
    await _turnOnSync(tester);
    await _tap(tester, find.byKey(const ValueKey('pair-device')));
    final code = tester.widget<PairingQr>(find.byType(PairingQr)).payload.code;

    // The other device has no budget at all yet.
    final second = _services(first.drive);
    final draft = BudgetEngine(
      log: InMemoryEventLog(),
      deviceId: 'phone',
      actor: Actor.userAndroid,
    );
    // A fresh key, so the second device starts with its own blank tree. The
    // library shares the device's preferences, as the real app's does.
    await tester.pumpWidget(
      BudgetApp(
        key: const ValueKey('second-device'),
        library: BudgetLibrary.single(draft, prefs: second.prefs),
        services: second,
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('join-from-welcome')));

    await tester.enterText(find.byKey(const ValueKey('pairing-code')), code);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('join-budget')));

    // The joined budget opens, with its own money already in it.
    expect(find.text('READY TO ASSIGN'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text(r'$4,210.55'), findsOneWidget);

    final payload = PairingPayload.parse(code);
    expect(await second.prefs.readBudgetIds(), [payload.budgetId]);
    expect(
      (await second.keys.keyFor(payload.budgetId)).toHex(),
      payload.key.toHex(),
    );
  });

  testWidgets('a code that opens nothing is refused, and says so', (
    tester,
  ) async {
    final seed = _Seed();
    final services = _services();
    await tester.pumpWidget(BudgetApp(engine: seed.engine, services: services));
    await _openSettings(tester);
    await _tap(tester, find.text('Join a device’s budget'));

    await tester.enterText(
      find.byKey(const ValueKey('pairing-code')),
      'budget://pair?v=1&budget=nothing&key=AAAA',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('join-budget')));

    expect(find.byKey(const ValueKey('join-problem')), findsOneWidget);
    expect(find.text('That isn’t a budget pairing code'), findsOneWidget);
    // Nothing was joined.
    expect(await services.prefs.readBudgetIds(), isEmpty);
  });

  testWidgets('the phrase is shown again only after the fingerprint', (
    tester,
  ) async {
    final seed = _Seed();
    final services = _services();
    final auth = services.authenticator as FakeAuthenticator;
    final budgetId = seed.engine.state.budget!.id;
    // Sync setup creates the key; the phrase screen only reads it.
    await services.keys.keyFor(budgetId);
    await tester.pumpWidget(BudgetApp(engine: seed.engine, services: services));
    await _openSettings(tester);

    auth.succeeds = false;
    await _tap(tester, find.text('Recovery phrase'));
    expect(find.byKey(const ValueKey('recovery-words')), findsNothing);
    expect(
      find.textContaining('only shown after your fingerprint'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    auth.succeeds = true;
    await _tap(tester, find.text('Recovery phrase'));
    final words = _wordsOnScreen(tester);
    expect(words, hasLength(RecoveryPhrase.wordCount));
    // The words spell this budget's key, and no other.
    expect(
      (await RecoveryPhrase.parse(words)).key.toHex(),
      (await services.keys.keyFor(budgetId)).toHex(),
    );
    // Only the fingerprint counts, never the phone's screen lock.
    expect(auth.calls, [true, true]);
  });

  testWidgets('rotating re-seals Drive, deletes the old files and unpairs', (
    tester,
  ) async {
    final seed = _Seed();
    final services = _services();
    await tester.pumpWidget(BudgetApp(engine: seed.engine, services: services));
    await _turnOnSync(tester);

    final budgetId = seed.engine.state.budget!.id;
    final oldKey = await services.keys.keyFor(budgetId);
    final drive = services.drive as InMemoryDrive;
    final path = [budgetId, 'test-device'];
    expect(
      drive.filesAt(path).where((name) => name.startsWith('seg-')),
      isNotEmpty,
    );

    await _tap(tester, find.byKey(const ValueKey('rotate-key')));
    await tester.tap(find.text('Rotate'));
    await tester.pumpAndSettle();

    // The new phrase is shown at once, and it isn't the old key.
    final newKey = (await RecoveryPhrase.parse(_wordsOnScreen(tester))).key;
    expect(newKey.toHex(), isNot(oldKey.toHex()));
    expect((await services.keys.keyFor(budgetId)).toHex(), newKey.toHex());
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Every segment the old key sealed is gone, and a snapshot holds them all.
    final names = drive.filesAt(path);
    expect(names.where((name) => name.startsWith('seg-')), isEmpty);
    final snapshot = names.singleWhere((name) => name.startsWith('snap-'));
    final bytes = drive.readBytes(path: path, name: snapshot)!;
    final body = await SealedFile.open(
      name: '$budgetId/test-device/$snapshot',
      file: bytes,
      key: newKey,
    );
    expect(readEvents(body), hasLength(seed.engine.events.length));
    await expectLater(
      SealedFile.open(
        name: '$budgetId/test-device/$snapshot',
        file: bytes,
        key: oldKey,
      ),
      throwsA(isA<SyncException>()),
    );

    // The screen says the other device has to pair again.
    await tester.scrollUntilVisible(
      find.textContaining('must pair again'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('must pair again'), findsOneWidget);
  });
}
