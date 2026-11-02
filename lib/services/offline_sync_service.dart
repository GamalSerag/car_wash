import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/offline_protocol.dart';

import '../models/profile_model.dart';
import 'app_update_service.dart';
import 'offline_runtime.dart';
import 'offline_session_service.dart';
import 'offline_store.dart';

class OfflineSyncService {
  OfflineSyncService(
    this.client,
    this.store,
    this.session, {
    this.prepareSession,
    this.updateRequired,
  });
  final SupabaseClient client;
  final OfflineStore store;
  final OfflineSessionService session;
  final Future<void> Function()? prepareSession;
  final Future<bool> Function()? updateRequired;
  bool _running = false;

  Future<Map<String, dynamic>> rpc(
    String name,
    Map<String, dynamic> args,
  ) async => Map<String, dynamic>.from(
    await client.rpc(name, params: args).timeout(const Duration(seconds: 15))
        as Map,
  );

  Future<void> run({bool manual = false}) async {
    if (_running || !OfflineRuntime.online.value) return;
    _running = true;
    try {
      await _run(manual: manual);
    } finally {
      _running = false;
    }
  }

  Future<void> _run({required bool manual}) async {
    final user = client.auth.currentUser?.id;
    if (user == null) return;
    final retry = await store.cache('sync_retry:$user');
    final retryData = retry?['value'] as Map?;
    if (!manual &&
        retryData != null &&
        ((retryData['attempts'] as int) >= 8 ||
            (retryData['next'] as int) > DateTime.now().millisecondsSinceEpoch))
      return;
    final epoch = await session.epoch();
    final owner = OfflineStore.uuid.v4();
    final fence = await store.acquire('sales-sync', owner);
    if (fence == null) {
      return;
    }
    var leaseValid = true;
    final renewal = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        leaseValid = await store.renew('sales-sync', owner, fence);
      } catch (_) {
        leaseValid = false;
      }
    });
    Future<void> verify() async {
      if (!leaseValid ||
          await session.epoch() != epoch ||
          client.auth.currentUser?.id != user) {
        throw StateError('تغيرت الجلسة أثناء المزامنة');
      }
    }

    OfflineRuntime.syncing.value = true;
    try {
      if (prepareSession != null) {
        await prepareSession!();
      } else {
        await session.ensure(client, expectedUser: user);
      }
      final raw = await client
          .from('profiles')
          .select('*, companies(name, is_active)')
          .eq('id', user)
          .single()
          .timeout(const Duration(seconds: 12));
      final p = ProfileModel.fromMap(raw);
      await verify();
      await session.cacheProfile(p);
      if (!p.canAccessApp)
        throw const AuthException('تم إيقاف الحساب أو اشتراك الشركة');
      if (p.role != 'employee' && (await store.rows(user, p.companyId)).isEmpty)
        return;
      final needsUpdate = updateRequired != null
          ? await updateRequired!()
          : await AppUpdateService(
                  client: client,
                  store: store,
                  session: session,
                ).checkForUpdate(requireOnline: true) !=
                null;
      if (needsUpdate) {
        throw StateError('يلزم تحديث التطبيق قبل المزامنة');
      }
      await verify();
      OfflineRuntime.backendAvailable = true;
      final started = Stopwatch()..start();
      final rows = await store.rows(user, p.companyId);
      for (final row in rows.where((e) => e.state == 'uncertain')) {
        if (started.elapsed.inSeconds >= 40) return;
        await verify();
        final attempted = await store.cache('attempt:${row.localId}');
        if (attempted != null) {
          final receipt = await client
              .from('sale_sync_receipts')
              .select('outcome, sale_id, error_code')
              .eq('company_id', p.companyId)
              .eq('client_operation_id', row.localId)
              .maybeSingle()
              .timeout(const Duration(seconds: 15));
          if (receipt != null) {
            if (receipt['outcome'] == 'accepted') {
              await store.reconcileOnline(
                row.localId,
                receipt['sale_id'] as int,
              );
            } else {
              await store.mark(
                row.localId,
                'failed',
                error: receipt['error_code'] as String?,
              );
            }
          } else {
            await store.mark(row.localId, 'pending');
          }
        } else {
          await store.put('attempt:${row.localId}', true);
          final result = await rpc('submit_online_sale', {
            'operation_id': row.localId,
            'payload': row.payload,
          });
          await store.reconcileOnline(row.localId, result['sale_id'] as int);
        }
      }
      while (started.elapsed.inSeconds < 40) {
        await verify();
        final batch = await store.freeze(user, p.companyId);
        if (batch == null) break;
        final device =
            (await store.cache('device_id'))?['value'] as String? ??
            OfflineStore.uuid.v4();
        await store.put('device_id', device);
        await rpc('begin_offline_sale_batch', {
          'batch_id': batch.id,
          'metadata': {
            'device_id': device,
            'expected_order_count': batch.orderCount,
            'expected_item_count': batch.items.length,
            'expected_action_count': batch.actions.length,
            'manifest_hash': batch.manifestHash,
          },
        });
        final progressKey = 'stage_progress:${batch.id}';
        final savedProgress =
            (await store.cache(progressKey))?['value'] as Map?;
        final progress = <String, dynamic>{
          'items': 0,
          'actions': 0,
          'results': 0,
          'sealed': false,
          if (savedProgress != null)
            ...Map<String, dynamic>.from(savedProgress),
        };
        Future<bool> stage(
          String kind,
          List<Map<String, dynamic>> values,
        ) async {
          var index = 0;
          for (final page in pages(values)) {
            if (index++ < (progress[kind] as int)) continue;
            await verify();
            await rpc('stage_offline_sale_chunk', {
              'batch_id': batch.id,
              'items': kind == 'items' ? page : <dynamic>[],
              'actions': kind == 'actions' ? page : <dynamic>[],
            });
            progress[kind] = index;
            await store.put(progressKey, progress);
            if (started.elapsed.inSeconds >= 40) return false;
          }
          return true;
        }

        if (progress['sealed'] != true) {
          if (!await stage('items', batch.items) ||
              !await stage('actions', batch.actions))
            return;
          await rpc('seal_offline_sale_batch', {'batch_id': batch.id});
          progress['sealed'] = true;
          await store.put(progressKey, progress);
        }
        var completed = false;
        do {
          await verify();
          final result = await rpc('process_offline_sale_batch', {
            'batch_id': batch.id,
            'limit_count': 50,
          });
          await verify();
          completed = result['completed'] == true;
          await store.applyResults(
            batch.id,
            result['results'] as List? ?? [],
            false,
          );
          if (started.elapsed.inSeconds >= 40) break;
        } while (!completed);
        if (!completed) break;
        // Recover acknowledgements lost during earlier process requests.
        for (var offset = progress['results'] as int; ; offset += 100) {
          await verify();
          final data = await client
              .from('sale_sync_items')
              .select('id:client_operation_id, state, sale_id, error_code')
              .eq('batch_id', batch.id)
              .order('client_operation_id')
              .range(offset, offset + 99)
              .timeout(const Duration(seconds: 15));
          await store.applyResults(batch.id, data, false);
          progress['results'] = offset + 100;
          await store.put(progressKey, progress);
          if (data.length < 100) break;
          if (started.elapsed.inSeconds >= 40) return;
        }
        await store.applyResults(batch.id, [], true);
        await store.remove(progressKey);
      }
      await store.remove('sync_retry:$user');
      OfflineRuntime.error.value = null;
    } catch (error) {
      if (isTransientOfflineError(error)) {
        OfflineRuntime.backendAvailable = false;
        await store.retainUnattemptedAsOffline(user);
      }
      final attempts = (retryData?['attempts'] as int? ?? 0) + 1;
      final delay = (5 * (1 << attempts.clamp(0, 6))).clamp(5, 300);
      await store.put('sync_retry:$user', {
        'attempts': attempts,
        'next': DateTime.now()
            .add(Duration(seconds: delay))
            .millisecondsSinceEpoch,
      });
      if (client.auth.currentUser?.id == user && await session.epoch() == epoch)
        OfflineRuntime.error.value = error is AuthException
            ? error.message
            : 'تعذر إتمام المزامنة. العمليات محفوظة على الهاتف. تحقق من الاتصال والصلاحيات';
      rethrow;
    } finally {
      renewal.cancel();
      try {
        await store.release('sales-sync', owner, fence);
      } finally {
        OfflineRuntime.syncing.value = false;
        OfflineRuntime.changed();
      }
    }
  }

  static Iterable<List<Map<String, dynamic>>> pages(
    List<Map<String, dynamic>> values,
  ) sync* {
    var page = <Map<String, dynamic>>[];
    for (final value in values) {
      if (utf8.encode(jsonEncode(value)).length > 120000)
        throw StateError('العملية أكبر من حد الرفع');
      if (page.length >= 50 ||
          utf8.encode(jsonEncode([...page, value])).length > 128 * 1024) {
        yield page;
        page = [];
      }
      page.add(value);
    }
    if (page.isNotEmpty) yield page;
  }
}
