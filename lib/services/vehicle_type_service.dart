import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vehicle_type_model.dart';

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
      final path = '${DateTime.now().millisecondsSinceEpoch}-$safeFileName';

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

  Future<List<VehicleTypeModel>> getActiveVehicleTypes() async {
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
}
