import 'package:car_wash/models/profile_model.dart';
import 'package:car_wash/services/offline_store.dart';
import 'package:car_wash/services/offline_session_service.dart';
import 'package:car_wash/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'offline_test_support.dart';

void main() {
  late OfflineStore store;
  late OfflineSessionService session;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = await OfflineStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = OfflineSessionService(store);
    OfflineRuntimeAccess.isOnline = () => false;
    PackageInfo.setMockInitialValues(
      appName: 'car_wash',
      packageName: 'com.maghsala.car_wash',
      version: '1.0.9',
      buildNumber: '11',
      buildSignature: '',
    );
  });
  tearDown(() async {
    await store.db.close();
    OfflineRuntimeAccess.isOnline = () => true;
  });

  test(
    'Cold start admits only the previously verified employee of the same identity',
    () async {
      final client = await offlineTestClient();
      addTearDown(client.dispose);
      expect(await session.hasOfflineGrant(client), isFalse);
      await session.cacheProfile(ProfileModel.fromMap(offlineTestProfile()));
      expect(await session.hasOfflineGrant(client), isTrue);
      expect((await session.loadProfile(client))!.fullName, 'موظف اختبار');
      expect(await session.cachedProfile('other-user'), isNull);
    },
  );
  test('Expired offline grant cannot be extended by a local read', () async {
    await session.cacheProfile(ProfileModel.fromMap(offlineTestProfile()));
    await store.db.update('cache', {
      'at': DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch,
    });
    expect(await session.cachedProfile(testUser), isNull);
  });
  test(
    'Known company suspension remains denied even without internet',
    () async {
      await session.cacheProfile(
        ProfileModel.fromMap(offlineTestProfile(active: false)),
      );
      final client = await offlineTestClient();
      addTearDown(client.dispose);
      expect(await session.hasOfflineGrant(client), isFalse);
      expect((await session.loadProfile(client))!.canAccessApp, isFalse);
    },
  );
  test(
    'Cached allowed update policy plus grant permits offline; known required update blocks',
    () async {
      final client = await offlineTestClient(
        httpClient: MockClient(
          (_) async => throw Exception('SocketException: offline'),
        ),
      );
      addTearDown(client.dispose);
      final service = AppUpdateService(
        client: client,
        store: store,
        session: session,
      );
      await session.cacheProfile(ProfileModel.fromMap(offlineTestProfile()));
      await expectLater(service.checkForUpdate(), throwsException);
      await store.put('update_policy', {
        'enabled': true,
        'minimum_build': 11,
        'update_url':
            'https://play.google.com/store/apps/details?id=com.maghsala.car_wash',
      });
      expect(await service.checkForUpdate(), isNull);
      await store.put('update_policy', {
        'enabled': true,
        'minimum_build': 12,
        'update_url':
            'https://play.google.com/store/apps/details?id=com.maghsala.car_wash',
      });
      expect((await service.checkForUpdate())!.minimumBuild, 12);
      await expectLater(
        service.checkForUpdate(requireOnline: true),
        throwsException,
      );
    },
  );
}
