import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input_limits.dart';
import '../core/offline_protocol.dart';
import '../models/local_sale.dart';
import '../models/profile_model.dart';
import '../models/sale_model.dart';
import '../models/vehicle_type_model.dart';
import 'offline_runtime.dart';
import 'offline_session_service.dart';
import 'offline_store.dart';

class OfflineSalesRepository {
  OfflineSalesRepository(this.client, this.store, this.session);
  final SupabaseClient client;
  final OfflineStore store;
  final OfflineSessionService session;
  static const select =
      '*, vehicle_types(name, icon_name), profiles(full_name)';

  Future<ProfileModel> profile() async {
    final id = client.auth.currentUser?.id;
    if (id == null) throw const AuthException('يرجى تسجيل الدخول');
    final p = await session.cachedProfile(id);
    if (p == null || !p.canAccessApp || p.role != 'employee') {
      throw StateError('يلزم الاتصال بالإنترنت لتأكيد صلاحية الحساب');
    }
    return p;
  }

  Future<LocalSale> create({
    required VehicleTypeModel type,
    required double price,
    String? vehicleName,
    String? plateNumber,
    String? notes,
  }) async {
    validate(price, vehicleName, plateNumber, notes);
    final p = await profile();
    if (type.companyId != p.companyId || !type.isActive)
      throw StateError('نوع المركبة غير متاح');
    final sale = await store.enqueue(
      p.id,
      p.companyId,
      {
        'vehicle_type_id': type.id,
        'vehicle_type_name': type.name,
        'vehicle_type_icon_name': type.iconName,
        'employee_name': p.fullName,
        'price_cents': (price * 100).round(),
        'vehicle_name': vehicleName,
        'plate_number': plateNumber,
        'notes': notes,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      online: OfflineRuntime.online.value && OfflineRuntime.backendAvailable,
    );
    OfflineRuntime.changed();
    try {
      await OfflineRuntime.schedule?.call();
    } catch (_) {
      /* Foreground sync can still recover. */
    }
    OfflineRuntime.requestSync();
    return sale;
  }

  static void validate(
    double price,
    String? name,
    String? plate,
    String? notes,
  ) {
    InputLimits.checkAmount(price);
    if (price <= 0) throw ArgumentError('السعر يجب أن يكون أكبر من صفر');
    InputLimits.checkText(name, InputLimits.name);
    InputLimits.checkText(plate, InputLimits.plate);
    InputLimits.checkText(notes, InputLimits.notes);
  }

  Future<void> edit(
    LocalSale sale,
    VehicleTypeModel type,
    double price,
    String? name,
    String? plate,
    String? notes,
  ) async {
    validate(price, name, plate, notes);
    final p = await profile();
    if (sale.userId != p.id ||
        sale.companyId != p.companyId ||
        type.companyId != p.companyId ||
        !type.isActive) {
      throw StateError('لا يمكن تعديل هذه العملية');
    }
    await store.edit(sale, {
      ...sale.payload,
      'vehicle_type_id': type.id,
      'vehicle_type_name': type.name,
      'vehicle_type_icon_name': type.iconName,
      'price_cents': (price * 100).round(),
      'vehicle_name': name,
      'plate_number': plate,
      'notes': notes,
    });
    OfflineRuntime.changed();
  }

  Future<void> cancel(LocalSale sale) async {
    final p = await profile();
    if (p.id != sale.userId || p.companyId != sale.companyId)
      throw StateError('لا توجد صلاحية');
    await store.edit(sale, sale.payload, cancel: true);
    OfflineRuntime.changed();
  }

  Future<List<SaleModel>> today({bool refresh = true}) async {
    final p = await profile();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day + 1);
    final key = 'sales:${p.id}:${p.companyId}:${start.toIso8601String()}';
    if (refresh && OfflineRuntime.online.value) {
      try {
        await session.ensure(client, expectedUser: p.id);
        final data = await client
            .from('sales')
            .select(select)
            .gte('created_at', start.toUtc().toIso8601String())
            .lt('created_at', end.toUtc().toIso8601String())
            .eq('employee_id', p.id)
            .eq('company_id', p.companyId)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 12));
        if (client.auth.currentUser?.id == p.id) await store.put(key, data);
      } catch (error) {
        if (!isTransientOfflineError(error)) rethrow;
      }
    }
    final cache = await store.cache(key);
    final sales = ((cache?['value'] as List?) ?? [])
        .map((e) => SaleModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    for (final local in await store.rows(p.id, p.companyId)) {
      if (local.state == 'synced' &&
          !local.createdAt.isBefore(start.toUtc()) &&
          local.createdAt.isBefore(end.toUtc()) &&
          (local.ackAt ?? 0) > (cache?['at'] as int? ?? 0) &&
          !sales.any(
            (sale) =>
                sale.clientOperationId == local.localId ||
                sale.id == local.serverId,
          ))
        sales.add(local.displaySale);
    }
    return sales..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<LocalSale>> pending() async {
    final p = await profile();
    return (await store.rows(
        p.id,
        p.companyId,
      )).where((e) => !['synced', 'cancelled'].contains(e.state)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
