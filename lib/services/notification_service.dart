import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_navigation.dart';
import '../models/profile_model.dart';
import '../screens/offline_sync_report_screen.dart';
import 'package:flutter/material.dart';

class NotificationService {
  NotificationService({FirebaseMessaging? messaging, SupabaseClient? client})
    : _messaging = messaging,
      _client = client ?? Supabase.instance.client;

  final FirebaseMessaging? _messaging;
  final SupabaseClient _client;

  static StreamSubscription<String>? _tokenRefreshSubscription;
  static String? _registeredUserId;
  static String? _registeredTopic;
  static StreamSubscription<RemoteMessage>? _openSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static Map<String, dynamic>? _pendingReport;
  static bool _readInitial = false;
  static String? _lastOpenedEvent;

  static void showPendingReport(ProfileModel profile) {
    final data = _pendingReport;
    if (data == null) return;
    if (data['company_id'] != profile.companyId ||
        !profile.canAccessApp ||
        !profile.isAdmin) {
      _pendingReport = null;
      return;
    }
    final id = data['batch_id']?.toString();
    if (id == null || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
      _pendingReport = null;
      return;
    }
    final nav = AppNavigation.navigatorKey.currentState;
    if (nav == null) return;
    _pendingReport = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Supabase.instance.client.auth.currentUser?.id != profile.id) return;
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => OfflineSyncReportScreen(batchId: id),
        ),
      );
    });
  }

  Future<void> _openMessage(RemoteMessage message) async {
    if (message.data['type'] != 'offline_sale_summary') return;
    final event = message.data['event_id']?.toString();
    if (event != null && event == _lastOpenedEvent) return;
    _lastOpenedEvent = event;
    _pendingReport = message.data;
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final raw = await _client
          .from('profiles')
          .select('*, companies(name,is_active)')
          .eq('id', user.id)
          .single();
      if (_client.auth.currentUser?.id == user.id)
        showPendingReport(ProfileModel.fromMap(raw));
    } catch (_) {
      /* Auth gate can open the pending report after reconnect/login. */
    }
  }

  Future<void> registerCurrentDevice({String? role, String? companyId}) async {
    if (!_supportsFirebaseMessaging) {
      return;
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }

    final messaging = _messaging ?? FirebaseMessaging.instance;
    _openSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _openMessage,
    );
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'offline_sale_summary') {
        final context = AppNavigation.navigatorKey.currentContext;
        if (context != null)
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: const Text('تمت مزامنة عمليات مسجلة بدون إنترنت'),
              action: SnackBarAction(
                label: 'عرض الملخص',
                onPressed: () => _openMessage(message),
              ),
            ),
          );
      }
    });
    if (!_readInitial) {
      _readInitial = true;
      final initial = await messaging.getInitialMessage();
      if (initial != null) await _openMessage(initial);
    }

    try {
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
    } catch (_) {
      return;
    }

    try {
      if (_client.auth.currentUser?.id != user.id) return;
      await _syncTopicSubscription(messaging, role, companyId);
    } catch (_) {
      // Notifications should never block login or normal sales work.
    }

    try {
      final token = await messaging.getToken();
      if (token != null) {
        await _saveToken(user.id, token, companyId);
      }
    } catch (_) {
      // Token storage is useful for future direct sends, but topics can work
      // without storing the token in Supabase.
    }

    if (_client.auth.currentUser?.id != user.id) return;
    if (_registeredUserId != user.id) {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
        unawaited(
          _saveToken(user.id, token, companyId).catchError((Object _) {}),
        );
      });
      _registeredUserId = user.id;
    }
  }

  Future<void> removeCurrentDevice() async {
    _pendingReport = null;
    _lastOpenedEvent = null;
    if (!_supportsFirebaseMessaging) {
      return;
    }

    final oldUser = _client.auth.currentUser?.id;
    final oldTopic = _registeredTopic;
    final oldSubscription = _tokenRefreshSubscription;
    _tokenRefreshSubscription = null;
    _registeredUserId = null;
    _registeredTopic = null;
    await oldSubscription?.cancel();
    try {
      final messaging = _messaging ?? FirebaseMessaging.instance;
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 2),
      );
      if (token != null && oldUser != null) {
        await _client
            .from('device_tokens')
            .delete()
            .eq('token', token)
            .eq('user_id', oldUser)
            .timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      // Ignore logout cleanup failures.
    }
    try {
      final messaging = _messaging ?? FirebaseMessaging.instance;
      for (final topic in {
        'super_admins',
        'admins',
        'employees',
        if (oldTopic != null) oldTopic,
      }) {
        try {
          await messaging
              .unsubscribeFromTopic(topic)
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          // Continue cleanup even if one topic cannot be removed.
        }
      }
    } finally {
      // A new login may already own the static subscription; do not clear it here.
    }
  }

  Future<void> _saveToken(
    String userId,
    String token,
    String? companyId,
  ) async {
    if (_client.auth.currentUser?.id != userId) return;
    await _client.rpc(
      'register_current_device',
      params: {'device_token': token, 'device_platform': _platformName},
    );
  }

  Future<void> _syncTopicSubscription(
    FirebaseMessaging messaging,
    String? role,
    String? companyId,
  ) async {
    final topic = _topicFor(role, companyId);
    final expectedUser = _client.auth.currentUser?.id;
    if (topic == null || _registeredTopic == topic) {
      return;
    }

    await messaging.unsubscribeFromTopic('admins');
    await messaging.unsubscribeFromTopic('employees');
    if (topic != 'super_admins')
      await messaging.unsubscribeFromTopic('super_admins');
    final registeredTopic = _registeredTopic;
    if (registeredTopic != null) {
      await messaging.unsubscribeFromTopic(registeredTopic);
    }
    if (_client.auth.currentUser?.id != expectedUser) return;
    await messaging.subscribeToTopic(topic);
    _registeredTopic = topic;
  }

  String? _topicFor(String? role, String? companyId) {
    if (role == 'super_admin') {
      return 'super_admins';
    }

    if (companyId == null || companyId.isEmpty) {
      return null;
    }

    final safeCompanyId = companyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final audience = role == 'admin' ? 'admins' : 'employees';
    return 'company_${safeCompanyId}_$audience';
  }

  bool get _supportsFirebaseMessaging {
    if (kIsWeb) {
      return false;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  String get _platformName {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}
