import 'package:car_wash/models/profile_model.dart';
import 'package:car_wash/models/vehicle_type_model.dart';
import 'package:car_wash/services/offline_runtime.dart';
import 'package:car_wash/services/offline_store.dart';
import 'package:car_wash/services/offline_session_service.dart';
import 'package:car_wash/services/offline_sales_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_test_support.dart';

void main() {
  late OfflineStore store;
  late SupabaseClient client;
  late OfflineSalesRepository repo;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = await OfflineStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    client = await offlineTestClient();
    final session = OfflineSessionService(store);
    await session.cacheProfile(ProfileModel.fromMap(offlineTestProfile()));
    repo = OfflineSalesRepository(client, store, session);
    OfflineRuntime.online.value = false;
  });
  tearDown(() async {
    await client.dispose();
    await store.db.close();
    OfflineRuntime.online.value = true;
  });
  VehicleTypeModel type({String company = testCompany}) => VehicleTypeModel(
    id: 1,
    companyId: company,
    name: 'سيارة',
    price: 200,
    isActive: true,
    createdAt: DateTime.now(),
  );

  test(
    'Offline sale is immediately durable with exact cents and original timestamp',
    () async {
      final sale = await repo.create(type: type(), price: 123.45);
      expect(sale.state, 'pending');
      expect(sale.priceCents, 12345);
      expect((await repo.pending()).single.localId, sale.localId);
      final before = sale.createdAt;
      await repo.edit(sale, type(), 150, 'سيارة', null, null);
      expect((await repo.pending()).single.createdAt, before);
      expect((await repo.pending()).single.priceCents, 15000);
    },
  );
  test(
    'Invalid amount, foreign type and suspended grant never enqueue financial data',
    () async {
      await expectLater(
        repo.create(type: type(), price: 0),
        throwsArgumentError,
      );
      await expectLater(
        repo.create(type: type(company: 'another-company'), price: 200),
        throwsStateError,
      );
      await repo.session.cacheProfile(
        ProfileModel.fromMap(offlineTestProfile(active: false)),
      );
      await expectLater(
        repo.create(type: type(), price: 200),
        throwsStateError,
      );
      expect(await store.rows(testUser, testCompany), isEmpty);
    },
  );
  test(
    'Acknowledged online operation removes its offline journal and cannot be replayed in a batch',
    () async {
      final sale = await repo.create(type: type(), price: 100);
      await store.reconcileOnline(sale.localId, 42);
      expect(await store.freeze(testUser, testCompany), isNull);
      expect(await repo.pending(), isEmpty);
      expect((await repo.today(refresh: false)).single.id, 42);
    },
  );
  test(
    'Cancelled pending sale stays in audit but not the employee pending sales list',
    () async {
      final sale = await repo.create(type: type(), price: 100);
      await repo.cancel(sale);
      expect(await repo.pending(), isEmpty);
      expect((await store.freeze(testUser, testCompany))!.orderCount, 0);
    },
  );
}
