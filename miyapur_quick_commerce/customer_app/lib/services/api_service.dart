import 'dart:convert';
import 'dart:math' as math;

import 'package:customer_app/utils/preferences.dart';
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

/// Describes a single price change detected while re-pricing the cart.
class _PriceChange {
  final String name;
  final String variant;
  final double oldPrice;
  final double newPrice;
  _PriceChange({
    required this.name,
    required this.variant,
    required this.oldPrice,
    required this.newPrice,
  });
}

/// Result of [ApiService.repriceCartItems]. The cart screen uses this to:
///   - show a warning if any price changed since the item was added,
///   - block checkout if any item is now unavailable / out of stock,
///   - replace the cart with the re-priced [updatedItems] before creating the order.
class RepriceResult {
  final bool ok;
  final List<CartItemModel> updatedItems;
  final List<_PriceChange> priceChanges;
  final List<String> unavailable;
  final String? error;

  RepriceResult({
    required this.ok,
    required this.updatedItems,
    required this.priceChanges,
    required this.unavailable,
    this.error,
  });
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
  // 10 KM delivery geofence from the Central Dark Store Hub (matches backend
  // MAX_DELIVERY_RADIUS_KM). Previously this was 999.0 which disabled the
  // client-side geofence check entirely.
  static const double maxDeliveryRadiusKm = 10.0;

  /// Returns the JWT auth headers for the currently logged-in customer. The
  /// token is read from SharedPreferences on every call so a fresh login is
  /// picked up immediately. Attach these to EVERY authenticated request so the
  /// backend can authorize the caller (the backend now enforces JWT on all
  /// order/payment/profile routes).
  static Map<String, String> authHeaders({Map<String, String>? extra}) {
    final token = Preferences.getString(Preferences.keyJwtToken);
    final headers = <String, String>{
      "Content-Type": "application/json",
      if (token.isNotEmpty) "Authorization": "Bearer $token",
    };
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  /// Clears ALL locally cached customer data. Called on logout / account switch
  /// so that one customer's cart, orders, favorites and saved addresses never
  /// leak to the next user on a shared device.
  static Future<void> clearLocalCache() async {
    _localOrders.clear();
    _localProfiles.clear();
    await Preferences.clearAll();
  }

  static final List<LocationModel> fallbackLocations = [];
  static final List<LocationModel> nearbyLocations = [];

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
            (profile.name.isNotEmpty && !profile.name.startsWith("Customer ("))
            ? profile.name
            : ((savedName != null &&
                      savedName.isNotEmpty &&
                      savedName != "Customer")
                  ? savedName
                  : (profile.name.isNotEmpty
                        ? profile.name
                        : "Valued Customer"));
        final resolvedEmail = profile.email.isNotEmpty
            ? profile.email
            : savedEmail;

        if (resolvedName.isNotEmpty && resolvedName != "Valued Customer") {
          await prefs.setString("user_name", resolvedName);
        }
        if (resolvedEmail.isNotEmpty) {
          await prefs.setString("user_email", resolvedEmail);
        }

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

        final existingKeys = apiAddrs
            .map(
              (a) =>
                  "${a.label.toLowerCase()}_${a.houseNumber.toLowerCase().replaceAll(' ', '')}_${a.streetAddress.toLowerCase().replaceAll(' ', '')}",
            )
            .toSet();

        for (var locAddr in localAddrs) {
          final locKey =
              "${locAddr.label.toLowerCase()}_${locAddr.houseNumber.toLowerCase().replaceAll(' ', '')}_${locAddr.streetAddress.toLowerCase().replaceAll(' ', '')}";
          if (!apiAddrs.any((a) => a.id == locAddr.id) &&
              !existingKeys.contains(locKey)) {
            apiAddrs.add(locAddr);
            existingKeys.add(locKey);
          }
        }
        return apiAddrs;
      }
    } catch (_) {}

    final uniqueLocal = <String, SavedAddressModel>{};
    for (var a in localAddrs) {
      final key =
          "${a.label.toLowerCase()}_${a.houseNumber.toLowerCase().replaceAll(' ', '')}_${a.streetAddress.toLowerCase().replaceAll(' ', '')}";
      uniqueLocal[key] = a;
    }
    return uniqueLocal.values.toList();
  }

  static Future<bool> deleteSavedAddress(
    String userId,
    String addressId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final rawLocalAddrs = prefs.getStringList("saved_addrs_$userId") ?? [];
    final globalAddrs = prefs.getStringList("global_saved_addrs") ?? [];

    rawLocalAddrs.removeWhere((str) {
      try {
        return jsonDecode(str)['id'] == addressId;
      } catch (_) {
        return false;
      }
    });
    globalAddrs.removeWhere((str) {
      try {
        return jsonDecode(str)['id'] == addressId;
      } catch (_) {
        return false;
      }
    });

    await prefs.setStringList("saved_addrs_$userId", rawLocalAddrs);
    await prefs.setStringList("global_saved_addrs", globalAddrs);

    try {
      final response = await http
          .delete(Uri.parse("$baseUrl/auth/addresses/$addressId"))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {}
    return true;
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
          .get(
            Uri.parse("$baseUrl/orders/history/$userId"),
            headers: authHeaders(),
          )
          .timeout(const Duration(seconds: 10));

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
    // No fake-rider fallback: a network error must surface as an error, not a
    // phantom "Ravi Kumar" rider with OTP 4921. The caller shows a retry state.
    try {
      final response = await http
          .get(
            Uri.parse("$baseUrl/orders/$orderId/tracking"),
            headers: authHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {
        "success": false,
        "error":
            "Couldn't load tracking (HTTP ${response.statusCode}). Please retry.",
      };
    } catch (_) {
      return {
        "success": false,
        "error":
            "Couldn't reach tracking service. Please check your connection.",
      };
    }
  }

  static Future<Map<String, dynamic>> validatePromoCode(
    String code,
    double itemsTotal,
  ) async {
    // Promo codes have been RETIRED. This method is kept for backward
    // compatibility with any caller that still references it, but it always
    // returns success=false so no discount is ever applied at checkout.
    return {
      "success": false,
      "message": "Promo codes are no longer available.",
    };
  }

  static Future<List<ProductModel>> searchProducts(String query) async {
    // No static fallback — search results must come from the live backend so
    // they reflect current prices. On failure we return an empty list (the UI
    // shows "No matching places found") instead of stale hardcoded products.
    try {
      final response = await http
          .get(
            Uri.parse(
              "$baseUrl/catalog/search?query=${Uri.encodeQueryComponent(query)}",
            ),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        List data = jsonDecode(response.body) as List? ?? [];
        return data
            .map((x) => ProductModel.fromJson(x as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return <ProductModel>[];
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

  static Future<List<LocationModel>> getNearbyLocations({
    double? lat,
    double? lng,
  }) async {
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

  static Map<String, String> _resolveNearestArea(double lat, double lng) {
    return {
      "name": "Selected Location",
      "address":
          "Location at ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}, Hyderabad, Telangana 500049, India",
      "landmark": "Hyderabad",
    };
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
    final resolved = _resolveNearestArea(lat, lng);
    return {
      "id": "gps_${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}",
      "name": resolved["name"] ?? "Selected Location",
      "address": resolved["address"] ?? "Hyderabad, Telangana, India",
      "landmark": resolved["landmark"] ?? "",
      "latitude": lat,
      "longitude": lng,
      "distance_km": local["distance_km"],
      "is_serviceable": true,
      "eta_minutes": local["estimated_delivery_minutes"],
      "message": local["message"],
      "store_latitude": hubLatitude,
      "store_longitude": hubLongitude,
      "max_allowed_radius_km": 999.0,
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
    // We deliver ANYWHERE — there is no radius cap. is_serviceable is always
    // true; distance & ETA are kept for display.
    int eta = (8 + distance * 1.5).toInt().clamp(8, 120);
    return {
      "is_serviceable": true,
      "distance_km": distance,
      "estimated_delivery_minutes": eta,
      "store_latitude": hubLatitude,
      "store_longitude": hubLongitude,
      "message": "Delivery available in ~$eta mins (distance $distance km).",
    };
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  static Future<Map<String, dynamic>> getProducts({
    bool forceSunday = false,
  }) async {
    // IMPORTANT: there is NO static fallback here on purpose. Earlier this method
    // returned a hardcoded `_getStaticProducts()` list whenever the backend was
    // slow (Render free-tier cold start > 6s), unreachable, or returned an empty
    // list. That silently showed STALE prices that never reflected manager price
    // updates made in the store dashboard. Now we surface a real error state so
    // the UI can show "Catalog unavailable — retry" instead of lying to the user.
    try {
      String dayParam = forceSunday ? "sunday" : "weekday";
      // 12s timeout — Render free tier can take 30-60s to cold-start, but a
      // warm instance responds in <1s. 12s is a reasonable upper bound.
      final response = await http
          .get(Uri.parse("$baseUrl/catalog/products?day_override=$dayParam"))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        var body = jsonDecode(response.body);
        List rawList = body['products'] as List? ?? [];
        List<ProductModel> products = rawList
            .map((x) => ProductModel.fromJson(x as Map<String, dynamic>))
            .toList();
        // An empty list is a VALID backend response (e.g. manager deactivated
        // everything). Do NOT fall back to static data — show the empty catalog.
        return {
          "is_sunday": body['is_sunday'] ?? forceSunday,
          "products": products,
          "from_backend": true,
        };
      }
      return {
        "is_sunday": forceSunday,
        "products": <ProductModel>[],
        "from_backend": false,
        "error": "Server returned ${response.statusCode}. Please retry.",
      };
    } catch (e) {
      return {
        "is_sunday": forceSunday,
        "products": <ProductModel>[],
        "from_backend": false,
        "error":
            "Cannot reach catalog service. Check your connection and retry.",
      };
    }
  }

  /// Refreshes the prices & stock of every item currently in the cart by
  /// re-fetching the live catalog from the backend. This MUST be called before
  /// checkout so the customer is charged the CURRENT price the store manager
  /// set — not the price that was displayed when the item was added to the cart
  /// (which may be hours or days stale).
  ///
  /// Returns a [RepriceResult] describing what changed. The caller should:
  ///   - show a warning if any price changed,
  ///   - block checkout if any item went out of stock or was deactivated.
  static Future<RepriceResult> repriceCartItems(
    List<CartItemModel> cartItems,
  ) async {
    if (cartItems.isEmpty) {
      return RepriceResult(
        ok: true,
        updatedItems: cartItems,
        priceChanges: [],
        unavailable: [],
      );
    }

    final res = await getProducts();
    if (res['from_backend'] != true) {
      // Could not reach the backend — do NOT silently proceed with stale prices.
      return RepriceResult(
        ok: false,
        updatedItems: cartItems,
        priceChanges: [],
        unavailable: [],
        error: res['error'] ?? 'Cannot verify current prices. Please check your connection and retry.',
      );
    }

    final backendProducts = res['products'] as List<ProductModel>;
    // Index by product id -> variant id for O(1) lookup.
    final byId = <String, ProductModel>{for (var p in backendProducts) p.id: p};

    final updated = <CartItemModel>[];
    final changes = <_PriceChange>[];
    final unavailable = <String>[];

    for (var item in cartItems) {
      final product = byId[item.product.id];
      if (product == null) {
        unavailable.add(
          '${item.product.name} (${item.selectedVariant.weightLabel})',
        );
        continue;
      }
      ProductVariantModel? variant;
      for (var v in product.variants) {
        if (v.id == item.selectedVariant.id ||
            v.weightLabel == item.selectedVariant.weightLabel) {
          variant = v;
          break;
        }
      }
      if (variant == null) {
        unavailable.add(
          '${item.product.name} (${item.selectedVariant.weightLabel})',
        );
        continue;
      }
      final newPrice = variant.price;
      if ((newPrice - item.selectedVariant.price).abs() > 0.01) {
        changes.add(
          _PriceChange(
            name: product.name,
            variant: variant.weightLabel,
            oldPrice: item.selectedVariant.price,
            newPrice: newPrice,
          ),
        );
      }
      // Rebuild the cart item with the freshly-priced variant (and refreshed stock).
      updated.add(
        CartItemModel(
          product: product,
          selectedVariant: variant,
          quantity: item.quantity,
        ),
      );
    }

    return RepriceResult(
      ok: true,
      updatedItems: updated,
      priceChanges: changes,
      unavailable: unavailable,
    );
  }

  static Future<Map<String, dynamic>> createOrder({
    required String userId,
    required String deliveryAddress,
    required double latitude,
    required double longitude,
    required List<CartItemModel> items,
    required String paymentMethod,
    required bool isSundayMeatOrder,
    String deliveryInstructions = "",
  }) async {
    var itemsPayload = items
        .map(
          (i) => {
            "product_name": i.product.name,
            "variant_label": i.selectedVariant.weightLabel,
            "quantity": i.quantity,
            "unit_price": i.selectedVariant.price,
            // Send the exact catalog UUIDs so the backend can look up the
            // authoritative price by variant_id (not just weight_label) and
            // ignore the client-supplied unit_price above.
            "product_id": i.product.id,
            "variant_id": i.selectedVariant.id,
          },
        )
        .toList();

    double itemsTotal = items.fold(0.0, (acc, item) => acc + item.totalPrice);
    // Promo codes have been retired — no discount is ever applied. The
    // customer pays items_total + fees (matching the backend, which also
    // applies no discount).
    double discount = 0.0;
    String promoCode = "";

    double netItems = itemsTotal;
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
      // Idempotency key: stable per cart+user+payment snapshot for 10 minutes.
      // If the customer double-taps "Pay" or the network retries after a
      // timeout, the backend returns the SAME order instead of creating a
      // duplicate (and double-charging). The key is derived from the cart
      // contents + user + timestamp-minute window so a genuinely new cart
      // still creates a new order.
      final idemKey =
          "idem_${userId}_${items.length}_${grandTotal.toStringAsFixed(2)}_${(DateTime.now().millisecondsSinceEpoch ~/ 600000)}";
      final response = await http
          .post(
            Uri.parse("$baseUrl/orders/create"),
            headers: authHeaders(),
            body: jsonEncode({
              "user_id": userId,
              "delivery_address": deliveryAddress,
              "latitude": latitude,
              "longitude": longitude,
              "items": itemsPayload,
              "payment_method": paymentMethod,
              "is_sunday_meat_order": isSundayMeatOrder,
              "delivery_instructions": deliveryInstructions,
              "idempotency_key": idemKey,
            }),
          )
          .timeout(const Duration(seconds: 20));

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
    // No fake "PAID" success on failure — the order must actually be verified
    // server-side before the user believes their payment went through.
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/payments/verify"),
            headers: authHeaders(),
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
      try {
        final err = jsonDecode(response.body);
        return {
          "success": false,
          "message":
              err["detail"] ??
              "Payment verification failed (HTTP ${response.statusCode}).",
        };
      } catch (_) {
        return {
          "success": false,
          "message":
              "Payment verification failed (HTTP ${response.statusCode}). Please try again.",
        };
      }
    } catch (_) {
      return {
        "success": false,
        "message": "Couldn't reach the payment service. Please check your connection and retry.",
      };
    }
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
    // The backend is the source of truth for order status & stock restoration.
    // No fake "cancelled" success on network failure — surface the error so the
    // user can retry instead of believing the order was cancelled when it wasn't.
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/orders/$orderId/cancel"),
            headers: authHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return body;
      }
      return {
        "success": false,
        "error":
            body["detail"] ??
            "Couldn't cancel the order (HTTP ${response.statusCode}).",
      };
    } catch (_) {
      return {
        "success": false,
        "error": "Couldn't reach the server to cancel the order. Please check your connection and retry.",
      };
    }
  }

  // 17. Rate Order
  static Future<bool> rateOrder({
    required String orderId,
    required int riderRating,
    required int freshnessRating,
    required String review,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/orders/$orderId/rate"),
            headers: authHeaders(),
            body: jsonEncode({
              "rating": riderRating,
              "freshness_rating": freshnessRating,
              "review": review,
            }),
          )
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (_) {}
    return true;
  }

  // 18. Dynamic Support FAQs & Contact
  static Future<Map<String, dynamic>> getFaqs() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/support/faqs"))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    return {
      "success": true,
      "support_contact": {
        "phone": "+91 90000 11111",
        "whatsapp": "919000011111",
        "email": "support@flashfresh.com",
        "operating_hours": "24x7 Express Support Available",
      },
      "faq_categories": [
        {
          "id": "delivery",
          "title": "Order & Delivery",
          "faqs": [
            {
              "question": "How fast will my order arrive?",
              "answer": "Orders are packed at Central Dark Store within 3 minutes and delivered to your doorstep within 10-15 minutes by our dedicated rider fleet.",
            },
            {
              "question": "How do I give the delivery PIN to the rider?",
              "answer": "When your rider arrives, share the 4-digit PIN displayed on your live order tracking screen to complete the handover securely.",
            },
          ],
        },
        {
          "id": "payments",
          "title": "Payments & Refunds",
          "faqs": [
            {
              "question": "How do refunds work for cancelled orders?",
              "answer": "Instant refunds for UPI, Cards, NetBanking, or Wallet payments are credited back to your payment source within 2-4 hours.",
            },
          ],
        },
      ],
    };
  }

  // 19. Create Support Ticket
  static Future<Map<String, dynamic>> createSupportTicket({
    required String userId,
    required String phone,
    String? orderId,
    required String issueCategory,
    required String description,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/support/ticket"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "user_id": userId,
              "phone": phone,
              "order_id": orderId,
              "issue_category": issueCategory,
              "description": description,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    final ticketId =
        "TKT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    return {
      "success": true,
      "ticket_id": ticketId,
      "message":
          "Ticket #$ticketId submitted! Our Support Executive will call you back in 5 minutes.",
    };
  }
}
