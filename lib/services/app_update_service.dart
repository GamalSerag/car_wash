import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_update_policy.dart';
import '../core/offline_protocol.dart';
import 'offline_runtime.dart';
import 'offline_store.dart';
import 'offline_session_service.dart';

class AppUpdateService {
  AppUpdateService({this.client, this.store, this.session});
  final SupabaseClient? client;
  final OfflineStore? store;
  final OfflineSessionService? session;

  Future<AppUpdatePolicy?> checkForUpdate({bool requireOnline = false}) async {
    final info = await PackageInfo.fromPlatform();
    final build = int.parse(info.buildNumber);
    final backend = client ?? Supabase.instance.client;
    final cache = store ?? OfflineRuntime.store;
    try {
      if (!requireOnline &&
          OfflineRuntime.enabled &&
          !OfflineRuntime.online.value)
        throw TimeoutException('network offline');
      final data = await backend
          .from('app_update_policy')
          .select('enabled, minimum_build, update_url')
          .eq('platform', 'android')
          .single()
          .timeout(const Duration(seconds: 12));
      final policy = AppUpdatePolicy.fromMap(data);
      await cache?.put('update_policy', data);
      return policy.requiresUpdate(build) ? policy : null;
    } catch (error) {
      if (requireOnline || !isTransientOfflineError(error) || cache == null)
        rethrow;
      final saved = await cache.cache('update_policy');
      if (saved == null) rethrow;
      final policy = AppUpdatePolicy.fromMap(
        Map<String, dynamic>.from(saved['value'] as Map),
      );
      if (policy.requiresUpdate(build)) return policy;
      final age = DateTime.now().millisecondsSinceEpoch - (saved['at'] as int);
      final auth = session ?? OfflineRuntime.session;
      if (age < -const Duration(minutes: 5).inMilliseconds ||
          age > const Duration(days: 7).inMilliseconds ||
          auth == null ||
          !await auth.hasOfflineGrant(backend))
        rethrow;
      return null;
    }
  }
}
