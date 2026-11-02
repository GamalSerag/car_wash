import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/input_limits.dart';

import '../models/vehicle_type_model.dart';
import '../core/offline_protocol.dart';
import 'offline_runtime.dart';

class VehicleTypeService {
  VehicleTypeService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> uploadVehicleIcon({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final companyId = await _getCurrentCompanyId();
      final path =
          '$companyId/vehicle-icons/${DateTime.now().millisecondsSinceEpoch}-$safeFileName';

      await _client.storage
          .from('vehicle-icons')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      return _client.storage.from('vehicle-icons').getPublicUrl(path);
    } on StorageException {
      rethrow;
    } catch (error) {
      throw Exception('Failed to upload vehicle icon: $error');
    }
  }

  Future<List<VehicleTypeModel>> getVehicleTypes() async {
    try {
      final data = await _client.from('vehicle_types').select().order('id');

      return data.map(VehicleTypeModel.fromMap).toList();
    } on PostgrestException {
      rethrow;
    } catch (error) {
      throw Exception('Failed to get vehicle types: $error');
    }
  }

  Future<List<VehicleTypeModel>> getActiveVehicleTypes({
    bool refreshCache = false,
  }) async {
    if (OfflineRuntime.owns(_client)) {
      final user = _client.auth.currentUser?.id;
      final profile = user == null
          ? null
          : await OfflineRuntime.session!.cachedProfile(
              user,
              allowExpired: OfflineRuntime.online.value,
            );
      if (profile != null &&
          profile.canAccessApp &&
          profile.role == 'employee') {
        final key = 'types:${profile.id}:${profile.companyId}';
        final cached = await OfflineRuntime.store!.cache(key);
        Future<List<VehicleTypeModel>> refresh() async {
          await OfflineRuntime.session!.ensure(_client, expectedUser: user);
          final data = await _client
              .from('vehicle_types')
              .select()
              .eq('is_active', true)
              .eq('company_id', profile.companyId)
              .order('id')
              .timeout(const Duration(seconds: 12));
          if (_client.auth.currentUser?.id != user) return <VehicleTypeModel>[];
          await OfflineRuntime.store!.put(key, data);
          return data.map(VehicleTypeModel.fromMap).toList();
        }

        if (cached != null && !refreshCache) {
          if (OfflineRuntime.online.value &&
              DateTime.now().millisecondsSinceEpoch - (cached['at'] as int) >
                  const Duration(minutes: 5).inMilliseconds) {
            refresh().catchError((Object _) => <VehicleTypeModel>[]);
          }
          return (cached['value'] as List)
              .map(
                (e) => VehicleTypeModel.fromMap(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();
        }
        try {
          return await refresh();
        } catch (error) {
          if (!isTransientOfflineError(error)) rethrow;
          if (cached != null)
            return (cached['value'] as List)
                .map(
                  (e) => VehicleTypeModel.fromMap(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList();
          throw StateError('اتصل بالإنترنت لتحميل أنواع المركبات أول مرة');
        }
      }
    }
    try {
      final data = await _client
          .from('vehicle_types')
          .select()
          .eq('is_active', true)
          .order('id');

      return data.map(VehicleTypeModel.fromMap).toList();
    } catch (error) {
      throw Exception('Failed to get vehicle types: $error');
    }
  }

  Future<VehicleTypeModel> createVehicleType({
    required String name,
    required double price,
    String? iconName,
  }) async {
    InputLimits.checkText(name, InputLimits.name);
    InputLimits.checkAmount(price);
    try {
      final data = await _client
          .from('vehicle_types')
          .insert({'name': name, 'price': price, 'icon_name': iconName})
          .select()
          .single();

      return VehicleTypeModel.fromMap(data);
    } on PostgrestException {
      rethrow;
    } catch (error) {
      throw Exception('Failed to create vehicle type: $error');
    }
  }

  Future<VehicleTypeModel> updateVehicleType({
    required int id,
    String? name,
    double? price,
    String? iconName,
    bool? isActive,
  }) async {
    InputLimits.checkText(name, InputLimits.name);
    if (price != null) InputLimits.checkAmount(price);
    try {
      final updates = <String, dynamic>{
        if (name != null) 'name': name,
        if (price != null) 'price': price,
        if (iconName != null) 'icon_name': iconName,
        if (isActive != null) 'is_active': isActive,
      };

      final data = await _client
          .from('vehicle_types')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

      return VehicleTypeModel.fromMap(data);
    } on PostgrestException {
      rethrow;
    } catch (error) {
      throw Exception('Failed to update vehicle type: $error');
    }
  }

  Future<void> deactivateVehicleType(int id) async {
    try {
      await _client
          .from('vehicle_types')
          .update({'is_active': false})
          .eq('id', id);
    } on PostgrestException {
      rethrow;
    } catch (error) {
      throw Exception('Failed to deactivate vehicle type: $error');
    }
  }

  Future<String> _getCurrentCompanyId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No authenticated user');
    }

    final data = await _client
        .from('profiles')
        .select('company_id')
        .eq('id', userId)
        .single();
    final companyId = data['company_id'] as String?;
    if (companyId == null || companyId.isEmpty) {
      throw Exception('Current user has no company');
    }

    return companyId;
  }
}
