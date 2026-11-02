class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.isCompanyActive = true,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String companyName;
  final String fullName;
  final String role;
  final bool isActive;
  final bool isCompanyActive;
  final DateTime createdAt;

  bool get isAdmin => role == 'admin' || role == 'super_admin';
  bool get isSuperAdmin => role == 'super_admin';
  bool get canAccessCompany => isSuperAdmin || isCompanyActive;
  bool get canAccessApp => isActive && canAccessCompany;

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    final company = map['companies'];

    return ProfileModel(
      id: map['id'] as String,
      companyId: map['company_id'] as String? ?? '',
      companyName: company is Map<String, dynamic>
          ? company['name'] as String? ?? ''
          : map['company_name'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      role: map['role'] as String? ?? 'employee',
      isActive: map['is_active'] as bool? ?? true,
      isCompanyActive: company is Map<String, dynamic>
          ? company['is_active'] as bool? ?? false
          : map['company_is_active'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'company_name': companyName,
      'full_name': fullName,
      'role': role,
      'is_active': isActive,
      'company_is_active': isCompanyActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
