import 'package:shared_preferences/shared_preferences.dart';

/// Persistent storage for the store manager's JWT auth token + identity.
class StorePreferences {
  static const keyManagerToken = "store_manager_jwt_token";
  static const keyManagerId = "store_manager_id";
  static const keyManagerPhone = "store_manager_phone";
  static const keyManagerName = "store_manager_name";

  static late SharedPreferences _pref;

  static Future<void> init() async {
    _pref = await SharedPreferences.getInstance();
  }

  static String get token => _pref.getString(keyManagerToken) ?? "";
  static Future<void> setToken(String value) async => _pref.setString(keyManagerToken, value);

  static String get managerId => _pref.getString(keyManagerId) ?? "";
  static Future<void> setManagerId(String value) async => _pref.setString(keyManagerId, value);

  static String get managerPhone => _pref.getString(keyManagerPhone) ?? "";
  static Future<void> setManagerPhone(String value) async => _pref.setString(keyManagerPhone, value);

  static String get managerName => _pref.getString(keyManagerName) ?? "";
  static Future<void> setManagerName(String value) async => _pref.setString(keyManagerName, value);

  static bool get isLoggedIn => token.isNotEmpty;

  static Future<void> clear() async {
    await _pref.remove(keyManagerToken);
    await _pref.remove(keyManagerId);
    await _pref.remove(keyManagerPhone);
    await _pref.remove(keyManagerName);
  }
}
