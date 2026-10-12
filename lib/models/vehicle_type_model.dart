class VehicleTypeModel {
  const VehicleTypeModel({
    required this.id,
    required this.companyId,
    required this.name,
    required this.price,
    this.iconName,
    required this.isActive,
    required this.createdAt,
  });

  final int id;
  final String companyId;
  final String name;
  final double price;
  final String? iconName;
  final bool isActive;
  final DateTime createdAt;

  factory VehicleTypeModel.fromMap(Map<String, dynamic> map) {
    return VehicleTypeModel(
      id: map['id'] as int,
      companyId: map['company_id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      iconName: map['icon_name'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'name': name,
      'price': price,
      'icon_name': iconName,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
