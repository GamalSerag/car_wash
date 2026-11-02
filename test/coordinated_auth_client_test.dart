import 'dart:convert';
import 'package:car_wash/services/coordinated_auth_client.dart';
import 'package:car_wash/services/offline_store.dart';
import 'package:car_wash/services/offline_session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_test_support.dart';

class MemorySession extends OfflineSessionService {
  MemorySession(super.store);
  String? raw;
  @override
  Future<String?> rawSession() async => raw;
  @override
  Future<void> writeRawSession(String value) async {
    raw = value;
  }
}

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
  http.Request refresh() => http.Request(
    'POST',
    Uri.parse('https://example.invalid/auth/v1/token?grant_type=refresh_token'),
  )..body = '{"refresh_token":"old-token"}';
  Future<Map<String, dynamic>> expiredSession() async {
    final client = await offlineTestClient();
    final data = client.auth.currentSession!.toJson();
    await client.dispose();
    String b64(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    data['access_token'] =
        '${b64({'alg': 'HS256'})}.${b64({'sub': testUser, 'exp': 1})}.test';
    return data;
  }

  test(
    'Concurrent refresh callers spend one token and share the latest disk session',
    () async {
      final session = MemorySession(store)
        ..raw = jsonEncode(await expiredSession());
      final fresh = await offlineTestClient();
      final next = fresh.auth.currentSession!.toJson();
      await fresh.dispose();
      var calls = 0;
      final transport = CoordinatedAuthClient(
        session,
        () => testUser,
        inner: MockClient((_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(
            jsonEncode(next),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(transport.close);
      final results = await Future.wait([
        transport.send(refresh()).then(http.Response.fromStream),
        transport.send(refresh()).then(http.Response.fromStream),
      ]);
      expect(calls, 1);
      expect(results.every((r) => r.statusCode == 200), isTrue);
      expect(
        Session.fromJson(
          jsonDecode(session.raw!) as Map<String, dynamic>,
        )!.isExpired,
        isFalse,
      );
    },
  );

  test(
    'Account change during refresh cannot overwrite the saved session',
    () async {
      final session = MemorySession(store)
        ..raw = jsonEncode(await expiredSession());
      final before = session.raw;
      final fresh = await offlineTestClient();
      final next = fresh.auth.currentSession!.toJson();
      await fresh.dispose();
      final transport = CoordinatedAuthClient(
        session,
        () => testUser,
        inner: MockClient((_) async {
          await session.advanceEpoch();
          return http.Response(jsonEncode(next), 200);
        }),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.send(refresh()),
        throwsA(isA<AuthException>()),
      );
      expect(session.raw, before);
    },
  );
}
