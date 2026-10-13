class SignupRequestModel {
  const SignupRequestModel({
    required this.id,
    required this.companyName,
    required this.ownerName,
    required this.phone,
    required this.email,
    this.address,
    this.notes,
    required this.status,
    this.companyId,
    required this.createdAt,
  });

  final int id;
  final String companyName;
  final String ownerName;
  final String phone;
  final String email;
  final String? address;
  final String? notes;
  final String status;
  final String? companyId;
  final DateTime createdAt;

  factory SignupRequestModel.fromMap(Map<String, dynamic> map) {
    return SignupRequestModel(
      id: map['id'] as int,
      companyName: map['company_name'] as String? ?? '',
      ownerName: map['owner_name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      status: map['status'] as String? ?? 'pending',
      companyId: map['company_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_name': companyName,
      'owner_name': ownerName,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'status': status,
      'company_id': companyId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
