import 'dart:io';

import 'package:car_wash/services/offline_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late OfflineStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = await OfflineStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() => store.db.close());

  Map<String, dynamic> payload(int cents) => {
    'vehicle_type_id': 1,
    'price_cents': cents,
    'created_at': '2026-11-01T10:00:00.000Z',
  };

  test(
    'Enqueue commits one UUID and journal atomically; owner cache is isolated',
    () async {
      final sale = await store.enqueue('user-a', 'company-a', payload(12345));
      expect(sale.localId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(sale.priceCents, 12345);
      expect(await store.rows('user-b', 'company-a'), isEmpty);
      expect(await store.rows('user-a', 'company-b'), isEmpty);
      expect((await store.db.query('activity')).length, 1);
    },
  );

  test(
    'Pending edits and cancellations journal all versions without multiplying sales',
    () async {
      var sale = await store.enqueue('u', 'c', payload(10000));
      await store.edit(sale, payload(15000));
      await expectLater(store.edit(sale, payload(17000)), throwsStateError);
      sale = (await store.rows('u', 'c')).single;
      await store.edit(sale, sale.payload, cancel: true);
      expect((await store.rows('u', 'c')).single.countsAsSale, isFalse);
      final batch = await store.freeze('u', 'c');
      expect(batch!.orderCount, 0);
      expect(await store.hasUnsentActivity('u', 'c'), isTrue);
      expect(batch.actions.map((e) => e['kind']), ['create', 'edit', 'cancel']);
      await store.applyResults(batch.id, [], true);
      expect(await store.hasUnsentActivity('u', 'c'), isFalse);
    },
  );

  test(
    'Freezing preserves manifest/threshold through transport retries and prevents edit',
    () async {
      for (var i = 0; i < 11; i++) {
        await store.enqueue('u', 'c', payload(10000 + i));
      }
      final batch = (await store.freeze('u', 'c'))!;
      final again = (await store.freeze('u', 'c'))!;
      expect(batch.id, again.id);
      expect(batch.manifestHash, again.manifestHash);
      expect(batch.orderCount, 11);
      final row = (await store.rows('u', 'c')).first;
      expect(row.canEdit, isFalse);
      await expectLater(store.edit(row, payload(1)), throwsStateError);
    },
  );

  test(
    'Server results are idempotent; next episode gets a distinct identity',
    () async {
      final sale = await store.enqueue('u', 'c', payload(10000));
      final batch = (await store.freeze('u', 'c'))!;
      final result = [
        {
          'id': sale.localId,
          'state': 'accepted',
          'sale_id': 17,
          'error_code': null,
        },
      ];
      await store.applyResults(batch.id, result, true);
      await store.applyResults(batch.id, result, true);
      final confirmed = (await store.rows('u', 'c')).single;
      expect(confirmed.state, 'synced');
      expect(confirmed.serverId, 17);
      expect(await store.freeze('u', 'c'), isNull);
      await store.enqueue('u', 'c', payload(9000));
      expect((await store.freeze('u', 'c'))!.id, isNot(batch.id));
    },
  );

  test(
    'Lease acquisition is exclusive and fencing rejects stale releases',
    () async {
      final fence = (await store.acquire('sync', 'first'))!;
      expect(await store.acquire('sync', 'second'), isNull);
      await store.release('sync', 'second', fence);
      expect(await store.acquire('sync', 'second'), isNull);
      await store.release('sync', 'first', fence);
      final second = (await store.acquire('sync', 'second'))!;
      expect(second, greaterThan(fence));
      expect(await store.renew('sync', 'first', fence), isFalse);
    },
  );

  test('Disk transaction failure never leaves an orphaned sale', () async {
    await store.db.execute(
      "CREATE TRIGGER reject_activity BEFORE INSERT ON activity BEGIN SELECT RAISE(ABORT,'disk write rejected'); END",
    );
    await expectLater(
      store.enqueue('u', 'c', payload(10000)),
      throwsA(isA<DatabaseException>()),
    );
    expect(await store.rows('u', 'c'), isEmpty);
  });

  test(
    'Closing a background connection does not close the foreground database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'maghsala-offline-connections-',
      );
      final path = '${directory.path}/queue.db';
      final foreground = await OfflineStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      try {
        final sale = await foreground.enqueue('u', 'c', payload(10000));
        final worker = await OfflineStore.open(
          factory: databaseFactoryFfi,
          path: path,
        );
        try {
          expect(worker.db, isNot(same(foreground.db)));
          expect((await worker.rows('u', 'c')).single.localId, sale.localId);
          final lease = (await worker.acquire('sync', 'worker'))!;
          expect(await foreground.acquire('sync', 'foreground'), isNull);
          await worker.release('sync', 'worker', lease);
        } finally {
          await worker.db.close();
        }
        expect(foreground.db.isOpen, isTrue);
        expect((await foreground.rows('u', 'c')).single.localId, sale.localId);
        await foreground.put('session_epoch', 2);
        expect((await foreground.cache('session_epoch'))!['value'], 2);
        expect(await foreground.acquire('sync', 'foreground'), isNotNull);
      } finally {
        await foreground.db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'Queue survives reopening a file database with identical batch membership',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'maghsala-offline-test-',
      );
      final path = '${directory.path}/queue.db';
      final first = await OfflineStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      await first.enqueue('u', 'c', payload(100));
      final batch = (await first.freeze('u', 'c'))!;
      await first.db.close();
      final second = await OfflineStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect((await second.freeze('u', 'c'))!.manifestHash, batch.manifestHash);
      expect((await second.rows('u', 'c')).single.state, 'frozen');
      await second.db.close();
      await directory.delete(recursive: true);
    },
  );
}
