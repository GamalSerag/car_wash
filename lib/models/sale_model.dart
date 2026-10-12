class SaleModel {
  const SaleModel({
    required this.id,
    required this.companyId,
    required this.vehicleTypeId,
    this.vehicleTypeName,
    this.vehicleTypeIconName,
    this.vehicleName,
    this.plateNumber,
    required this.price,
    required this.employeeId,
    this.employeeName,
    this.notes,
    required this.createdAt,
  });

  final int id;
  final String companyId;
  final int vehicleTypeId;
  final String? vehicleTypeName;
  final String? vehicleTypeIconName;
  final String? vehicleName;
  final String? plateNumber;
  final double price;
  final String employeeId;
  final String? employeeName;
  final String? notes;
  final DateTime createdAt;

  factory SaleModel.fromMap(Map<String, dynamic> map) {
    final vehicleType = map['vehicle_types'];
    final employee = map['profiles'];

    return SaleModel(
      id: map['id'] as int,
      companyId: map['company_id'] as String? ?? '',
      vehicleTypeId: map['vehicle_type_id'] as int,
      vehicleTypeName: vehicleType is Map<String, dynamic>
          ? vehicleType['name'] as String?
          : map['vehicle_type_name'] as String?,
      vehicleTypeIconName: vehicleType is Map<String, dynamic>
          ? vehicleType['icon_name'] as String?
          : map['vehicle_type_icon_name'] as String?,
      vehicleName: map['vehicle_name'] as String?,
      plateNumber: map['plate_number'] as String?,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      employeeId: map['employee_id'] as String,
      employeeName: employee is Map<String, dynamic>
          ? employee['full_name'] as String?
          : map['employee_name'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'vehicle_type_id': vehicleTypeId,
      'vehicle_type_name': vehicleTypeName,
      'vehicle_type_icon_name': vehicleTypeIconName,
      'vehicle_name': vehicleName,
      'plate_number': plateNumber,
      'price': price,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
