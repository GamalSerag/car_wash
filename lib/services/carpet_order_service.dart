import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/carpet_order_model.dart';

class CarpetOrderService {
  CarpetOrderService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<CarpetOrderModel> createOrder({
    required String customerName,
    required String phoneNumber,
    required double totalPrice,
    required double paidAmount,
    required String employeeId,
    String? notes,
    List<CarpetOrderPhotoUpload> photos = const [],
  }) async {
    try {
      final remainingAmount = totalPrice - paidAmount;
      final data = await _client
          .from('carpet_orders')
          .insert({
            'customer_name': customerName,
            'phone_number': phoneNumber,
            'total_price': totalPrice,
            'paid_amount': paidAmount,
            'remaining_amount': remainingAmount < 0 ? 0 : remainingAmount,
            'employee_id': employeeId,
            'notes': notes,
          })
          .select(_ordersSelect)
          .single();

      final order = CarpetOrderModel.fromMap(data);

      if (photos.isNotEmpty) {
        await _uploadOrderPhotos(order.id, photos);
        return await getOrder(order.id);
      }

      return order;
    } catch (error) {
      throw Exception('Failed to create carpet order: $error');
    }
  }

  Future<CarpetOrderModel> updateOrder({
    required int id,
    required String customerName,
    required String phoneNumber,
    required double totalPrice,
    required double paidAmount,
    String? notes,
    bool? isDelivered,
    List<CarpetOrderPhotoUpload> photos = const [],
  }) async {
    try {
      final remainingAmount = totalPrice - paidAmount;
      final updateData = <String, dynamic>{
        'customer_name': customerName,
        'phone_number': phoneNumber,
        'total_price': totalPrice,
        'paid_amount': paidAmount,
        'remaining_amount': remainingAmount < 0 ? 0 : remainingAmount,
        'notes': notes,
      };

      if (isDelivered != null) {
        updateData['is_delivered'] = isDelivered;
        updateData['delivered_at'] = isDelivered
            ? DateTime.now().toUtc().toIso8601String()
            : null;
      }

      await _client.from('carpet_orders').update(updateData).eq('id', id);

      if (photos.isNotEmpty) {
        await _uploadOrderPhotos(id, photos);
      }

      return await getOrder(id);
    } catch (error) {
      throw Exception('Failed to update carpet order: $error');
    }
  }

  Future<CarpetOrderModel> getOrder(int id) async {
    try {
      final data = await _client
          .from('carpet_orders')
          .select(_ordersSelect)
          .eq('id', id)
          .single();

      return CarpetOrderModel.fromMap(data);
    } catch (error) {
      throw Exception('Failed to get carpet order: $error');
    }
  }

  Future<List<CarpetOrderModel>> getOrders() async {
    try {
      final data = await _client
          .from('carpet_orders')
          .select(_ordersSelect)
          .order('created_at', ascending: false);

      return data.map(CarpetOrderModel.fromMap).toList();
    } catch (error) {
      throw Exception('Failed to get carpet orders: $error');
    }
  }

  Future<void> markDelivered(int id) async {
    try {
      final order = await getOrder(id);
      await _client
          .from('carpet_orders')
          .update({
            'is_delivered': true,
            'delivered_at': DateTime.now().toUtc().toIso8601String(),
            'paid_amount': order.totalPrice,
            'remaining_amount': 0,
          })
          .eq('id', id);
    } catch (error) {
      throw Exception('Failed to mark carpet order delivered: $error');
    }
  }

  Future<void> deleteOrder(int id) async {
    try {
      final photos = await _client
          .from('carpet_order_photos')
          .select('storage_path')
          .eq('order_id', id);
      final paths = photos
          .map((photo) => photo['storage_path'] as String?)
          .whereType<String>()
          .toList();

      if (paths.isNotEmpty) {
        await _client.storage.from('carpet-orders').remove(paths);
      }

      await _client.from('carpet_orders').delete().eq('id', id);
    } catch (error) {
      throw Exception('Failed to delete carpet order: $error');
    }
  }

  Future<void> _uploadOrderPhotos(
    int orderId,
    List<CarpetOrderPhotoUpload> photos,
  ) async {
    for (final photo in photos) {
      final safeName = photo.fileName.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final path =
          '$orderId/${DateTime.now().millisecondsSinceEpoch}-$safeName';

      await _client.storage
          .from('carpet-orders')
          .uploadBinary(
            path,
            photo.bytes,
            fileOptions: FileOptions(contentType: photo.contentType),
          );

      final publicUrl = _client.storage
          .from('carpet-orders')
          .getPublicUrl(path);

      await _client.from('carpet_order_photos').insert({
        'order_id': orderId,
        'photo_url': publicUrl,
        'storage_path': path,
      });
    }
  }

  static const String _ordersSelect = '''
    *,
    profiles(full_name),
    carpet_order_photos(photo_url)
  ''';
}

class CarpetOrderPhotoUpload {
  const CarpetOrderPhotoUpload({
    required this.fileName,
    required this.bytes,
    required this.contentType,
  });

  final String fileName;
  final Uint8List bytes;
  final String contentType;
}
