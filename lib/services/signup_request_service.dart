import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/input_limits.dart';

import '../models/signup_request_model.dart';

class CompanyCreationException implements Exception {
  const CompanyCreationException(this.message);

  final String message;

  @override
  String toString() => message;
}

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
    InputLimits.checkText(companyName, InputLimits.name);
    InputLimits.checkText(ownerName, InputLimits.name);
    InputLimits.checkText(phone, InputLimits.phone);
    InputLimits.checkText(email, InputLimits.email);
    InputLimits.checkText(address, InputLimits.address);
    InputLimits.checkText(notes, InputLimits.notes);
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
    InputLimits.checkText(companyName, InputLimits.name);
    InputLimits.checkText(adminFullName, InputLimits.name);
    InputLimits.checkText(adminEmail, InputLimits.email);
    InputLimits.checkText(adminPassword, InputLimits.password);
    InputLimits.checkText(employeeFullName, InputLimits.name);
    InputLimits.checkText(employeeEmail, InputLimits.email);
    InputLimits.checkText(employeePassword, InputLimits.password);
    final employeeValues = [employeeFullName, employeeEmail, employeePassword];
    if (employeeValues.any(_hasText) && !employeeValues.every(_hasText)) {
      throw const CompanyCreationException(
        'أكمل جميع بيانات الموظف أو اتركها فارغة',
      );
    }
    if (_client.auth.currentSession == null) {
      throw const CompanyCreationException(
        'انتهت جلسة الدخول. سجل الدخول مرة أخرى',
      );
    }

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
        throw CompanyCreationException(
          _creationError(response.data, response.status),
        );
      }
    } on FunctionException catch (error) {
      throw CompanyCreationException(
        _creationError(error.details, error.status),
      );
    }
  }

  String _creationError(dynamic data, int status) {
    if (data is Map && data['message'] is String) {
      final message = data['message'] as String;
      if (RegExp(r'[\u0600-\u06FF]').hasMatch(message)) {
        return message;
      }
    }
    if (status == 401) {
      return 'انتهت جلسة الدخول. سجل الدخول مرة أخرى';
    }
    if (status == 403) {
      return 'إنشاء الشركات متاح للمشرف العام النشط فقط';
    }
    return 'تعذر إنشاء الشركة أو الحسابات. تحقق من الاتصال وحاول مرة أخرى';
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}
