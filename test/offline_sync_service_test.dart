import 'dart:convert';
import 'package:car_wash/services/offline_runtime.dart';
import 'package:car_wash/services/offline_store.dart';
import 'package:car_wash/services/offline_session_service.dart';
import 'package:car_wash/services/offline_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'offline_test_support.dart';

void main() {
  late OfflineStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = await OfflineStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    OfflineRuntime.online.value = true;
  });
  tearDown(() async {
    await store.db.close();
    OfflineRuntime.error.value = null;
  });

  test(
    'ACK loss resumes the same frozen manifest and reconciles server receipts without new sales',
    () async {
      final accepted = <String, Map<String, dynamic>>{};
      final staged = <String, Map<String, dynamic>>{};
      final batchIds = <String>{};
      var lost = true;
      var prepared = false;
      var expectedCount = 0;
      final client = await offlineTestClient(
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/profiles'))
            return http.Response(
              jsonEncode(offlineTestProfile()),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          if (path.endsWith('/sale_sync_items'))
            return http.Response(
              jsonEncode(accepted.values.toList()),
              200,
              request: request,
            );
          expect(prepared, isTrue);
          final params = jsonDecode(request.body) as Map;
          if (params['batch_id'] != null)
            batchIds.add(params['batch_id'] as String);
          if (path.endsWith('/begin_offline_sale_batch'))
            expectedCount =
                (params['metadata'] as Map)['expected_order_count'] as int;
          if (path.endsWith('/stage_offline_sale_chunk')) {
            for (final raw in params['items'] as List) {
              final item = Map<String, dynamic>.from(raw as Map);
              staged[item['id'] as String] = item;
            }
          }
          if (path.endsWith('/process_offline_sale_batch')) {
            for (final id in staged.keys) {
              accepted.putIfAbsent(
                id,
                () => {
                  'id': id,
                  'state': 'accepted',
                  'sale_id': accepted.length + 1,
                  'error_code': null,
                },
              );
            }
            if (lost) {
              lost = false;
              throw Exception('SocketException: response lost after commit');
            }
            return http.Response(
              jsonEncode({'completed': true, 'results': <dynamic>[]}),
              200,
              request: request,
            );
          }
          return http.Response('{"ok":true}', 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      final session = OfflineSessionService(store);
      for (var i = 0; i < 11; i++) {
        await store.enqueue(testUser, testCompany, {
          'vehicle_type_id': 1,
          'price_cents': 10000,
          'created_at': '2026-11-01T10:00:00.000Z',
        });
      }
      final service = OfflineSyncService(
        client,
        store,
        session,
        prepareSession: () async {
          prepared = true;
        },
        updateRequired: () async => false,
      );
      await expectLater(service.run(manual: true), throwsException);
      expect(
        (await store.rows(
          testUser,
          testCompany,
        )).every((e) => e.state == 'frozen'),
        isTrue,
      );
      await service.run(manual: true);
      expect(expectedCount, 11);
      expect(batchIds.length, 1);
      expect(accepted.length, 11);
      expect(
        (await store.rows(
          testUser,
          testCompany,
        )).every((e) => e.state == 'synced'),
        isTrue,
      );
      expect(await store.freeze(testUser, testCompany), isNull);
    },
  );

  test(
    'A known required update prevents batch creation and preserves pending data',
    () async {
      var remoteWrites = 0;
      final client = await offlineTestClient(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') remoteWrites++;
          return http.Response(
            jsonEncode(offlineTestProfile()),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await store.enqueue(testUser, testCompany, {
        'vehicle_type_id': 1,
        'price_cents': 10000,
        'created_at': '2026-11-01T10:00:00Z',
      });
      final service = OfflineSyncService(
        client,
        store,
        OfflineSessionService(store),
        prepareSession: () async {},
        updateRequired: () async => true,
      );
      await expectLater(service.run(manual: true), throwsStateError);
      expect(remoteWrites, 0);
      expect((await store.rows(testUser, testCompany)).single.canEdit, isTrue);
    },
  );

  test(
    'Lease already held by another worker prevents any network operation',
    () async {
      var calls = 0;
      final client = await offlineTestClient(
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.dispose);
      await store.acquire('sales-sync', 'background-worker');
      await OfflineSyncService(
        client,
        store,
        OfflineSessionService(store),
        prepareSession: () async {},
      ).run();
      expect(calls, 0);
    },
  );
}
