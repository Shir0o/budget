import 'dart:convert';

import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:test/test.dart';

/// A device's wall clock, which the test moves by hand so two devices can
/// edit "at the same time" in a known order.
final class _Clock {
  _Clock(this.ms);

  int ms;

  int call() => ms;
}

/// One simulated device: its own Event log, clock, engine and sync book.
final class _Device {
  _Device(this.deviceId, this.platform, {Iterable<Event> events = const []}) {
    if (events.isNotEmpty) log.append(events.toList());
    engine = BudgetEngine(
      log: log,
      deviceId: deviceId,
      actor: Actor.userAndroid,
      nowMs: clock.call,
    );
  }

  final String deviceId;
  final String platform;
  final log = InMemoryEventLog();
  final clock = _Clock(1000);
  late final BudgetEngine engine;
  var book = SyncBook.off;
}

/// A synthetic budget: Home, Checking at 4,210.55, Groceries and Dining out,
/// and three hand-entered transactions. Every amount is literal cents.
void _seed(_Device device) {
  final engine = device.engine;
  engine.execute(const CreateBudget(name: 'Home'));
  engine.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: const Money(421055),
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  engine.execute(const CreateCategoryGroup(name: 'Everyday'));
  final group = engine.state.categoryGroups.single;
  engine.execute(CreateCategory(groupId: group.id, name: 'Groceries'));
  engine.execute(CreateCategory(groupId: group.id, name: 'Dining out'));
  final account = engine.state.accounts.single;
  for (final (payee, cents, category) in [
    ('Corner Bistro', -4820, 'Groceries'),
    ('Landlord', -180000, 'Groceries'),
    ('Hardware', -3000, 'Groceries'),
  ]) {
    engine.execute(
      CreateTransaction(
        accountId: account.id,
        date: CivilDate(2026, 11, 12),
        payee: payee,
        amount: Money(cents),
        lines: [
          LineInput(
            amount: Money(cents),
            category: engine.state.categories
                .firstWhere((c) => c.name == category)
                .id,
            business: const Personal(),
          ),
        ],
      ),
    );
  }
}

String _category(_Device device, String name) =>
    device.engine.state.categories.firstWhere((c) => c.name == name).id;

Transaction _byPayee(_Device device, String payee) =>
    device.engine.state.transactions.firstWhere((t) => t.payee == payee);

final _november = CalendarMonth(2026, 11);

void main() {
  late InMemoryDrive drive;
  late SyncClient client;
  late BudgetKey key;
  late _Device a;
  late _Device b;
  late String budgetId;

  Future<SyncOutcome> sync(_Device device) async {
    final outcome = await client.sync(
      engine: device.engine,
      key: key,
      book: device.book,
      platform: device.platform,
    );
    expect(outcome.error, isNull);
    device.book = outcome.book;
    return outcome;
  }

  setUp(() async {
    drive = InMemoryDrive();
    client = SyncClient(drive: drive);
    key = BudgetKey.generate();
    a = _Device('device-a', 'mac');
    _seed(a);
    budgetId = a.engine.state.budget!.id;

    // The Mac turns sync on and writes everything to its own folder.
    await sync(a);

    // The phone pairs: it starts from the same log, as a backup restore or
    // ticket 12's QR pairing would leave it.
    b = _Device('device-b', 'android', events: a.engine.events);
    await sync(b);
  });

  group('Two devices editing offline', () {
    test('converge to the same projection and the same history', () async {
      final bistroId = _byPayee(a, 'Corner Bistro').id;
      final landlordId = _byPayee(a, 'Landlord').id;
      final hardwareId = _byPayee(a, 'Hardware').id;
      final groceries = _category(a, 'Groceries');
      final dining = _category(a, 'Dining out');

      // Offline, each device changes what it changes.
      a.clock.ms = 2000;
      a.engine.execute(
        EditTransaction(transactionId: bistroId, payee: 'Bistro'),
      );
      a.engine.execute(
        SetAssignment(
          categoryId: _category(a, 'Groceries'),
          month: _november,
          amount: const Money(5000),
        ),
      );
      a.clock.ms = 2500;
      a.engine.execute(EditTransaction(transactionId: bistroId, memo: 'Lunch'));
      a.clock.ms = 2600;
      a.engine.execute(DeleteTransaction(transactionId: landlordId));
      a.clock.ms = 2700;
      a.engine.execute(
        EditTransaction(
          transactionId: hardwareId,
          amount: const Money(-3000),
          lines: [
            LineInput(
              amount: const Money(-1000),
              category: groceries,
              business: const Personal(),
            ),
            LineInput(
              amount: const Money(-2000),
              category: dining,
              business: const Personal(),
            ),
          ],
        ),
      );

      b.clock.ms = 3000;
      b.engine.execute(
        EditTransaction(transactionId: bistroId, payee: 'Cafe Bistro'),
      );
      b.engine.execute(
        SetAssignment(
          categoryId: _category(b, 'Groceries'),
          month: _november,
          amount: const Money(3000),
        ),
      );
      b.clock.ms = 3100;
      b.engine.execute(
        EditTransaction(transactionId: landlordId, payee: 'Landlord LLC'),
      );
      b.clock.ms = 3200;
      b.engine.execute(
        EditTransaction(
          transactionId: hardwareId,
          amount: const Money(-3000),
          lines: [
            LineInput(
              amount: const Money(-2500),
              category: groceries,
              business: const Personal(),
            ),
            LineInput(
              amount: const Money(-500),
              category: dining,
              business: const Personal(),
            ),
          ],
        ),
      );

      // The Mac syncs, then the phone, then the Mac again.
      final mac = await sync(a);
      expect(mac.pulled, 0);
      expect(mac.pushed, greaterThan(0));
      final phone = await sync(b);
      expect(phone.pulled, greaterThan(0));
      expect(mac.others, isEmpty);
      final again = await sync(a);
      // The Mac now names what came from the phone, as its manifest says.
      expect(again.others, ['android']);

      // Both hold exactly the same Events.
      expect(
        b.engine.events.map((e) => e.id).toSet(),
        a.engine.events.map((e) => e.id).toSet(),
      );
      expect(b.engine.events, hasLength(a.engine.events.length));

      // Both project the same budget.
      expect(
        stateJson(b.engine.state, month: _november),
        stateJson(a.engine.state, month: _november),
      );

      // Field-level last writer wins: the phone's later payee stands, and
      // the Mac's memo on another field survives.
      expect(_byPayee(a, 'Cafe Bistro').memo, 'Lunch');
      expect(
        a.engine.state.transactions.any((t) => t.payee == 'Bistro'),
        isFalse,
      );

      // Assignments are deltas: 50.00 + 30.00, not one replacing the other.
      expect(
        a.engine.state.assigned(_category(a, 'Groceries'), _november).cents,
        8000,
      );

      // Delete beats a concurrent edit, and the edit stays in history.
      expect(
        a.engine.state.transactions.any((t) => t.payee == 'Landlord'),
        isFalse,
      );
      expect(
        a.engine.history.entries().any(
          (entry) => entry.summary.startsWith('Set payee of Landlord'),
        ),
        isTrue,
      );

      // Split lines are replaced as a whole, never mixed.
      final hardware = _byPayee(a, 'Hardware');
      expect(hardware.lines.map((l) => l.amount.cents), [-2500, -500]);
      expect(hardware.amount.cents, -3000);
    });

    test(
      'mark the losing values as overwritten by sync, on both sides',
      () async {
        a.clock.ms = 2000;
        a.engine.execute(
          EditTransaction(
            transactionId: _byPayee(a, 'Corner Bistro').id,
            payee: 'Bistro',
          ),
        );
        b.clock.ms = 3000;
        b.engine.execute(
          EditTransaction(
            transactionId: _byPayee(b, 'Corner Bistro').id,
            payee: 'Cafe Bistro',
          ),
        );

        await sync(a);
        await sync(b);
        await sync(a);

        for (final device in [a, b]) {
          final changes = [
            for (final entry in device.engine.history.entries())
              for (final change in entry.changes)
                if (change.note == overwrittenBySync) change,
          ];
          expect(changes, hasLength(1));
          expect(changes.single.label, 'Payee');
          // The value that lost is still visible, with the note.
          expect(changes.single.after, '“Bistro”');
          expect(changes.single.note, 'overwritten by sync');
          expect(changes.single.toString(), endsWith('(overwritten by sync)'));
        }
      },
    );
  });

  group('Drive layout', () {
    test('each device writes only its own folder, and names are ids', () async {
      final macFolder = drive.folderAt([budgetId, 'device-a']);
      final phoneFolder = drive.folderAt([budgetId, 'device-b']);
      expect(macFolder, isNotNull);
      expect(phoneFolder, isNotNull);
      for (final upload in drive.uploads) {
        // Each device's files land in the folder it made, never the other's
        // and never the budget folder.
        expect([macFolder, phoneFolder], contains(upload.folderId));
        expect(
          upload.name == DeviceManifest.fileName ||
              upload.name.startsWith('seg-') ||
              upload.name.startsWith('snap-'),
          isTrue,
          reason: '${upload.name} reveals more than an id',
        );
      }
      expect(drive.filesAt([budgetId, 'device-a']), contains('seg-000001.bin'));
      // The phone has no Events of its own yet, so it writes only its
      // manifest.
      expect(drive.filesAt([budgetId, 'device-b']), ['manifest.bin']);
    });

    test(
      'every file is sealed, so nothing readable leaves the device',
      () async {
        final bytes = drive.readBytes(
          path: [budgetId, 'device-a'],
          name: 'seg-000001.bin',
        )!;
        final text = utf8.decode(bytes, allowMalformed: true);
        expect(text, isNot(contains('Corner Bistro')));
        expect(text, isNot(contains('Home')));
        expect(text, isNot(contains('device-a')));
        // A sealed file still opens with the Budget Key.
        final body = await SealedFile.open(
          name: '$budgetId/device-a/seg-000001.bin',
          file: bytes,
          key: key,
        );
        expect(body['kind'], SyncFileKind.segment);
      },
    );

    test(
      'a snapshot compacts a device\'s own Events and still merges',
      () async {
        client = SyncClient(drive: drive, snapshotEvery: 2);
        final c = _Device('device-c', 'android', events: a.engine.events)
          ..book = SyncBook.off;
        await sync(c);
        c.clock.ms = 5000;
        c.engine.execute(
          EditTransaction(
            transactionId: _byPayee(c, 'Corner Bistro').id,
            memo: 'Coffee',
          ),
        );
        c.clock.ms = 5001;
        c.engine.execute(
          EditTransaction(
            transactionId: _byPayee(c, 'Hardware').id,
            memo: 'Bolts',
          ),
        );
        await sync(c);

        expect(
          drive
              .filesAt([budgetId, 'device-c'])
              .any((name) => name.startsWith('snap-')),
          isTrue,
        );

        final before = b.engine.events.length;
        await sync(b);
        expect(b.engine.events.length, greaterThan(before));
        await sync(a);
        expect(_byPayee(a, 'Corner Bistro').memo, 'Coffee');
        expect(_byPayee(a, 'Hardware').memo, 'Bolts');
        expect(
          stateJson(b.engine.state, month: _november),
          stateJson(a.engine.state, month: _november),
        );
      },
    );

    test('a wrong key is reported, not merged', () async {
      final outcome = await client.sync(
        engine: b.engine,
        key: BudgetKey.generate(),
        book: b.book,
      );
      expect(outcome.error, 'Wrong Budget Key, or the file was changed');
      expect(outcome.pulled, 0);
    });
  });

  group('Pairing', () {
    test('the QR code reads the whole budget and writes nothing', () async {
      // The phone has an Event of its own by the time the new device pairs.
      b.clock.ms = 2000;
      b.engine.execute(
        EditTransaction(
          transactionId: _byPayee(b, 'Hardware').id,
          memo: 'Bolts',
        ),
      );
      await sync(b);

      final code = PairingPayload(budgetId: budgetId, key: key).code;
      final scanned = PairingPayload.parse(code);
      final uploads = drive.uploads.length;

      final joined = await client.join(
        budgetId: scanned.budgetId,
        key: scanned.key,
      );

      expect(joined.error, isNull);
      expect(joined.devices, 2);
      expect(joined.events.map((event) => event.id).toSet(), {
        for (final event in [...a.engine.events, ...b.engine.events]) event.id,
      });
      expect(
        joined.events.first.hlc.compareTo(joined.events.last.hlc),
        lessThanOrEqualTo(0),
      );
      expect(drive.uploads, hasLength(uploads));

      // The Events are a whole budget a new device can open on its own.
      final fresh = BudgetEngine(
        log: InMemoryEventLog()..append(joined.events),
        deviceId: 'device-c',
        actor: Actor.userAndroid,
      );
      expect(fresh.state.budget!.id, budgetId);
      expect(fresh.state.budget!.name, 'Home');
      expect(
        fresh.state.transactions.firstWhere((t) => t.payee == 'Hardware').memo,
        'Bolts',
      );
    });

    test('a code that opens nothing is reported, not trusted', () async {
      final wrongKey = await client.join(
        budgetId: budgetId,
        key: BudgetKey.generate(),
      );
      expect(wrongKey.error, 'Wrong Budget Key, or the file was changed');
      expect(wrongKey.events, isEmpty);

      final noBudget = await client.join(budgetId: 'no-such-budget', key: key);
      expect(noBudget.error, 'No synced budget uses that code.');
    });
  });

  group('Key rotation', () {
    test('re-seals a fresh snapshot, deletes the old files and unpairs', () async {
      b.clock.ms = 2000;
      b.engine.execute(
        EditTransaction(
          transactionId: _byPayee(b, 'Corner Bistro').id,
          memo: 'Lunch',
        ),
      );
      await sync(b);
      await sync(a);
      final before = a.engine.events.length;

      final newKey = BudgetKey.generate();
      final rotation = await client.rotate(
        engine: a.engine,
        oldKey: key,
        newKey: newKey,
        book: a.book,
      );

      expect(rotation.error, isNull);
      expect(rotation.snapshotEvents, before);
      expect(rotation.deletedFiles, greaterThan(0));
      expect(rotation.book.uploadedEvents, greaterThan(0));
      expect(rotation.book.uploadedSeq, 0);

      // Every file the old key sealed is gone, the phone's folder included.
      expect(drive.filesAt([budgetId, 'device-b']), isEmpty);
      final names = drive.filesAt([budgetId, 'device-a']);
      expect(names.where((name) => name.startsWith('seg-')), isEmpty);
      final snapshotName = names.singleWhere(
        (name) => name.startsWith('snap-'),
      );

      // The fresh snapshot is the whole budget, and only the new key opens it.
      final bytes = drive.readBytes(
        path: [budgetId, 'device-a'],
        name: snapshotName,
      )!;
      final body = await SealedFile.open(
        name: '$budgetId/device-a/$snapshotName',
        file: bytes,
        key: newKey,
      );
      expect(
        readEvents(body).map((event) => event.id).toSet(),
        a.engine.events.map((event) => event.id).toSet(),
      );
      await expectLater(
        SealedFile.open(
          name: '$budgetId/device-a/$snapshotName',
          file: bytes,
          key: key,
        ),
        throwsA(isA<SyncException>()),
      );

      // The phone still holds the old key, so it is refused.
      final refused = await client.sync(
        engine: b.engine,
        key: key,
        book: b.book,
      );
      expect(refused.error, 'Wrong Budget Key, or the file was changed');
      expect(refused.pulled, 0);

      // Pairing again with the new code catches it up, under the new key.
      final joined = await client.join(budgetId: budgetId, key: newKey);
      expect(joined.error, isNull);
      b.engine.merge(joined.events);
      b.book = SyncBook(enabled: true);
      final phone = await client.sync(
        engine: b.engine,
        key: newKey,
        book: b.book,
      );
      expect(phone.error, isNull);
      b.book = phone.book;
      final mac = await client.sync(
        engine: a.engine,
        key: newKey,
        book: rotation.book,
      );
      expect(mac.error, isNull);
      expect(b.engine.events.length, a.engine.events.length);
      expect(
        stateJson(b.engine.state, month: _november),
        stateJson(a.engine.state, month: _november),
      );
    });

    test('a rotation with the wrong old key deletes nothing', () async {
      final before = [
        ...drive.filesAt([budgetId, 'device-a']),
        ...drive.filesAt([budgetId, 'device-b']),
      ]..sort();

      final outcome = await client.rotate(
        engine: a.engine,
        oldKey: BudgetKey.generate(),
        newKey: BudgetKey.generate(),
        book: a.book,
      );

      expect(outcome.error, 'That isn’t this budget’s current Budget Key.');
      expect(outcome.deletedFiles, 0);
      expect(
        [
          ...drive.filesAt([budgetId, 'device-a']),
          ...drive.filesAt([budgetId, 'device-b']),
        ]..sort(),
        before,
      );
    });
  });
}
