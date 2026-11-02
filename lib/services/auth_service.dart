import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/input_limits.dart';

import '../models/profile_model.dart';
import 'offline_runtime.dart';
import 'offline_background_service.dart';

class AuthService {
  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    InputLimits.checkText(email, InputLimits.email);
    InputLimits.checkText(password, InputLimits.password);
    if (OfflineRuntime.owns(_client)) {
      return OfflineRuntime.session!.locked(() async {
        await OfflineRuntime.session!.advanceEpoch();
        final response = await _client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        await OfflineRuntime.session!.save(_client);
        final user = response.user?.id;
        if (user != null)
          await OfflineRuntime.store!.remove('sync_retry:$user');
        OfflineRuntime.error.value = null;
        OfflineRuntime.backendAvailable = true;
        return response;
      });
    }
    try {
      return await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException {
      rethrow;
    } catch (error) {
      throw Exception('Failed to sign in: $error');
    }
  }

  Future<void> signOut() async {
    if (OfflineRuntime.owns(_client)) {
      final user = _client.auth.currentUser?.id;
      await OfflineRuntime.session!.clear(_client);
      OfflineRuntime.error.value = null;
      if (user != null) {
        try {
          await OfflineBackgroundService.cancelUser(user);
        } catch (_) {
          /* Epoch still prevents old tasks from uploading. */
        }
      }
      OfflineRuntime.changed();
      return;
    }
    try {
      await _client.auth.signOut();
    } on AuthException {
      rethrow;
    } catch (error) {
      throw Exception('Failed to sign out: $error');
    }
  }

  User? getCurrentUser() {
    try {
      return _client.auth.currentUser;
    } catch (error) {
      throw Exception('Failed to get current user: $error');
    }
  }

  Future<ProfileModel?> getCurrentProfile() async {
    if (OfflineRuntime.owns(_client)) {
      return OfflineRuntime.session!.loadProfile(_client);
    }
    try {
      final user = getCurrentUser();
      if (user == null) {
        return null;
      }

      final data = await _client
          .from('profiles')
          .select('*, companies(name, is_active)')
          .eq('id', user.id)
          .maybeSingle();

      if (data == null) {
        return null;
      }

      return ProfileModel.fromMap(data);
    } on PostgrestException {
      rethrow;
    } catch (error) {
      throw Exception('Failed to get current profile: $error');
    }
  }
}
