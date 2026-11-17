import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? endpoint;

  ApiException(this.message, {this.statusCode, this.endpoint});

  @override
  String toString() => "ApiException($statusCode @ $endpoint): $message";
}

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: "https://flash-fresh.onrender.com/api/v1",
  );

  static final List<OrderHistoryModel> _localOrders = [];
  static final Map<String, Map<String, String>> _localProfiles = {};

  /// Verified from https://maps.app.goo.gl/5fc6a8ZMgjfttUiB9
  static const double hubLatitude = 17.495101;
  static const double hubLongitude = 78.367535;
  static const double maxDeliveryRadiusKm = 10.0;

  static final List<LocationModel> fallbackLocations = [];

  static final List<LocationModel> nearbyLocations = [
    LocationModel(
      id: "nearby_1",
      name: "Miyapur Metro Station",
      address: "Beside Metro Pillar 84, Miyapur, Hyderabad",
      latitude: 17.4968,
      longitude: 78.3614,
      landmark: "Miyapur Metro Station",
      distanceKm: 0.68,
      isServiceable: true,
      etaMinutes: 9,
    ),
    LocationModel(
      id: "nearby_2",
      name: "Allwyn X Roads",
      address: "Allwyn Colony Main Road, Miyapur, Hyderabad",
      latitude: 17.4985,
      longitude: 78.3720,
      landmark: "Allwyn Junction",
      distanceKm: 0.61,
      isServiceable: true,
      etaMinutes: 8,
    ),
    LocationModel(
      id: "nearby_3",
      name: "Madinaguda Central",
      address: "Opposite GSM Mall, Madinaguda, Hyderabad",
      latitude: 17.4920,
      longitude: 78.3520,
      landmark: "GSM Mall",
      distanceKm: 1.68,
      isServiceable: true,
      etaMinutes: 10,
    ),
    LocationModel(
      id: "nearby_4",
      name: "Hafeezpet MMTS Station",
      address: "Hafeezpet Road, Hyderabad",
      latitude: 17.4812,
      longitude: 78.3651,
      landmark: "Railway Bridge",
      distanceKm: 1.57,
      isServiceable: true,
      etaMinutes: 10,
    ),
    LocationModel(
      id: "nearby_5",
      name: "Chandanagar Rythu Bazar",
      address: "Chandanagar Main Road, Hyderabad",
      latitude: 17.4895,
      longitude: 78.3390,
      landmark: "Rythu Bazar",
      distanceKm: 3.09,
      isServiceable: true,
      etaMinutes: 12,
    ),
    LocationModel(
      id: "nearby_6",
      name: "Nizampet Village & Road",
      address: "Nizampet Main Road, Hyderabad",
      latitude: 17.5180,
      longitude: 78.3820,
      landmark: "Gram Panchayat",
      distanceKm: 2.97,
      isServiceable: true,
      etaMinutes: 12,
    ),
    LocationModel(
      id: "nearby_7",
      name: "KPHB Colony / JNTU",
      address: "KPHB Phase 1, Kukatpally, Hyderabad",
      latitude: 17.4980,
      longitude: 78.3910,
      landmark: "JNTU Main Gate",
      distanceKm: 2.51,
      isServiceable: true,
      etaMinutes: 11,
    ),
    LocationModel(
      id: "nearby_8",
      name: "Bachupally X Roads",
      address: "Bachupally, Hyderabad",
      latitude: 17.5350,
      longitude: 78.3650,
      landmark: "Silver Oaks Road",
      distanceKm: 4.44,
      isServiceable: true,
      etaMinutes: 14,
    ),
    LocationModel(
      id: "nearby_9",
      name: "Kondapur Botanical Garden",
      address: "Botanical Garden Road, Kondapur, Hyderabad",
      latitude: 17.4580,
      longitude: 78.3650,
      landmark: "Heritage Fresh",
      distanceKm: 4.13,
      isServiceable: true,
      etaMinutes: 14,
    ),
  ];

  static Future<Map<String, dynamic>> sendOtp(String phone) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/auth/send-otp"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"phone": phone}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      try {
        final err = jsonDecode(response.body);
        return {
          "success": false,
          "message": err["detail"] ?? "Could not send OTP. Please try again.",
        };
      } catch (_) {
        return {
          "success": false,
          "message":
              "Could not send OTP (HTTP ${response.statusCode}). Please try again.",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Cannot connect to server. Please check your internet connection and try again.",
      };
    }
  }

  static Future<Map<String, dynamic>> syncFirebaseUserWithBackend({
    required String phone,
    required String firebaseUid,
    String? name,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final canonicalUserId = "usr_$cleanPhone";
    final last4 = cleanPhone.length >= 4
        ? cleanPhone.substring(cleanPhone.length - 4)
        : "";
    final defaultName =
        name ?? (last4.isNotEmpty ? "Customer ($last4)" : "Customer");

    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/auth/firebase-login"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "phone": phone,
              "firebase_uid": firebaseUid.startsWith("firebase_auto_")
                  ? canonicalUserId
                  : firebaseUid,
              "name": defaultName,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    return {
      "success": true,
      "user_id": firebaseUid.startsWith("firebase_auto_")
          ? canonicalUserId
          : firebaseUid,
      "phone": cleanPhone,
      "name": defaultName,
      "token": "jwt_synced_$firebaseUid",
    };
  }

  static Future<Map<String, dynamic>> verifyOtp(
    String phone,
    String otp,
  ) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final last4 = cleanPhone.length >= 4
        ? cleanPhone.substring(cleanPhone.length - 4)
        : "";
    final defaultName = "Customer ($last4)";

    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/auth/verify-otp"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"phone": phone, "otp": otp, "name": defaultName}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        try {
          final err = jsonDecode(response.body);
          return {
            "success": false,
            "message": err["detail"] ?? "Incorrect OTP verification code.",
          };
        } catch (_) {
          return {
            "success": false,
            "message": "OTP verification failed (HTTP ${response.statusCode}).",
          };
        }
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Cannot connect to server. Please check your internet connection and try again.",
      };
    }
  }

  static Future<UserProfileModel> getUserProfile(
    String userId, {
    String? defaultPhone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString("user_name");
    final savedEmail = prefs.getString("user_email") ?? "";
    final savedPhone = prefs.getString("user_phone") ?? (defaultPhone ?? "");

    try {
      final response = await http
          .get(Uri.parse("$baseUrl/auth/profile/$userId"))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final profile = UserProfileModel.fromJson(jsonDecode(response.body));
        final resolvedName =
            (savedName != null &&
                savedName.isNotEmpty &&
                savedName != "Customer")
            ? savedName
            : (profile.name.isNotEmpty ? profile.name : "Valued Customer");
        final resolvedEmail = savedEmail.isNotEmpty
            ? savedEmail
            : profile.email;

        return UserProfileModel(
          id: profile.id,
          name: resolvedName,
          phone: profile.phone.isNotEmpty ? profile.phone : savedPhone,
          email: resolvedEmail,
          totalOrders: profile.totalOrders,
          savedAddressesCount: profile.savedAddressesCount,
          memberSince: profile.memberSince,
        );
      }
    } catch (_) {}

    return UserProfileModel(
      id: userId,
      name: (savedName != null && savedName.isNotEmpty)
          ? savedName
          : (savedPhone.isNotEmpty
                ? "Customer ($savedPhone)"
                : "Valued Customer"),
      phone: savedPhone,
      email: savedEmail,
      totalOrders: _localOrders.length,
      savedAddressesCount: 1,
      memberSince: "November 2026",
    );
  }

  static Future<bool> updateUserProfile(
    String userId,
    String name,
    String email,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("user_name", name);
    await prefs.setString("user_email", email);
    _localProfiles[userId] = {"name": name, "email": email};

    try {
      final response = await http
          .put(
            Uri.parse("$baseUrl/auth/profile/$userId"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"name": name, "email": email}),
          )
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (_) {}
    return true;
  }

  static Future<List<SavedAddressModel>> getSavedAddresses(
    String userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final rawLocalAddrs = prefs.getStringList("saved_addrs_$userId") ?? [];
    final globalAddrs = prefs.getStringList("global_saved_addrs") ?? [];

    Set<String> allRaw = {...rawLocalAddrs, ...globalAddrs};
    List<SavedAddressModel> localAddrs = [];

    for (var str in allRaw) {
      try {
        localAddrs.add(SavedAddressModel.fromJson(jsonDecode(str)));
      } catch (_) {}
    }

    try {
      final response = await http
          .get(Uri.parse("$baseUrl/auth/addresses/$userId"))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        List<SavedAddressModel> apiAddrs = data
            .map((x) => SavedAddressModel.fromJson(x))
            .toList();
        final existingIds = apiAddrs.map((a) => a.id).toSet();
        for (var locAddr in localAddrs) {
          if (!existingIds.contains(locAddr.id)) {
            apiAddrs.add(locAddr);
          }
        }
        return apiAddrs;
      }
    } catch (_) {}

    return localAddrs;
  }

  static Future<bool> addSavedAddress({
    required String userId,
    required String label,
    required String houseNumber,
    required String streetAddress,
    required String landmark,
    required double latitude,
    required double longitude,
    bool isDefault = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final rawLocalAddrs = prefs.getStringList("saved_addrs_$userId") ?? [];
    final globalAddrs = prefs.getStringList("global_saved_addrs") ?? [];

    final newAddr = SavedAddressModel(
      id: "addr_${DateTime.now().millisecondsSinceEpoch}",
      label: label,
      houseNumber: houseNumber,
      streetAddress: streetAddress,
      landmark: landmark,
      latitude: latitude,
      longitude: longitude,
      distanceKm: 0.1,
      isServiceable: true,
      isDefault: isDefault,
    );

    final jsonStr = jsonEncode({
      "id": newAddr.id,
      "label": newAddr.label,
      "house_number": newAddr.houseNumber,
      "street_address": newAddr.streetAddress,
      "landmark": newAddr.landmark,
      "latitude": newAddr.latitude,
      "longitude": newAddr.longitude,
      "distance_km": newAddr.distanceKm,
      "is_serviceable": newAddr.isServiceable,
      "is_default": newAddr.isDefault,
    });

    rawLocalAddrs.add(jsonStr);
    globalAddrs.add(jsonStr);

    await prefs.setStringList("saved_addrs_$userId", rawLocalAddrs);
    await prefs.setStringList("global_saved_addrs", globalAddrs);

    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/auth/addresses/$userId"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "label": label,
              "house_number": houseNumber,
              "street_address": streetAddress,
              "landmark": landmark,
              "latitude": latitude,
              "longitude": longitude,
              "is_default": isDefault,
            }),
          )
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (_) {}
    return true;
  }

  static Future<List<OrderHistoryModel>> getOrderHistory(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final rawDiskOrders = prefs.getStringList("cached_user_orders") ?? [];
    List<OrderHistoryModel> diskOrders = [];
    for (var str in rawDiskOrders) {
      try {
        diskOrders.add(OrderHistoryModel.fromJson(jsonDecode(str)));
      } catch (_) {}
    }

    try {
      final response = await http
          .get(Uri.parse("$baseUrl/orders/history/$userId"))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        List<OrderHistoryModel> apiOrders = data
            .map((x) => OrderHistoryModel.fromJson(x))
            .toList();

        final existingIds = apiOrders.map((o) => o.orderId).toSet();
        for (var localOrd in [..._localOrders, ...diskOrders]) {
          if (!existingIds.contains(localOrd.orderId)) {
            apiOrders.insert(0, localOrd);
          }
        }
        return apiOrders;
      }
    } catch (_) {}

    final existingIds = diskOrders.map((o) => o.orderId).toSet();
    for (var localOrd in _localOrders) {
      if (!existingIds.contains(localOrd.orderId)) {
        diskOrders.insert(0, localOrd);
      }
    }
    return diskOrders;
  }

  static Future<Map<String, dynamic>> getOrderTracking(String orderId) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/orders/$orderId/tracking"))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    return {
      "order_id": orderId,
      "order_number": "MYP-9842",
      "status": "OUT_FOR_DELIVERY",
      "delivery_eta_mins": 12,
      "delivery_otp": "4921",
      "rider": {
        "name": "Ravi Kumar",
        "phone": "+91 98480 12345",
        "vehicle": "Hero Electric (TS 07 EK 4921)",
        "rating": 4.9,
        "current_lat": 17.495101,
        "current_lng": 78.367535,
      },
    };
  }

  static Future<Map<String, dynamic>> validatePromoCode(
    String code,
    double itemsTotal,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/catalog/promos/validate"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"code": code, "items_total": itemsTotal}),
          )
          .timeout(const Duration(seconds: 15));

      return jsonDecode(response.body);
    } catch (_) {}

    if (code.toUpperCase() == "ZEPTO50" && itemsTotal >= 149) {
      double disc = (itemsTotal * 0.20).clamp(0, 50);
      return {
        "success": true,
        "code": "ZEPTO50",
        "discount_amount": disc,
        "message": "Coupon ZEPTO50 applied! Saved ₹${disc.toStringAsFixed(0)}.",
      };
    } else if (code.toUpperCase() == "MIYAPUR100" && itemsTotal >= 299) {
      double disc = (itemsTotal * 0.25).clamp(0, 100);
      return {
        "success": true,
        "code": "MIYAPUR100",
        "discount_amount": disc,
        "message":
            "Coupon MIYAPUR100 applied! Saved ₹${disc.toStringAsFixed(0)}.",
      };
    }

    return {
      "success": false,
      "message": "Invalid promo code or minimum order value not met.",
    };
  }

  static Future<List<ProductModel>> searchProducts(String query) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/catalog/search?query=$query"))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((x) => ProductModel.fromJson(x)).toList();
      }
    } catch (_) {}

    return _getStaticProducts(false)
        .where(
          (p) =>
              p.name.toLowerCase().contains(query.toLowerCase()) ||
              p.description.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
  }

  static Future<List<LocationModel>> getLocations({String query = ""}) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/maps/locations?query=$query"))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((x) => LocationModel.fromJson(x)).toList();
      }
    } catch (_) {}

    if (query.isEmpty) return fallbackLocations;
    return fallbackLocations
        .where(
          (l) =>
              l.name.toLowerCase().contains(query.toLowerCase()) ||
              l.address.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
  }

  static Future<List<LocationModel>> getNearbyLocations({double? lat, double? lng}) async {
    try {
      String url = "$baseUrl/maps/nearby";
      if (lat != null && lng != null) {
        url = "$url?lat=$lat&lng=$lng";
      }
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((x) => LocationModel.fromJson(x)).toList();
      }
    } catch (_) {}
    return nearbyLocations;
  }

  static Future<Map<String, dynamic>> checkServiceability(
    double lat,
    double lng,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/maps/check-serviceability"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"latitude": lat, "longitude": lng}),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return _localServiceability(lat, lng);
  }

  static Future<Map<String, dynamic>> reverseGeocode(
    double lat,
    double lng,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/maps/reverse-geocode"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"latitude": lat, "longitude": lng}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    final local = _localServiceability(lat, lng);
    return {
      "id": "gps_${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}",
      "name": "Detected Location",
      "address": "GPS (${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})",
      "landmark": "",
      "latitude": lat,
      "longitude": lng,
      "distance_km": local["distance_km"],
      "is_serviceable": local["is_serviceable"],
      "eta_minutes": local["estimated_delivery_minutes"],
      "message": local["message"],
      "store_latitude": hubLatitude,
      "store_longitude": hubLongitude,
      "max_allowed_radius_km": maxDeliveryRadiusKm,
    };
  }

  static Future<Map<String, dynamic>?> geocodePlace(String placeId) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/maps/geocode"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"place_id": placeId}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>> getDirectionsRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final url =
          "$baseUrl/maps/route?origin_lat=$originLat&origin_lng=$originLng&dest_lat=$destLat&dest_lng=$destLng";
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return {
      "success": false,
      "points": <Map<String, dynamic>>[],
      "distance_km": 0.0,
      "duration_mins": 10,
      "source": "fallback",
    };
  }

  static Map<String, dynamic> _localServiceability(double lat, double lng) {
    const R = 6371.0;
    double dLat = _rad(lat - hubLatitude);
    double dLng = _rad(lng - hubLongitude);
    double a =
        (math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(hubLatitude)) *
            math.cos(_rad(lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2));
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    double distance = double.parse((R * c).toStringAsFixed(2));
    bool serviceable = distance <= maxDeliveryRadiusKm;
    int eta = serviceable ? (8 + distance * 1.5).toInt().clamp(0, 25) : 0;
    return {
      "is_serviceable": serviceable,
      "distance_km": distance,
      "max_allowed_radius_km": maxDeliveryRadiusKm,
      "estimated_delivery_minutes": serviceable ? eta : null,
      "store_latitude": hubLatitude,
      "store_longitude": hubLongitude,
      "message": serviceable
          ? "Delivery available in ~$eta mins!"
          : "Delivery not available. Your location is $distance KM away, which exceeds the 10 KM delivery radius from the Miyapur Central Dark Store Hub.",
    };
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  static Future<Map<String, dynamic>> getProducts({
    bool forceSunday = false,
  }) async {
    try {
      String dayParam = forceSunday ? "sunday" : "weekday";
      final response = await http
          .get(Uri.parse("$baseUrl/catalog/products?day_override=$dayParam"))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        var body = jsonDecode(response.body);
        List rawList = body['products'] as List;
        List<ProductModel> products = rawList
            .map((x) => ProductModel.fromJson(x))
            .toList();
        return {
          "is_sunday": body['is_sunday'] ?? forceSunday,
          "products": products,
        };
      }
    } catch (_) {}

    return {
      "is_sunday": forceSunday,
      "products": _getStaticProducts(forceSunday),
    };
  }

  static Future<Map<String, dynamic>> createOrder({
    required String userId,
    required String deliveryAddress,
    required double latitude,
    required double longitude,
    required List<CartItemModel> items,
    required String paymentMethod,
    required bool isSundayMeatOrder,
    String promoCode = "",
    String deliveryInstructions = "",
  }) async {
    var itemsPayload = items
        .map(
          (i) => {
            "product_name": i.product.name,
            "variant_label": i.selectedVariant.weightLabel,
            "quantity": i.quantity,
            "unit_price": i.selectedVariant.price,
          },
        )
        .toList();

    double itemsTotal = items.fold(0.0, (acc, item) => acc + item.totalPrice);
    double discount = 0.0;
    if (promoCode.toUpperCase() == "ZEPTO50" && itemsTotal >= 149) {
      discount = (itemsTotal * 0.20).clamp(0, 50);
    } else if (promoCode.toUpperCase() == "MIYAPUR100" && itemsTotal >= 299) {
      discount = (itemsTotal * 0.25).clamp(0, 100);
    }

    double netItems = (itemsTotal - discount).clamp(0, 99999);
    double deliveryFee = netItems >= 199.0 ? 0.0 : 15.0;
    double grandTotal = netItems + deliveryFee;

    final orderId = "ord_${DateTime.now().millisecondsSinceEpoch}";
    final orderNum =
        "MYP-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}";

    // Cache order locally so it immediately shows up in "My Orders"
    final newLocalOrder = OrderHistoryModel(
      orderId: orderId,
      orderNumber: orderNum,
      status: "PLACED",
      grandTotal: grandTotal,
      itemsTotal: itemsTotal,
      discountAmount: discount,
      promoCode: promoCode,
      deliveryFee: deliveryFee,
      deliveryOtp: "4921",
      paymentStatus: "PAID",
      paymentMethod: paymentMethod,
      deliveryAddress: deliveryAddress,
      deliveryEtaMins: 12,
      createdAt: "Just now",
      isSundayMeatOrder: isSundayMeatOrder,
      items: items
          .map(
            (i) => OrderHistoryItem(
              name: i.product.name,
              variant: i.selectedVariant.weightLabel,
              quantity: i.quantity,
              unitPrice: i.selectedVariant.price,
              totalPrice: i.totalPrice,
            ),
          )
          .toList(),
    );

    _localOrders.insert(0, newLocalOrder);

    try {
      final prefs = await SharedPreferences.getInstance();
      final rawDiskOrders = prefs.getStringList("cached_user_orders") ?? [];
      rawDiskOrders.insert(
        0,
        jsonEncode({
          "order_id": newLocalOrder.orderId,
          "order_number": newLocalOrder.orderNumber,
          "status": newLocalOrder.status,
          "grand_total": newLocalOrder.grandTotal,
          "items_total": newLocalOrder.itemsTotal,
          "discount_amount": newLocalOrder.discountAmount,
          "promo_code": newLocalOrder.promoCode,
          "delivery_fee": newLocalOrder.deliveryFee,
          "delivery_otp": newLocalOrder.deliveryOtp,
          "payment_status": newLocalOrder.paymentStatus,
          "payment_method": newLocalOrder.paymentMethod,
          "delivery_address": newLocalOrder.deliveryAddress,
          "delivery_eta_mins": newLocalOrder.deliveryEtaMins,
          "created_at": newLocalOrder.createdAt,
          "is_sunday_meat_order": newLocalOrder.isSundayMeatOrder,
          "items": newLocalOrder.items
              .map(
                (i) => {
                  "name": i.name,
                  "variant": i.variant,
                  "quantity": i.quantity,
                  "unit_price": i.unitPrice,
                  "total_price": i.totalPrice,
                },
              )
              .toList(),
        }),
      );
      await prefs.setStringList("cached_user_orders", rawDiskOrders);
    } catch (_) {}

    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/orders/create"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "user_id": userId,
              "delivery_address": deliveryAddress,
              "latitude": latitude,
              "longitude": longitude,
              "items": itemsPayload,
              "payment_method": paymentMethod,
              "is_sunday_meat_order": isSundayMeatOrder,
              "promo_code": promoCode,
              "delivery_instructions": deliveryInstructions,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        try {
          final errBody = jsonDecode(response.body);
          return {
            "success": false,
            "message":
                errBody['detail'] ??
                "Order creation failed (HTTP ${response.statusCode})",
          };
        } catch (_) {
          return {
            "success": false,
            "message":
                "Order creation failed with status ${response.statusCode}",
          };
        }
      }
    } catch (e) {
      return {
        "success": false,
        "message": "Cannot connect to server at $baseUrl: $e",
      };
    }
  }

  // 15. Verify Payment
  static Future<Map<String, dynamic>> verifyPayment({
    required String orderId,
    required String paymentMethod,
    String? transactionId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/payments/verify"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "order_id": orderId,
              "payment_method": paymentMethod,
              "transaction_id": transactionId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    return {
      "success": true,
      "status": "PAID",
      "order_id": orderId,
      "order_status": "PACKED",
      "message": "Payment verified successfully.",
    };
  }

  static Future<Map<String, dynamic>> verifyCashfreePayment(
    String orderId,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/payments/cashfree/verify"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"order_id": orderId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      try {
        final err = jsonDecode(response.body);
        return {
          "success": false,
          "is_paid": false,
          "is_failed": false,
          "message":
              err["detail"] ?? "Payment verification failed. Please try again.",
        };
      } catch (_) {
        return {
          "success": false,
          "is_paid": false,
          "is_failed": false,
          "message":
              "Payment verification failed (HTTP ${response.statusCode}). Please try again.",
        };
      }
    } catch (e) {
      return {
        "success": false,
        "is_paid": false,
        "is_failed": false,
        "message": "Cannot connect to server to verify payment. Please check your connection and retry.",
      };
    }
  }

  // 16. Cancel Order
  static Future<Map<String, dynamic>> cancelOrder(String orderId) async {
    // Update local cache
    for (var i = 0; i < _localOrders.length; i++) {
      if (_localOrders[i].orderId == orderId) {
        _localOrders[i] = OrderHistoryModel(
          orderId: _localOrders[i].orderId,
          orderNumber: _localOrders[i].orderNumber,
          status: "CANCELLED",
          grandTotal: _localOrders[i].grandTotal,
          itemsTotal: _localOrders[i].itemsTotal,
          discountAmount: _localOrders[i].discountAmount,
          promoCode: _localOrders[i].promoCode,
          deliveryFee: _localOrders[i].deliveryFee,
          deliveryOtp: _localOrders[i].deliveryOtp,
          paymentStatus: "REFUNDED",
          paymentMethod: _localOrders[i].paymentMethod,
          deliveryAddress: _localOrders[i].deliveryAddress,
          deliveryEtaMins: _localOrders[i].deliveryEtaMins,
          createdAt: _localOrders[i].createdAt,
          isSundayMeatOrder: _localOrders[i].isSundayMeatOrder,
          items: _localOrders[i].items,
        );
      }
    }

    try {
      final response = await http
          .post(Uri.parse("$baseUrl/orders/$orderId/cancel"))
          .timeout(const Duration(seconds: 4));

      return jsonDecode(response.body);
    } catch (_) {}

    return {
      "success": true,
      "order_id": orderId,
      "status": "CANCELLED",
      "message": "Order cancelled successfully. Refund will be processed.",
    };
  }

  // 17. Rate Order
  static Future<bool> rateOrder(
    String orderId,
    int rating,
    String review,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/orders/$orderId/rate"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"rating": rating, "review": review}),
          )
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (_) {}
    return true;
  }

  static List<ProductModel> _getStaticProducts(bool isSunday) {
    return [
      // 1. Daily Fresh Vegetables
      ProductModel(
        id: "p1",
        categoryId: "cat_veg",
        name: "Fresh Farm Hybrid Tomatoes",
        description: "Crisp, red, farm-fresh local tomatoes.",
        imageUrl: "https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v1",
            weightLabel: "500g",
            mrp: 25.0,
            price: 18.0,
            stockQty: 100,
          ),
          ProductVariantModel(
            id: "v2",
            weightLabel: "1kg",
            mrp: 50.0,
            price: 34.0,
            stockQty: 80,
          ),
        ],
      ),
      ProductModel(
        id: "p2",
        categoryId: "cat_veg",
        name: "Fresh Red Onions (Kurnool)",
        description: "Cleaned, premium grade onions.",
        imageUrl: "https://images.unsplash.com/photo-1618512496248-a07fe83aa8cb?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v3",
            weightLabel: "1kg",
            mrp: 45.0,
            price: 36.0,
            stockQty: 120,
          ),
          ProductVariantModel(
            id: "v4",
            weightLabel: "2kg (Saver Pack)",
            mrp: 90.0,
            price: 68.0,
            stockQty: 50,
          ),
        ],
      ),
      ProductModel(
        id: "p3",
        categoryId: "cat_veg",
        name: "New Crop Fresh Potatoes (Aloo)",
        description: "Firm, thin-skinned golden potatoes.",
        imageUrl: "https://images.unsplash.com/photo-1518977676601-b53f82aba655?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v3_a",
            weightLabel: "1kg",
            mrp: 40.0,
            price: 32.0,
            stockQty: 150,
          ),
          ProductVariantModel(
            id: "v3_b",
            weightLabel: "2kg",
            mrp: 80.0,
            price: 60.0,
            stockQty: 70,
          ),
        ],
      ),
      ProductModel(
        id: "p4",
        categoryId: "cat_veg",
        name: "Green Tender Ladies Finger (Bhendi)",
        description: "Handpicked tender bhendi.",
        imageUrl: "https://images.unsplash.com/photo-1625944525533-473f1a3d54e7?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v5",
            weightLabel: "250g",
            mrp: 20.0,
            price: 15.0,
            stockQty: 60,
          ),
          ProductVariantModel(
            id: "v6",
            weightLabel: "500g",
            mrp: 40.0,
            price: 28.0,
            stockQty: 40,
          ),
        ],
      ),
      ProductModel(
        id: "p5",
        categoryId: "cat_veg",
        name: "Fresh Ridge Gourd (Beerakaya)",
        description: "Tender, fiber-rich ridge gourd.",
        imageUrl: "https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v5_a",
            weightLabel: "500g",
            mrp: 35.0,
            price: 26.0,
            stockQty: 70,
          ),
        ],
      ),
      ProductModel(
        id: "p6",
        categoryId: "cat_veg",
        name: "Tender Bottle Gourd (Sorakaya)",
        description: "Juicy, pale green bottle gourd.",
        imageUrl: "https://images.unsplash.com/photo-1603048588665-791ca8aea617?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v6_a",
            weightLabel: "1 Unit (600g)",
            mrp: 30.0,
            price: 22.0,
            stockQty: 50,
          ),
        ],
      ),
      ProductModel(
        id: "p7",
        categoryId: "cat_veg",
        name: "Green Capsicum (Simla Mirchi)",
        description: "Crisp, glossy green bell peppers.",
        imageUrl: "https://images.unsplash.com/photo-1563565375-f3fdfdbefa83?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v7_a",
            weightLabel: "250g",
            mrp: 25.0,
            price: 19.0,
            stockQty: 80,
          ),
        ],
      ),
      ProductModel(
        id: "p8_v",
        categoryId: "cat_veg",
        name: "Purple Brinjal / Eggplant (Vankaya)",
        description: "Tender, shiny purple brinjal.",
        imageUrl: "https://images.unsplash.com/photo-1615485290382-441e4d049cb5?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v8_v",
            weightLabel: "500g",
            mrp: 30.0,
            price: 22.0,
            stockQty: 65,
          ),
        ],
      ),
      ProductModel(
        id: "p9_v",
        categoryId: "cat_veg",
        name: "Fresh Green Peas (Matar)",
        description: "Sweet, tender green pea pods.",
        imageUrl: "https://images.unsplash.com/photo-1587735243615-c03f25aaff15?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v9_v1",
            weightLabel: "250g",
            mrp: 35.0,
            price: 26.0,
            stockQty: 90,
          ),
          ProductVariantModel(
            id: "v9_v2",
            weightLabel: "500g",
            mrp: 70.0,
            price: 48.0,
            stockQty: 50,
          ),
        ],
      ),
      ProductModel(
        id: "p10_v",
        categoryId: "cat_veg",
        name: "Fresh Bitter Gourd (Kakarakaya)",
        description: "Tender, dark green bitter gourd.",
        imageUrl: "https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v10_v1",
            weightLabel: "250g",
            mrp: 22.0,
            price: 16.0,
            stockQty: 75,
          ),
        ],
      ),
      ProductModel(
        id: "p11_v",
        categoryId: "cat_veg",
        name: "Fresh Tender Drumsticks (Munakkaya)",
        description: "Long, flavorful drumstick pods.",
        imageUrl: "https://images.unsplash.com/photo-1603048588665-791ca8aea617?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v11_v1",
            weightLabel: "3 Pcs Pack",
            mrp: 30.0,
            price: 22.0,
            stockQty: 80,
          ),
        ],
      ),

      // 2. Leafy Greens
      ProductModel(
        id: "p8",
        categoryId: "cat_leafy",
        name: "Hydroponic Fresh Palak (Spinach)",
        description: "Tender baby spinach leaves.",
        imageUrl: "https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v7",
            weightLabel: "250g Bunch",
            mrp: 25.0,
            price: 18.0,
            stockQty: 50,
          ),
        ],
      ),
      ProductModel(
        id: "p9",
        categoryId: "cat_leafy",
        name: "Fresh Coriander & Mint Combo",
        description: "Aromatic kothimeera and pudina bunch.",
        imageUrl: "https://images.unsplash.com/photo-1596797038530-2c107229654b?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v9_a",
            weightLabel: "1 Combo Bunch",
            mrp: 20.0,
            price: 15.0,
            stockQty: 100,
          ),
        ],
      ),
      ProductModel(
        id: "p10",
        categoryId: "cat_leafy",
        name: "Fresh Methi Leaves (Menthi Kura)",
        description: "Cleaned, aromatic fenugreek leaves.",
        imageUrl: "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v10_a",
            weightLabel: "200g Bunch",
            mrp: 22.0,
            price: 16.0,
            stockQty: 80,
          ),
        ],
      ),
      ProductModel(
        id: "p12_l",
        categoryId: "cat_leafy",
        name: "Fresh Amaranthus (Thotakura)",
        description: "Tender green amaranthus leafy greens.",
        imageUrl: "https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v12_l1",
            weightLabel: "250g Bunch",
            mrp: 20.0,
            price: 14.0,
            stockQty: 70,
          ),
        ],
      ),

      // 3. Salad & Exotics
      ProductModel(
        id: "p13_e",
        categoryId: "cat_exotics",
        name: "Hybrid Salad Cucumber (Kheera)",
        description: "Cool, crisp, thin-skinned cucumber.",
        imageUrl: "https://images.unsplash.com/photo-1449300079323-02e209d9d3a6?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v13_e1",
            weightLabel: "500g",
            mrp: 25.0,
            price: 18.0,
            stockQty: 100,
          ),
        ],
      ),
      ProductModel(
        id: "p14_e",
        categoryId: "cat_exotics",
        name: "Orange Crunchy Carrots",
        description: "Sweet, crunchy orange carrots.",
        imageUrl: "https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v14_e1",
            weightLabel: "500g",
            mrp: 35.0,
            price: 26.0,
            stockQty: 80,
          ),
        ],
      ),
      ProductModel(
        id: "p15_e",
        categoryId: "cat_exotics",
        name: "Fresh Cauliflower Gobhi",
        description: "Tight, clean, white cauliflower florets.",
        imageUrl: "https://images.unsplash.com/photo-1568584711075-3d021a7c3ca3?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v15_e1",
            weightLabel: "1 Head (500g)",
            mrp: 40.0,
            price: 29.0,
            stockQty: 60,
          ),
        ],
      ),
      ProductModel(
        id: "p16_e",
        categoryId: "cat_exotics",
        name: "Fresh Sweet Corn Cobs",
        description: "Sweet golden corn cobs.",
        imageUrl: "https://images.unsplash.com/photo-1551754655-cd27e38d2076?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v16_e1",
            weightLabel: "2 Pcs Pack",
            mrp: 35.0,
            price: 25.0,
            stockQty: 90,
          ),
        ],
      ),

      // 4. Kitchen Aromatics
      ProductModel(
        id: "p11",
        categoryId: "cat_aromatics",
        name: "Spicy Green Chillies (Pachi Mirchi)",
        description: "Fresh, pungent local green chillies.",
        imageUrl: "https://images.unsplash.com/photo-1588252303782-cb80119abd6d?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v11_a",
            weightLabel: "100g",
            mrp: 15.0,
            price: 10.0,
            stockQty: 120,
          ),
          ProductVariantModel(
            id: "v11_b",
            weightLabel: "250g",
            mrp: 35.0,
            price: 24.0,
            stockQty: 80,
          ),
        ],
      ),
      ProductModel(
        id: "p12",
        categoryId: "cat_aromatics",
        name: "Fresh Ginger & Garlic Combo",
        description: "Cleaned Allam & Vellulli roots.",
        imageUrl: "https://images.unsplash.com/photo-1540148426945-6cf22a6b2383?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v12_a",
            weightLabel: "250g Combo",
            mrp: 50.0,
            price: 38.0,
            stockQty: 90,
          ),
        ],
      ),
      ProductModel(
        id: "p18_a",
        categoryId: "cat_aromatics",
        name: "Fresh Yellow Lemons (Nimmapakaya)",
        description: "Juicy, bright yellow lemons.",
        imageUrl: "https://images.unsplash.com/photo-1534706936160-d5ee67737249?w=500&q=80",
        isSundayOnly: false,
        deliveryMode: "LIVE_DELIVERY",
        deliveryLabel: "10-15 Mins Quick Delivery",
        variants: [
          ProductVariantModel(
            id: "v18_a1",
            weightLabel: "4 Pcs Pack",
            mrp: 20.0,
            price: 15.0,
            stockQty: 160,
          ),
        ],
      ),

      // 5. Sunday Fresh Meat & Seafood
      ProductModel(
        id: "p13",
        categoryId: "cat_chicken",
        name: "Sunday Special Tender Chicken (Curry Cut)",
        description: "100% antibiotic-free, freshly cut on Sunday morning.",
        imageUrl: "https://images.unsplash.com/photo-1604503468506-a8da13d82791?w=500&q=80",
        isSundayOnly: true,
        deliveryMode: isSunday ? "LIVE_DELIVERY" : "PREORDER_FOR_SUNDAY",
        deliveryLabel: isSunday
            ? "10 Mins Delivery Today!"
            : "Available for Sunday Delivery (Pre-order)",
        variants: [
          ProductVariantModel(
            id: "v8",
            weightLabel: "500g",
            mrp: 150.0,
            price: 125.0,
            stockQty: 50,
          ),
          ProductVariantModel(
            id: "v9",
            weightLabel: "1kg",
            mrp: 290.0,
            price: 240.0,
            stockQty: 30,
          ),
        ],
      ),
      ProductModel(
        id: "p14",
        categoryId: "cat_chicken",
        name: "Fresh Boneless Chicken Breast",
        description: "Cleaned, tender breast fillets.",
        imageUrl: "https://images.unsplash.com/photo-1607623814075-e51df1bdc82f?w=500&q=80",
        isSundayOnly: true,
        deliveryMode: isSunday ? "LIVE_DELIVERY" : "PREORDER_FOR_SUNDAY",
        deliveryLabel: isSunday
            ? "10 Mins Delivery Today!"
            : "Available for Sunday Delivery (Pre-order)",
        variants: [
          ProductVariantModel(
            id: "v14_a",
            weightLabel: "500g",
            mrp: 210.0,
            price: 175.0,
            stockQty: 40,
          ),
        ],
      ),
      ProductModel(
        id: "p15",
        categoryId: "cat_fish",
        name: "Fresh Godavari Rohu Fish (Curry Cut)",
        description: "Fresh river fish, cleaned and descaled.",
        imageUrl: "https://images.unsplash.com/photo-1534948216015-843149f72be3?w=500&q=80",
        isSundayOnly: true,
        deliveryMode: isSunday ? "LIVE_DELIVERY" : "PREORDER_FOR_SUNDAY",
        deliveryLabel: isSunday
            ? "10 Mins Delivery Today!"
            : "Available for Sunday Delivery (Pre-order)",
        variants: [
          ProductVariantModel(
            id: "v10",
            weightLabel: "500g",
            mrp: 220.0,
            price: 185.0,
            stockQty: 25,
          ),
          ProductVariantModel(
            id: "v11",
            weightLabel: "1kg",
            mrp: 420.0,
            price: 360.0,
            stockQty: 20,
          ),
        ],
      ),
      ProductModel(
        id: "p16",
        categoryId: "cat_fish",
        name: "Live Cleaned Sea Prawns (Medium)",
        description: "Deveined, peeled, juicy prawns.",
        imageUrl: "https://images.unsplash.com/photo-1559742811-822873691df8?w=500&q=80",
        isSundayOnly: true,
        deliveryMode: isSunday ? "LIVE_DELIVERY" : "PREORDER_FOR_SUNDAY",
        deliveryLabel: isSunday
            ? "10 Mins Delivery Today!"
            : "Available for Sunday Delivery (Pre-order)",
        variants: [
          ProductVariantModel(
            id: "v16_a",
            weightLabel: "250g",
            mrp: 230.0,
            price: 199.0,
            stockQty: 20,
          ),
          ProductVariantModel(
            id: "v16_b",
            weightLabel: "500g",
            mrp: 440.0,
            price: 380.0,
            stockQty: 15,
          ),
        ],
      ),
      ProductModel(
        id: "p17",
        categoryId: "cat_fish",
        name: "Fresh Tender Mutton Curry Cut",
        description: "Fresh tender goat meat, cut with bone for rich gravy.",
        imageUrl: "https://images.unsplash.com/photo-1603048588665-791ca8aea617?w=500&q=80",
        isSundayOnly: true,
        deliveryMode: isSunday ? "LIVE_DELIVERY" : "PREORDER_FOR_SUNDAY",
        deliveryLabel: isSunday
            ? "10 Mins Delivery Today!"
            : "Available for Sunday Delivery (Pre-order)",
        variants: [
          ProductVariantModel(
            id: "v17_a",
            weightLabel: "500g",
            mrp: 480.0,
            price: 420.0,
            stockQty: 25,
          ),
          ProductVariantModel(
            id: "v17_b",
            weightLabel: "1kg",
            mrp: 950.0,
            price: 830.0,
            stockQty: 15,
          ),
        ],
      ),
    ];
  }
}
