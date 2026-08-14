import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';

class AuthService {
  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
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
    try {
      final user = getCurrentUser();
      if (user == null) {
        return null;
      }

      final data = await _client
          .from('profiles')
          .select()
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
