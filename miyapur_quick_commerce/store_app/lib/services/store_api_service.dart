import 'dart:convert';

import 'package:http/http.dart' as http;
import '../utils/store_preferences.dart';

class StoreApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: "https://flash-fresh.onrender.com/api/v1",
  );

  /// Auth headers — attaches the manager's JWT to every request. The backend
  /// now requires role=MANAGER on ALL /store/* routes.
  static Map<String, String> _authHeaders({Map<String, String>? extra}) {
    final token = StorePreferences.token;
    final headers = <String, String>{
      "Content-Type": "application/json",
      if (token.isNotEmpty) "Authorization": "Bearer $token",
    };
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  // 0. Manager login (OTP). Managers share the customer OTP flow; the backend
  // resolves role=MANAGER from the users table (seeded manager phone:
  // 9000011111).
  static Future<Map<String, dynamic>> sendOtp(String phone) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/auth/send-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone}),
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "OTP send failed."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server. Please retry."};
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/auth/verify-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone, "otp": otp}),
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body["success"] == true) {
          await StorePreferences.setToken(body["token"] ?? "");
          await StorePreferences.setManagerId(body["user_id"] ?? "");
          await StorePreferences.setManagerPhone(body["phone"] ?? phone);
          await StorePreferences.setManagerName(body["name"] ?? "Store Manager");
        }
        return body;
      }
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Verification failed."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server. Please retry."};
    }
  }

  // 1. Dashboard Summary
  static Future<Map<String, dynamic>> getDashboardSummary() async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/store/dashboard-summary"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {"error": "Couldn't load dashboard (HTTP ${res.statusCode}).", "orders_to_pack": 0};
    } catch (_) {}
    return {"error": "Couldn't reach the server.", "orders_to_pack": 0};
  }

  // 2. Active Riders (live from DB)
  static Future<List<Map<String, dynamic>>> getActiveRiders() async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/store/riders/active"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        List data = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  // 3. Live Packing Queue
  static Future<List<Map<String, dynamic>>> getPackingQueue() async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/store/packing-queue"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        List data = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  // 4. Mark Packed — CRITICAL: previously returned fake success on failure.
  static Future<Map<String, dynamic>> markOrderPacked(String orderId) async {
    try {
      final res = await http
          .post(Uri.parse("$baseUrl/store/orders/$orderId/mark-packed"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Mark packed failed (HTTP ${res.statusCode})."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server. The order was NOT marked packed."};
    }
  }

  // 5. Assign Rider — CRITICAL: previously returned fake success on failure.
  static Future<Map<String, dynamic>> assignRider(String orderId, String riderId) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/store/orders/$orderId/assign-rider"),
            headers: _authHeaders(),
            body: jsonEncode({"rider_id": riderId}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Rider assignment failed (HTTP ${res.statusCode})."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server. No rider was assigned."};
    }
  }

  // 6. Record Meat Weight & Cut — CRITICAL: previously returned fake success on failure.
  static Future<Map<String, dynamic>> recordMeatWeight({
    required String orderId,
    required double weightG,
    required String cutType,
    required bool turmericWash,
    required bool skinless,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/store/orders/$orderId/record-weight"),
            headers: _authHeaders(),
            body: jsonEncode({
              "actual_weight_g": weightG,
              "cut_type": cutType,
              "turmeric_wash": turmericWash,
              "skinless": skinless,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Weight recording failed (HTTP ${res.statusCode})."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server. Weight was NOT recorded."};
    }
  }

  // 7. Inventory List
  static Future<List<Map<String, dynamic>>> getInventory() async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/store/inventory"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        List data = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  // 8. Update Stock Qty — CRITICAL: previously returned `true` on failure.
  static Future<Map<String, dynamic>> updateStock(String variantId, int newStockQty) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/store/inventory/update-stock"),
            headers: _authHeaders(),
            body: jsonEncode({"variant_id": variantId, "new_stock_qty": newStockQty}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Stock update failed (HTTP ${res.statusCode})."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server. Stock was NOT updated."};
    }
  }

  // 9. Update Product Detail (Name, Label, Price, Stock)
  // CRITICAL: previously returned `true` on failure, so the manager saw
  // "✏️ Details Saved!" while nothing was actually saved. This was a major
  // contributor to the price-update bug: the price update silently failed and
  // the customer kept seeing the old price.
  static Future<Map<String, dynamic>> updateProductDetail({
    required String productId,
    required String variantId,
    required String productName,
    required String weightLabel,
    required double price,
    required int stockQty,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/store/inventory/update-product-detail"),
            headers: _authHeaders(),
            body: jsonEncode({
              "product_id": productId,
              "variant_id": variantId,
              "product_name": productName,
              "weight_label": weightLabel,
              "price": price,
              "stock_qty": stockQty,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Update failed (HTTP ${res.statusCode}). Price was NOT saved."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server. Price was NOT saved — please retry."};
    }
  }

  // 10. Get Catalog Categories
  static Future<List<Map<String, dynamic>>> getCatalogCategories() async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/store/catalog/all-categories"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        List data = jsonDecode(res.body);
        if (data.isNotEmpty) return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  // 11. Add Catalog Product — CRITICAL: previously returned fake success on failure.
  static Future<Map<String, dynamic>> addProduct({
    required String categoryId,
    required String name,
    required String description,
    required String imageUrl,
    required bool isSundayOnly,
    required String weightLabel,
    required double mrp,
    required double price,
    required int stockQty,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/store/catalog/add-product"),
            headers: _authHeaders(),
            body: jsonEncode({
              "category_id": categoryId,
              "name": name,
              "description": description,
              "image_url": imageUrl,
              "is_sunday_only": isSundayOnly,
              "variants": [
                {
                  "weight_label": weightLabel,
                  "mrp": mrp,
                  "price": price,
                  "stock_qty": stockQty,
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Add product failed (HTTP ${res.statusCode})."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server. Product was NOT added."};
    }
  }

  // 12. Deactivate Product — CRITICAL: previously returned `true` on failure.
  static Future<Map<String, dynamic>> deactivateProduct(String productId) async {
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/store/catalog/delete-product"),
            headers: _authHeaders(),
            body: jsonEncode({"product_id": productId}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final err = jsonDecode(res.body);
      return {"success": false, "message": err["detail"] ?? "Deactivate failed (HTTP ${res.statusCode})."};
    } catch (_) {
      return {"success": false, "message": "Couldn't reach the server. Product was NOT deactivated."};
    }
  }

  // 13. Promo codes (manager CRUD) — NEW.
  static Future<List<Map<String, dynamic>>> listPromoCodes() async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/store/promos"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        List data = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  // 14. Audit log — NEW (who-did-what trail for compliance).
  static Future<List<Map<String, dynamic>>> getAuditLog() async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/store/audit-log"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        List data = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  // 15. Customer Ratings
  static Future<Map<String, dynamic>> getRatings() async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/rider/reviews"), headers: _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return {"avg_rating": 0.0, "total_ratings": 0, "recent_reviews": [], "error": "Couldn't load ratings."};
  }
}
