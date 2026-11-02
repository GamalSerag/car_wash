class CompanyModel {
  const CompanyModel({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final bool isActive;
  final DateTime createdAt;

  factory CompanyModel.fromMap(Map<String, dynamic> map) => CompanyModel(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    isActive: map['is_active'] as bool? ?? false,
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
  };
}
