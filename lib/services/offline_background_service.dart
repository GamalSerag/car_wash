import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../core/supabase_config.dart';
import 'offline_store.dart';
import 'offline_session_service.dart';
import 'offline_sync_service.dart';
import 'coordinated_auth_client.dart';

@pragma('vm:entry-point')
void offlineCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final store = await OfflineStore.open();
    final session = OfflineSessionService(store);
    late final SupabaseClient client;
    client = SupabaseClient(
      SupabaseConfig.url,
      SupabaseConfig.publishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: CoordinatedAuthClient(
        session,
        () => client.auth.currentUser?.id,
      ),
    );
    try {
      await session.prepareWorker(client);
      if (client.auth.currentUser?.id != input?['user'] ||
          await session.epoch() != input?['epoch'])
        return true;
      await OfflineSyncService(client, store, session).run();
      final retry =
          (await store.cache('sync_retry:${input?['user']}'))?['value'] as Map?;
      if ((retry?['attempts'] as int? ?? 0) >= 8) return true;
      final rows = await store.rows(
        input!['user'] as String,
        input['company'] as String,
      );
      return !await store.hasUnsentActivity(
            input['user'] as String,
            input['company'] as String,
          ) &&
          !rows.any(
            (e) => ['pending', 'frozen', 'uncertain'].contains(e.state),
          );
    } catch (_) {
      return false;
    } finally {
      await client.dispose();
      await store.db.close();
    }
  });
}

class OfflineBackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(offlineCallbackDispatcher);
  }

  static Future<void> schedule(String user, String company, int epoch) async {
    final input = <String, dynamic>{
      'user': user,
      'company': company,
      'epoch': epoch,
    };
    await Workmanager().registerOneOffTask(
      'sales-$user-$company-$epoch',
      'offline-sales',
      inputData: input,
      tag: 'offline-sales-$user',
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
    await Workmanager().registerPeriodicTask(
      'sales-recovery-$user-$company-$epoch',
      'offline-sales',
      inputData: input,
      tag: 'offline-sales-$user',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> cancelUser(String user) =>
      Workmanager().cancelByTag('offline-sales-$user');
}
