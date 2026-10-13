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
  static String? _registeredTopic;

  Future<void> registerCurrentDevice({String? role, String? companyId}) async {
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

    if (_registeredUserId != user.id) {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
        unawaited(_saveToken(user.id, token, companyId));
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
      await messaging.unsubscribeFromTopic('super_admins');
      await messaging.unsubscribeFromTopic('admins');
      await messaging.unsubscribeFromTopic('employees');
      final topic = _registeredTopic;
      if (topic != null) {
        await messaging.unsubscribeFromTopic(topic);
      }
    } catch (_) {
      // Ignore logout cleanup failures.
    } finally {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      _registeredUserId = null;
      _registeredTopic = null;
    }
  }

  Future<void> _saveToken(
    String userId,
    String token,
    String? companyId,
  ) async {
    await _client.from('device_tokens').upsert({
      'user_id': userId,
      if (companyId != null && companyId.isNotEmpty) 'company_id': companyId,
      'token': token,
      'platform': _platformName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  Future<void> _syncTopicSubscription(
    FirebaseMessaging messaging,
    String? role,
    String? companyId,
  ) async {
    final topic = _topicFor(role, companyId);
    if (topic == null || _registeredTopic == topic) {
      return;
    }

    await messaging.unsubscribeFromTopic('admins');
    await messaging.unsubscribeFromTopic('employees');
    final registeredTopic = _registeredTopic;
    if (registeredTopic != null) {
      await messaging.unsubscribeFromTopic(registeredTopic);
    }
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
