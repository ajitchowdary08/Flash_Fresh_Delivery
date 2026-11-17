class RiderOrderItem {
  final String name;
  final String variant;
  final int quantity;

  RiderOrderItem({
    required this.name,
    required this.variant,
    required this.quantity,
  });

  factory RiderOrderItem.fromJson(Map<String, dynamic> json) {
    return RiderOrderItem(
      name: json['name'] ?? '',
      variant: json['variant'] ?? '',
      quantity: json['quantity'] ?? 1,
    );
  }
}

class RiderOrderModel {
  final String orderId;
  final String orderNumber;
  final String status;
  final int itemsCount;
  final double distanceKm;
  final String deliveryAddress;
  final double grandTotal;
  final double payoutAmount;
  final String pickupHub;
  final String customerPhone;
  final double? latitude;
  final double? longitude;
  final List<RiderOrderItem> items;

  RiderOrderModel({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.itemsCount,
    required this.distanceKm,
    required this.deliveryAddress,
    required this.grandTotal,
    required this.payoutAmount,
    required this.pickupHub,
    required this.customerPhone,
    this.latitude,
    this.longitude,
    required this.items,
  });

  factory RiderOrderModel.fromJson(Map<String, dynamic> json) {
    var rawItems = json['items'] as List? ?? [];
    return RiderOrderModel(
      orderId: json['order_id'] ?? '',
      orderNumber: json['order_number'] ?? '',
      status: json['status'] ?? 'PLACED',
      itemsCount: json['items_count'] ?? 1,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 1.5,
      deliveryAddress: json['delivery_address'] ?? 'Hyderabad',
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      payoutAmount: (json['payout_amount'] as num?)?.toDouble() ?? 45.0,
      pickupHub: json['pickup_hub'] ?? 'Flash Fresh Central Dark Store',
      customerPhone: json['customer_phone'] ?? '+91 98765 43210',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      items: rawItems.map((i) => RiderOrderItem.fromJson(i)).toList(),
    );
  }
}
