import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/signup_request_model.dart';

class SignupRequestService {
  SignupRequestService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> submitRequest({
    required String companyName,
    required String ownerName,
    required String phone,
    required String email,
    String? address,
    String? notes,
  }) async {
    try {
      await _client.from('signup_requests').insert({
        'company_name': companyName,
        'owner_name': ownerName,
        'phone': phone,
        'email': email,
        'address': address,
        'notes': notes,
      });
    } catch (error) {
      throw Exception('Failed to submit signup request: $error');
    }
  }

  Future<List<SignupRequestModel>> getRequests() async {
    try {
      final data = await _client
          .from('signup_requests')
          .select()
          .order('created_at', ascending: false);

      return data.map(SignupRequestModel.fromMap).toList();
    } catch (error) {
      throw Exception('Failed to load signup requests: $error');
    }
  }

  Future<void> rejectRequest(int requestId) async {
    try {
      await _client
          .from('signup_requests')
          .update({
            'status': 'rejected',
            'approved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', requestId);
    } catch (error) {
      throw Exception('Failed to reject signup request: $error');
    }
  }

  Future<void> createCompanyWithUsers({
    int? requestId,
    required String companyName,
    required String adminFullName,
    required String adminEmail,
    required String adminPassword,
    String? employeeFullName,
    String? employeeEmail,
    String? employeePassword,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-company-user',
        body: {
          'request_id': requestId,
          'company_name': companyName,
          'admin': {
            'full_name': adminFullName,
            'email': adminEmail,
            'password': adminPassword,
          },
          if (_hasText(employeeFullName) &&
              _hasText(employeeEmail) &&
              _hasText(employeePassword))
            'employee': {
              'full_name': employeeFullName,
              'email': employeeEmail,
              'password': employeePassword,
            },
        },
      );

      if (response.status >= 400) {
        throw Exception(response.data);
      }
    } catch (error) {
      throw Exception('Failed to create company users: $error');
    }
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}
