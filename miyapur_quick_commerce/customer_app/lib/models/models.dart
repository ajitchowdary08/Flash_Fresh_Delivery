class LocationModel {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String landmark;
  final double distanceKm;
  final bool isServiceable;
  final int etaMinutes;

  LocationModel({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.landmark,
    required this.distanceKm,
    required this.isServiceable,
    required this.etaMinutes,
  });

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      landmark: json['landmark'] ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      isServiceable: json['is_serviceable'] ?? true,
      etaMinutes: json['eta_minutes'] ?? 15,
    );
  }
}

class SavedAddressModel {
  final String id;
  final String label; // Home, Work, Other
  final String houseNumber;
  final String streetAddress;
  final String landmark;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final bool isServiceable;
  final bool isDefault;

  SavedAddressModel({
    required this.id,
    required this.label,
    required this.houseNumber,
    required this.streetAddress,
    required this.landmark,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.isServiceable,
    required this.isDefault,
  });

  factory SavedAddressModel.fromJson(Map<String, dynamic> json) {
    return SavedAddressModel(
      id: json['id'] ?? '',
      label: json['label'] ?? 'Home',
      houseNumber: json['house_number'] ?? '',
      streetAddress: json['street_address'] ?? '',
      landmark: json['landmark'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 17.495101,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 78.367535,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.1,
      isServiceable: json['is_serviceable'] ?? true,
      isDefault: json['is_default'] ?? false,
    );
  }
}

class UserProfileModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final int totalOrders;
  final int savedAddressesCount;
  final String memberSince;

  UserProfileModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.totalOrders,
    required this.savedAddressesCount,
    required this.memberSince,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Valued Resident',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      totalOrders: json['total_orders'] ?? 0,
      savedAddressesCount: json['saved_addresses_count'] ?? 1,
      memberSince: json['member_since'] ?? 'November 2026',
    );
  }
}

class ProductVariantModel {
  final String id;
  final String weightLabel;
  final double mrp;
  final double price;
  final int stockQty;

  ProductVariantModel({
    required this.id,
    required this.weightLabel,
    required this.mrp,
    required this.price,
    required this.stockQty,
  });

  factory ProductVariantModel.fromJson(Map<String, dynamic> json) {
    return ProductVariantModel(
      id: json['id'] ?? '',
      weightLabel: json['weight_label'] ?? '',
      mrp: (json['mrp'] as num?)?.toDouble() ?? 0.0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      stockQty: json['stock_qty'] ?? 100,
    );
  }
}

class ProductModel {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final String imageUrl;
  final bool isSundayOnly;
  final String deliveryMode;
  final String deliveryLabel;
  final List<ProductVariantModel> variants;

  ProductModel({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.isSundayOnly,
    required this.deliveryMode,
    required this.deliveryLabel,
    required this.variants,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    var rawVariants = json['variants'] as List? ?? [];
    List<ProductVariantModel> variantList = rawVariants
        .map((v) => ProductVariantModel.fromJson(v as Map<String, dynamic>))
        .toList();

    return ProductModel(
      id: json['id'] ?? '',
      categoryId: json['category_id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['image_url'] ?? '',
      isSundayOnly: json['is_sunday_only'] ?? false,
      deliveryMode: json['delivery_mode'] ?? 'LIVE_DELIVERY',
      deliveryLabel: json['delivery_label'] ?? '10-15 Mins Quick Delivery',
      variants: variantList,
    );
  }
}

class CartItemModel {
  final ProductModel product;
  ProductVariantModel selectedVariant;
  int quantity;

  CartItemModel({
    required this.product,
    required this.selectedVariant,
    this.quantity = 1,
  });

  double get totalPrice => selectedVariant.price * quantity;
}

class OrderHistoryItem {
  final String name;
  final String variant;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  OrderHistoryItem({
    required this.name,
    required this.variant,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory OrderHistoryItem.fromJson(Map<String, dynamic> json) {
    return OrderHistoryItem(
      name: json['name'] ?? '',
      variant: json['variant'] ?? '',
      quantity: json['quantity'] ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class OrderHistoryModel {
  final String orderId;
  final String orderNumber;
  final String status;
  final double grandTotal;
  final double itemsTotal;
  final double discountAmount;
  final String promoCode;
  final double deliveryFee;
  final String deliveryOtp;
  final String paymentStatus;
  final String paymentMethod;
  final String deliveryAddress;
  final int deliveryEtaMins;
  final String createdAt;
  final bool isSundayMeatOrder;
  final List<OrderHistoryItem> items;
  final String riderName;
  final String riderPhone;
  final String riderVehicle;
  final double riderLat;
  final double riderLng;
  final double? latitude;
  final double? longitude;

  OrderHistoryModel({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.grandTotal,
    required this.itemsTotal,
    required this.discountAmount,
    required this.promoCode,
    required this.deliveryFee,
    required this.deliveryOtp,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.deliveryAddress,
    required this.deliveryEtaMins,
    required this.createdAt,
    required this.isSundayMeatOrder,
    required this.items,
    this.riderName = "Ravi Kumar",
    this.riderPhone = "+91 98480 12345",
    this.riderVehicle = "Hero Electric (TS 07 EK 4921)",
    this.riderLat = 17.495101,
    this.riderLng = 78.367535,
    this.latitude,
    this.longitude,
  });

  factory OrderHistoryModel.fromJson(Map<String, dynamic> json) {
    var rawItems = json['items'] as List? ?? [];
    return OrderHistoryModel(
      orderId: json['order_id'] ?? '',
      orderNumber: json['order_number'] ?? '',
      status: json['status'] ?? 'PLACED',
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      itemsTotal: (json['items_total'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      promoCode: json['promo_code'] ?? '',
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 15.0,
      deliveryOtp: json['delivery_otp'] ?? '4921',
      paymentStatus: json['payment_status'] ?? 'PAID',
      paymentMethod: json['payment_method'] ?? 'UPI',
      deliveryAddress: json['delivery_address'] ?? '',
      deliveryEtaMins: json['delivery_eta_mins'] ?? 15,
      createdAt: json['created_at'] ?? 'Today',
      isSundayMeatOrder: json['is_sunday_meat_order'] ?? false,
      items: rawItems.map((i) => OrderHistoryItem.fromJson(i)).toList(),
      riderName: json['rider_name'] ?? 'Ravi Kumar',
      riderPhone: json['rider_phone'] ?? '+91 98480 12345',
      riderVehicle: json['rider_vehicle'] ?? 'Hero Electric (TS 07 EK 4921)',
      riderLat: (json['rider_lat'] as num?)?.toDouble() ?? 17.495101,
      riderLng: (json['rider_lng'] as num?)?.toDouble() ?? 78.367535,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}
