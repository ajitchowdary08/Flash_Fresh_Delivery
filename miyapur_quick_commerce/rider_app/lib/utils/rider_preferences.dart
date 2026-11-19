import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight persistent storage for the rider's JWT auth token + identity.
/// Kept separate from the customer app's Preferences so the two never collide
/// if both apps are ever merged into a monorepo.
class RiderPreferences {
  static const keyRiderToken = "rider_jwt_token";
  static const keyRiderId = "rider_id";
  static const keyRiderPhone = "rider_phone";
  static const keyRiderName = "rider_name";

  static late SharedPreferences _pref;

  static Future<void> init() async {
    _pref = await SharedPreferences.getInstance();
  }

  static String get token => _pref.getString(keyRiderToken) ?? "";
  static Future<void> setToken(String value) async => _pref.setString(keyRiderToken, value);

  static String get riderId => _pref.getString(keyRiderId) ?? "";
  static Future<void> setRiderId(String value) async => _pref.setString(keyRiderId, value);

  static String get riderPhone => _pref.getString(keyRiderPhone) ?? "";
  static Future<void> setRiderPhone(String value) async => _pref.setString(keyRiderPhone, value);

  static String get riderName => _pref.getString(keyRiderName) ?? "";
  static Future<void> setRiderName(String value) async => _pref.setString(keyRiderName, value);

  static bool get isLoggedIn => token.isNotEmpty;

  /// Clears the rider session on logout.
  static Future<void> clear() async {
    await _pref.remove(keyRiderToken);
    await _pref.remove(keyRiderId);
    await _pref.remove(keyRiderPhone);
    await _pref.remove(keyRiderName);
  }
}
