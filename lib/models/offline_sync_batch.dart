import '../core/offline_protocol.dart';

class OfflineSyncBatch {
  OfflineSyncBatch({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.items,
    required this.actions,
  });

  final String id;
  final String userId;
  final String companyId;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> actions;

  int get orderCount => items.where((e) => e['cancelled'] != true).length;
  String get manifestHash => protocolHash({'items': items, 'actions': actions});
}
