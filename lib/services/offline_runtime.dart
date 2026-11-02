import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_store.dart';
import 'offline_session_service.dart';

class OfflineRuntime {
  static OfflineStore? store;
  static OfflineSessionService? session;
  static final ValueNotifier<int> changes = ValueNotifier(0);
  static final ValueNotifier<bool> online = ValueNotifier(true);
  static bool backendAvailable = true;
  static final ValueNotifier<bool> syncing = ValueNotifier(false);
  static final ValueNotifier<String?> error = ValueNotifier(null);
  static Future<void> Function()? sync;
  static Future<void> Function()? manualSync;
  static Future<void> Function()? schedule;
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get enabled => store != null;
  static StreamSubscription<InternetStatus>? _network;
  static Timer? _retry;
  static bool owns(SupabaseClient client) =>
      enabled && identical(client, Supabase.instance.client);
  static void changed() {
    changes.value++;
  }

  static Future<void> initialize() async {
    if (!supported || enabled) return;
    store = await OfflineStore.open();
    session = OfflineSessionService(store!);
    OfflineRuntimeAccess.isOnline = () => online.value;
    try {
      online.value = await InternetConnection().hasInternetAccess.timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      online.value = false;
    }
  }

  static void watch() {
    if (!enabled || _network != null) return;
    _network = InternetConnection().onStatusChange.listen((status) async {
      online.value = status == InternetStatus.connected;
      if (!online.value) {
        backendAvailable = false;
        final user = Supabase.instance.client.auth.currentUser?.id;
        if (user != null) {
          try {
            await store!.retainUnattemptedAsOffline(user);
          } catch (_) {
            /* The next sync also reconciles uncertain requests. */
          }
        }
      }
      changed();
      if (online.value) requestSync();
    });
    _retry = Timer.periodic(const Duration(minutes: 1), (_) => requestSync());
    requestSync();
  }

  static void requestSync() {
    if (sync != null)
      unawaited(
        sync!().catchError((Object e, StackTrace stack) {
          diagnose('sync', e, stack);
          error.value = 'تعذر إتمام المزامنة. ستبقى العمليات محفوظة على الهاتف';
        }),
      );
  }

  static void diagnose(String operation, Object error, StackTrace stack) {
    if (!kDebugMode) return;
    final code = error is PostgrestException ? ' (${error.code})' : '';
    debugPrint('Offline $operation: ${error.runtimeType}$code');
    debugPrintStack(stackTrace: stack, maxFrames: 12);
  }

  static Future<void> dispose() async {
    _retry?.cancel();
    await _network?.cancel();
    _network = null;
  }
}
