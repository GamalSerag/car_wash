import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  NotificationService({FirebaseMessaging? messaging, SupabaseClient? client})
    : _messaging = messaging,
      _client = client ?? Supabase.instance.client;

  final FirebaseMessaging? _messaging;
  final SupabaseClient _client;

  static StreamSubscription<String>? _tokenRefreshSubscription;
  static String? _registeredUserId;
  static String? _registeredRole;

  Future<void> registerCurrentDevice({String? role}) async {
    if (!_supportsFirebaseMessaging) {
      return;
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }

    final messaging = _messaging ?? FirebaseMessaging.instance;

    try {
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
    } catch (_) {
      return;
    }

    try {
      await _syncTopicSubscription(messaging, role);
    } catch (_) {
      // Notifications should never block login or normal sales work.
    }

    try {
      final token = await messaging.getToken();
      if (token != null) {
        await _saveToken(user.id, token);
      }
    } catch (_) {
      // Token storage is useful for future direct sends, but topics can work
      // without storing the token in Supabase.
    }

    if (_registeredUserId != user.id) {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
        unawaited(_saveToken(user.id, token));
      });
      _registeredUserId = user.id;
    }
  }

  Future<void> removeCurrentDevice() async {
    if (!_supportsFirebaseMessaging) {
      return;
    }

    try {
      final messaging = _messaging ?? FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null) {
        await _client.from('device_tokens').delete().eq('token', token);
      }
      await messaging.unsubscribeFromTopic('admins');
      await messaging.unsubscribeFromTopic('employees');
    } catch (_) {
      // Ignore logout cleanup failures.
    } finally {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      _registeredUserId = null;
      _registeredRole = null;
    }
  }

  Future<void> _saveToken(String userId, String token) async {
    await _client.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': _platformName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  Future<void> _syncTopicSubscription(
    FirebaseMessaging messaging,
    String? role,
  ) async {
    final topic = role == 'admin' ? 'admins' : 'employees';
    if (_registeredRole == topic) {
      return;
    }

    await messaging.unsubscribeFromTopic('admins');
    await messaging.unsubscribeFromTopic('employees');
    await messaging.subscribeToTopic(topic);
    _registeredRole = topic;
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
