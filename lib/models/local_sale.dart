import 'sale_model.dart';

class LocalSale {
  const LocalSale({
    required this.localId,
    required this.userId,
    required this.companyId,
    required this.payload,
    required this.state,
    required this.revision,
    this.batchId,
    this.serverId,
    this.error,
    this.ackAt,
  });

  final String localId;
  final String userId;
  final String companyId;
  final Map<String, dynamic> payload;
  final String state;
  final int revision;
  final String? batchId;
  final int? serverId;
  final String? error;
  final int? ackAt;

  bool get canEdit => state == 'pending' && batchId == null;
  bool get countsAsSale => !['cancelled', 'failed'].contains(state);
  int get priceCents => payload['price_cents'] as int;
  DateTime get createdAt => DateTime.parse(payload['created_at'] as String);

  SaleModel get displaySale => SaleModel(
    id: serverId ?? -1,
    companyId: companyId,
    vehicleTypeId: payload['vehicle_type_id'] as int,
    vehicleTypeName: payload['vehicle_type_name'] as String?,
    vehicleTypeIconName: payload['vehicle_type_icon_name'] as String?,
    vehicleName: payload['vehicle_name'] as String?,
    plateNumber: payload['plate_number'] as String?,
    notes: payload['notes'] as String?,
    price: priceCents / 100,
    employeeId: userId,
    employeeName: payload['employee_name'] as String?,
    createdAt: createdAt,
    clientOperationId: localId,
  );
}
