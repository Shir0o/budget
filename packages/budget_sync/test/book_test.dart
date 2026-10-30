import 'package:budget_sync/budget_sync.dart';
import 'package:test/test.dart';

void main() {
  test('sync is off until it is turned on', () {
    expect(SyncBook.off.enabled, isFalse);
    expect(SyncBook.off.uploadedEvents, 0);
    expect(SyncBook.off.lastSync, isNull);
    expect(SyncBook.off.copyWith(enabled: true).enabled, isTrue);
  });

  test('round trips through secure storage', () {
    final book = SyncBook(
      enabled: true,
      uploadedEvents: 128,
      uploadedSeq: 3,
      snapshottedEvents: 120,
      devices: 2,
      lastSync: DateTime.fromMillisecondsSinceEpoch(1794000000000),
    );
    final back = SyncBook.fromJson(book.toJson());
    expect(back.enabled, isTrue);
    expect(back.uploadedEvents, 128);
    expect(back.uploadedSeq, 3);
    expect(back.snapshottedEvents, 120);
    expect(back.devices, 2);
    expect(back.lastSync, book.lastSync);
  });

  test('reads a book written by an older build', () {
    final back = SyncBook.fromJson({'enabled': true});
    expect(back.enabled, isTrue);
    expect(back.uploadedEvents, 0);
    expect(back.lastSync, isNull);
  });
}
