import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/offline_protocol.dart';
import '../core/supabase_config.dart';
import '../models/profile_model.dart';
import 'offline_store.dart';

class OfflineSessionService {
  OfflineSessionService(this.store);
  final OfflineStore store;
  late final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const key = 'maghsala.session.v1';
  static const grantLifetime = Duration(days: 7);

  Future<void> restore(SupabaseClient client) async {
    var raw = await _preferences.getString(key);
    if (raw == null) {
      final old = await SharedPreferences.getInstance();
      await old.reload();
      final legacy =
          'sb-${Uri.parse(SupabaseConfig.url).host.split('.').first}-auth-token';
      raw = old.getString(legacy);
      if (raw != null) {
        await _preferences.setString(key, raw);
        await old.remove(legacy);
      }
    }
    if (raw != null &&
        jsonEncode(client.auth.currentSession?.toJson()) != raw) {
      try {
        await client.auth.setInitialSession(raw);
      } on FormatException {
        await _preferences.remove(key);
      }
    } else if (raw == null && client.auth.currentSession != null) {
      try {
        await client.auth
            .signOut(scope: SignOutScope.local)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        /* Local removal precedes the network logout request. */
      }
    }
  }

  Future<int> epoch() async =>
      (await store.cache('session_epoch'))?['value'] as int? ?? 0;
  Future<void> advanceEpoch() async =>
      store.put('session_epoch', await epoch() + 1);

  Future<T> locked<T>(
    Future<T> Function() work, {
    String scope = 'auth',
  }) async {
    final owner = OfflineStore.uuid.v4();
    int? fence;
    for (var i = 0; i < 60 && fence == null; i++) {
      fence = await store.acquire(scope, owner);
      if (fence == null)
        await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (fence == null) throw TimeoutException('تعذر تأكيد الجلسة');
    try {
      return await work();
    } finally {
      await store.release(scope, owner, fence);
    }
  }

  Future<void> save(SupabaseClient client) async {
    final value = client.auth.currentSession;
    if (value != null)
      await _preferences.setString(key, jsonEncode(value.toJson()));
  }

  Future<void> ensure(SupabaseClient client, {String? expectedUser}) async {
    await locked(() async {
      await restore(client);
      final session = client.auth.currentSession;
      if (session == null ||
          (expectedUser != null && session.user.id != expectedUser)) {
        throw const AuthException('يرجى تسجيل الدخول للحساب صاحب العمليات');
      }
      if ((session.expiresAt ?? 0) * 1000 <
          DateTime.now()
              .add(const Duration(seconds: 60))
              .millisecondsSinceEpoch) {
        await client.auth.refreshSession().timeout(const Duration(seconds: 15));
        await save(client);
      }
    });
  }

  Future<void> clear(SupabaseClient client) async {
    await locked(() async {
      await advanceEpoch();
      await locked(() async {
        await _preferences.remove(key);
        try {
          await client.auth
              .signOut(scope: SignOutScope.local)
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          /* Local session and persistent credentials are already removed. */
        }
      }, scope: 'auth-network');
    });
  }

  Future<String?> rawSession() => _preferences.getString(key);
  Future<void> writeRawSession(String raw) => _preferences.setString(key, raw);

  Future<void> cacheProfile(ProfileModel profile) =>
      store.put('profile:${profile.id}', profile.toMap());

  Future<ProfileModel?> cachedProfile(
    String user, {
    bool allowExpired = false,
  }) async {
    final row = await store.cache('profile:$user');
    if (row == null) return null;
    final p = ProfileModel.fromMap(
      Map<String, dynamic>.from(row['value'] as Map),
    );
    if (p.id != user || p.companyId.isEmpty) return null;
    if (!p.canAccessApp) return p;
    final age = DateTime.now().millisecondsSinceEpoch - (row['at'] as int);
    if (age < -const Duration(minutes: 5).inMilliseconds) return null;
    if (p.role != 'employee' ||
        (!allowExpired && age > grantLifetime.inMilliseconds))
      return null;
    return p;
  }

  Future<ProfileModel?> loadProfile(SupabaseClient client) async {
    final id = client.auth.currentUser?.id;
    if (id == null) return null;
    final expectedEpoch = await epoch();
    try {
      if (!OfflineRuntimeAccess.isOnline())
        throw TimeoutException('network offline');
      await ensure(client, expectedUser: id);
      final data = await client
          .from('profiles')
          .select('*, companies(name, is_active)')
          .eq('id', id)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));
      if (client.auth.currentUser?.id != id || await epoch() != expectedEpoch)
        return null;
      if (data == null) {
        await store.remove('profile:$id');
        return null;
      }
      final p = ProfileModel.fromMap(data);
      await cacheProfile(p);
      return p;
    } catch (error) {
      if (!isTransientOfflineError(error)) rethrow;
      final cached = await cachedProfile(id);
      if (cached != null) return cached;
      throw StateError('يلزم اتصال بالإنترنت لتأكيد صلاحية الحساب');
    }
  }

  Future<bool> hasOfflineGrant(SupabaseClient client) async {
    final id = client.auth.currentUser?.id;
    if (id == null) return false;
    final p = await cachedProfile(id);
    return p != null && p.canAccessApp;
  }

  Future<void> prepareWorker(SupabaseClient client) => restore(client);
}

// Workers always verify against the server; the foreground runtime supplies connectivity.
class OfflineRuntimeAccess {
  static bool Function() isOnline = () => true;
}
