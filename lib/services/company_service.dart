import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/input_limits.dart';

import '../models/company_model.dart';

class CompanyService {
  CompanyService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _columns = 'id, name, is_active, created_at';

  Future<List<CompanyModel>> getCompanies() async {
    final data = await _client
        .from('companies')
        .select(_columns)
        .order('created_at', ascending: false);
    return data.map(CompanyModel.fromMap).toList();
  }

  Future<CompanyModel> updateCompany({
    required String id,
    String? name,
    bool? isActive,
  }) async {
    InputLimits.checkText(name, InputLimits.name);
    if (name != null && name.trim().isEmpty) {
      throw ArgumentError('Company name is required');
    }
    final updates = {
      if (name != null) 'name': name.trim(),
      if (isActive != null) 'is_active': isActive,
    };
    if (updates.isEmpty) throw ArgumentError('No company changes supplied');
    final data = await _client
        .from('companies')
        .update(updates)
        .eq('id', id)
        .select(_columns)
        .single();
    return CompanyModel.fromMap(data);
  }
}
