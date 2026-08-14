class CarpetOrderModel {
  const CarpetOrderModel({
    required this.id,
    required this.customerName,
    required this.phoneNumber,
    required this.totalPrice,
    required this.paidAmount,
    required this.remainingAmount,
    required this.employeeId,
    this.employeeName,
    this.notes,
    required this.isDelivered,
    required this.createdAt,
    this.deliveredAt,
    this.photoUrls = const [],
  });

  final int id;
  final String customerName;
  final String phoneNumber;
  final double totalPrice;
  final double paidAmount;
  final double remainingAmount;
  final String employeeId;
  final String? employeeName;
  final String? notes;
  final bool isDelivered;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final List<String> photoUrls;

  factory CarpetOrderModel.fromMap(Map<String, dynamic> map) {
    final photos = map['carpet_order_photos'];

    return CarpetOrderModel(
      id: map['id'] as int,
      customerName: map['customer_name'] as String? ?? '',
      phoneNumber: map['phone_number'] as String? ?? '',
      totalPrice: _toDouble(map['total_price']),
      paidAmount: _toDouble(map['paid_amount']),
      remainingAmount: _toDouble(map['remaining_amount']),
      employeeId: map['employee_id'] as String,
      employeeName:
          (map['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
      notes: map['notes'] as String?,
      isDelivered: map['is_delivered'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      deliveredAt: map['delivered_at'] == null
          ? null
          : DateTime.parse(map['delivered_at'] as String),
      photoUrls: photos is List
          ? photos
                .map((photo) => (photo as Map<String, dynamic>)['photo_url'])
                .whereType<String>()
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_name': customerName,
      'phone_number': phoneNumber,
      'total_price': totalPrice,
      'paid_amount': paidAmount,
      'remaining_amount': remainingAmount,
      'employee_id': employeeId,
      'notes': notes,
      'is_delivered': isDelivered,
      'created_at': createdAt.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
    };
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
