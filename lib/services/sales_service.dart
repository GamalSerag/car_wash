import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/input_limits.dart';

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
    String? clientOperationId,
    DateTime? createdAt,
  }) async {
    InputLimits.checkAmount(price);
    InputLimits.checkText(vehicleName, InputLimits.name);
    InputLimits.checkText(plateNumber, InputLimits.plate);
    InputLimits.checkText(notes, InputLimits.notes);
    if (price <= 0) throw ArgumentError('السعر يجب أن يكون أكبر من صفر');
    if (_client.auth.currentUser?.id != employeeId)
      throw const AuthException('لا يمكن التسجيل باسم موظف آخر');
    try {
      final result = Map<String, dynamic>.from(
        await _client.rpc(
              'submit_online_sale',
              params: {
                'operation_id': clientOperationId ?? const Uuid().v4(),
                'payload': {
                  'vehicle_type_id': vehicleTypeId,
                  'vehicle_name': vehicleName,
                  'plate_number': plateNumber,
                  'price_cents': (price * 100).round(),
                  'notes': notes,
                  'created_at': (createdAt ?? DateTime.now())
                      .toUtc()
                      .toIso8601String(),
                },
              },
            )
            as Map,
      );
      final data = result['sale'];
      if (data is! Map)
        throw StateError(
          'هذه العملية محفوظة سابقًا أو حُذفت. راجع قائمة المبيعات',
        );
      return SaleModel.fromMap(Map<String, dynamic>.from(data));
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
    InputLimits.checkAmount(price);
    InputLimits.checkText(vehicleName, InputLimits.name);
    InputLimits.checkText(plateNumber, InputLimits.plate);
    InputLimits.checkText(notes, InputLimits.notes);
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
          .gte('created_at', _todayStart().toUtc().toIso8601String())
          .lt('created_at', _tomorrowStart().toUtc().toIso8601String())
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
          .lt('created_at', _todayStart().toUtc().toIso8601String())
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
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }

  static const String _salesSelect = '''
    *,
    vehicle_types(name, icon_name),
    profiles(full_name)
  ''';
}
