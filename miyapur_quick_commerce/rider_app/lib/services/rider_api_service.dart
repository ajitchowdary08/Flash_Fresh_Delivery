import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/rider_order.dart';
import '../utils/rider_preferences.dart';

class RiderApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: "https://flash-fresh.onrender.com/api/v1",
  );

  /// Auth headers — attaches the rider's JWT to every authenticated request.
  /// The backend now enforces role=RIDER on all /rider/* routes.
  static Map<String, String> _authHeaders({Map<String, String>? extra}) {
    final token = RiderPreferences.token;
    final headers = <String, String>{
      "Content-Type": "application/json",
      if (token.isNotEmpty) "Authorization": "Bearer $token",
    };
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  // 0. Login: send OTP to the rider's phone (riders share the customer OTP flow,
  // but the backend resolves their role=RIDER from the users table).
  static Future<Map<String, dynamic>> sendOtp(String phone) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/auth/send-otp"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"phone": phone}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "OTP send failed."};
    } catch (_) {
      return {
        "success": false,
        "message": "Couldn't reach the server. Please retry.",
      };
    }
  }

  // 0b. Verify OTP and persist the JWT token + rider identity.
  static Future<Map<String, dynamic>> verifyOtp(
    String phone,
    String otp,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/auth/verify-otp"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"phone": phone, "otp": otp}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body["success"] == true) {
          await RiderPreferences.setToken(body["token"] ?? "");
          await RiderPreferences.setRiderId(body["user_id"] ?? "");
          await RiderPreferences.setRiderPhone(body["phone"] ?? phone);
          await RiderPreferences.setRiderName(body["name"] ?? "Rider");
        }
        return body;
      }
      final err = jsonDecode(res.body);
      return {
        "success": false,
        "message": err["detail"] ?? "Verification failed.",
      };
    } catch (_) {
      return {
        "success": false,
        "message": "Couldn't reach the server. Please retry.",
      };
    }
  }

  // 1. Get Dynamic Rider Profile from Live Database
  static Future<Map<String, dynamic>> getProfile() async {
    // No fake "Ravi Kumar" fallback — a network error surfaces as an error so
    // the rider sees a retry prompt instead of an invented identity.
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/rider/profile"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {
        "success": false,
        "error": "Couldn't load profile (HTTP ${res.statusCode}).",
      };
    } catch (_) {
      return {
        "success": false,
        "error": "Couldn't reach the server. Please retry.",
      };
    }
  }

  // 2. Toggle Online/Offline Duty State
  static Future<Map<String, dynamic>> toggleDuty(bool isOnline) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/rider/duty"),
            headers: _authHeaders(),
            body: jsonEncode({"is_online": isOnline}),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {
        "success": false,
        "is_online": !isOnline,
        "message": "Duty toggle failed.",
      };
    } catch (_) {
      // CRITICAL FIX: previously returned the input `isOnline` on failure, so the
      // UI flipped to ONLINE while the server stayed OFFLINE — rider never got
      // orders. Now we report failure so the UI stays accurate.
      return {
        "success": false,
        "is_online": !isOnline,
        "message": "Couldn't reach the server.",
      };
    }
  }

  // 3. Get Real-Time Available Orders from Database
  static Future<List<RiderOrderModel>> getAvailableOrders() async {
    try {
      final res = await http
          .get(
            Uri.parse("$baseUrl/rider/orders/available"),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.map((x) => RiderOrderModel.fromJson(x)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  // 4. Accept Order Atomically
  static Future<Map<String, dynamic>> acceptOrder(String orderId) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/rider/orders/$orderId/accept"),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Accept failed."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server."};
    }
  }

  // 4b. Reject an order with a reason (NEW — production riders need this).
  static Future<Map<String, dynamic>> rejectOrder(
    String orderId,
    String reason,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/rider/orders/$orderId/reject"),
            headers: _authHeaders(),
            body: jsonEncode({"reason": reason}),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Reject failed."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server."};
    }
  }

  // 5. Pickup Order from Hub & Mark OUT_FOR_DELIVERY
  static Future<Map<String, dynamic>> pickupOrder(String orderId) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/rider/orders/$orderId/pickup"),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Pickup failed."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server."};
    }
  }

  // 6. Broadcast Real Live GPS Coordinates to Customer Map
  static Future<bool> updateLocation(
    String orderId,
    double lat,
    double lng,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/rider/location/update"),
            headers: _authHeaders(),
            body: jsonEncode({
              "order_id": orderId,
              "latitude": lat,
              "longitude": lng,
            }),
          )
          .timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 7. Verify Customer Delivery PIN against Live Database (Server Authoritative)
  static Future<Map<String, dynamic>> verifyDeliveryOtp(
    String orderId,
    String otp,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/rider/orders/verify-delivery"),
            headers: _authHeaders(),
            body: jsonEncode({"order_id": orderId, "otp": otp}),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {
        "success": false,
        "message": err["detail"] ?? "OTP verification failed.",
      };
    } catch (_) {
      return {
        "success": false,
        "message": "Couldn't reach the verification server.",
      };
    }
  }

  // 8. Dynamic Street Route Waypoints from Map Service
  static Future<List<Map<String, double>>> getRoutePoints({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final res = await http
          .get(
            Uri.parse(
              "$baseUrl/maps/route?origin_lat=$originLat&origin_lng=$originLng&dest_lat=$destLat&dest_lng=$destLng",
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["points"] is List) {
          return (data["points"] as List).map<Map<String, double>>((p) {
            return {
              "lat": (p["latitude"] as num).toDouble(),
              "lng": (p["longitude"] as num).toDouble(),
            };
          }).toList();
        }
      }
    } catch (_) {}

    // Straight-line interpolation fallback ONLY for the route geometry (not for
    // rider position — rider position always comes from real GPS).
    final List<Map<String, double>> fallback = [];
    for (int i = 0; i <= 12; i++) {
      final double t = i / 12.0;
      fallback.add({
        "lat": originLat + (destLat - originLat) * t,
        "lng": originLng + (destLng - originLng) * t,
      });
    }
    return fallback;
  }

  // 9. Get Dynamic Earnings, Milestones, and Floating Cash from DB
  static Future<Map<String, dynamic>> getEarnings() async {
    // No fabricated earnings/milestones fallback — a network error surfaces as
    // an error so the rider is never shown fake financial data.
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/rider/earnings"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {
        "success": false,
        "error": "Couldn't load earnings (HTTP ${res.statusCode}).",
      };
    } catch (_) {
      return {
        "success": false,
        "error": "Couldn't reach the server. Please retry.",
      };
    }
  }

  // 10. Get Live Customer Reviews from DB
  static Future<Map<String, dynamic>> getRiderReviews() async {
    // No fake 5.0 rating fallback.
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/rider/reviews"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {"success": false, "error": "Couldn't load reviews."};
    } catch (_) {
      return {"success": false, "error": "Couldn't reach the server."};
    }
  }
}
