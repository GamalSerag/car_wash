import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sale_model.dart';

class SalesService {
  SalesService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<SaleModel> createSale({
    required int vehicleTypeId,
    String? vehicleName,
    String? plateNumber,
    required double price,
    required String employeeId,
    String? notes,
  }) async {
    try {
      final data = await _client
          .from('sales')
          .insert({
            'vehicle_type_id': vehicleTypeId,
            'vehicle_name': vehicleName,
            'plate_number': plateNumber,
            'price': price,
            'employee_id': employeeId,
            'notes': notes,
          })
          .select(_salesSelect)
          .single();

      return SaleModel.fromMap(data);
    } catch (error) {
      throw Exception('Failed to create sale: $error');
    }
  }

  Future<SaleModel> updateSale({
    required int id,
    required int vehicleTypeId,
    String? vehicleName,
    String? plateNumber,
    required double price,
    String? notes,
  }) async {
    try {
      final data = await _client
          .from('sales')
          .update({
            'vehicle_type_id': vehicleTypeId,
            'vehicle_name': vehicleName,
            'plate_number': plateNumber,
            'price': price,
            'notes': notes,
          })
          .eq('id', id)
          .select(_salesSelect)
          .single();

      return SaleModel.fromMap(data);
    } catch (error) {
      throw Exception('Failed to update sale: $error');
    }
  }

  Future<void> deleteSale(int id) async {
    try {
      await _client.from('sales').delete().eq('id', id);
    } catch (error) {
      throw Exception('Failed to delete sale: $error');
    }
  }

  Future<List<SaleModel>> getTodaySales() async {
    try {
      final data = await _client
          .from('sales')
          .select(_salesSelect)
          .gte('created_at', _todayStart().toIso8601String())
          .lt('created_at', _tomorrowStart().toIso8601String())
          .order('created_at', ascending: false);

      return data.map(SaleModel.fromMap).toList();
    } catch (error) {
      throw Exception('Failed to get today sales: $error');
    }
  }

  Future<double> getTodayTotal() async {
    try {
      final sales = await getTodaySales();
      return sales.fold<double>(0, (total, sale) => total + sale.price);
    } catch (error) {
      throw Exception('Failed to get today total: $error');
    }
  }

  Future<List<SaleModel>> getRecentSales({int limit = 20}) async {
    try {
      final data = await _client
          .from('sales')
          .select(_salesSelect)
          .order('created_at', ascending: false)
          .limit(limit);

      return data.map(SaleModel.fromMap).toList();
    } catch (error) {
      throw Exception('Failed to get recent sales: $error');
    }
  }

  Future<List<SaleModel>> getAllSales() async {
    try {
      final data = await _client
          .from('sales')
          .select(_salesSelect)
          .order('created_at', ascending: false);

      return data.map(SaleModel.fromMap).toList();
    } catch (error) {
      throw Exception('Failed to get all sales: $error');
    }
  }

  Future<List<SaleModel>> getPreviousSales() async {
    try {
      final data = await _client
          .from('sales')
          .select(_salesSelect)
          .lt('created_at', _todayStart().toIso8601String())
          .order('created_at', ascending: false);

      return data.map(SaleModel.fromMap).toList();
    } catch (error) {
      throw Exception('Failed to get previous sales: $error');
    }
  }

  DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _tomorrowStart() {
    return _todayStart().add(const Duration(days: 1));
  }

  static const String _salesSelect = '''
    *,
    vehicle_types(name, icon_name),
    profiles(full_name)
  ''';
}
