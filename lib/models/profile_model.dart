class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String fullName;
  final String role;
  final bool isActive;
  final DateTime createdAt;

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'] as String,
      fullName: map['full_name'] as String? ?? '',
      role: map['role'] as String? ?? 'employee',
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'full_name': fullName,
      'role': role,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
