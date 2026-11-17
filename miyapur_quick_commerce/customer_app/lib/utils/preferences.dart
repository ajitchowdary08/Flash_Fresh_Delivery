import 'package:shared_preferences/shared_preferences.dart';

class Preferences {
  static const keyUserId = "user_id";
  static const keyUserPhone = "user_phone";
  static const keyUserName = "user_name";
  static const keyUserEmail = "user_email";
  static const keyJwtToken = "jwt_token";
  static const keyActiveLocId = "active_loc_id";
  static const keyActiveLocName = "active_loc_name";
  static const keyActiveLocAddress = "active_loc_address";
  static const keyActiveLocLat = "active_loc_lat";
  static const keyActiveLocLng = "active_loc_lng";
  static const keyActiveLocDist = "active_loc_dist";
  static const keyActiveLocServiceable = "active_loc_serviceable";
  static const keyActiveLocEta = "active_loc_eta";
  static const keySavedAddrs = "global_saved_addrs";
  static const keyFavoriteProducts = "favorite_products";
  static const keyCachedOrders = "cached_user_orders";

  static late SharedPreferences pref;

  static Future<void> initPref() async {
    pref = await SharedPreferences.getInstance();
  }

  static String getString(String key, [String defaultValue = ""]) {
    return pref.getString(key) ?? defaultValue;
  }

  static Future<void> setString(String key, String value) async {
    await pref.setString(key, value);
  }

  static bool getBoolean(String key, [bool defaultValue = false]) {
    return pref.getBool(key) ?? defaultValue;
  }

  static Future<void> setBoolean(String key, bool value) async {
    await pref.setBool(key, value);
  }

  static double getDouble(String key, [double defaultValue = 0.0]) {
    return pref.getDouble(key) ?? defaultValue;
  }

  static Future<void> setDouble(String key, double value) async {
    await pref.setDouble(key, value);
  }

  static int getInt(String key, [int defaultValue = 0]) {
    return pref.getInt(key) ?? defaultValue;
  }

  static Future<void> setInt(String key, int value) async {
    await pref.setInt(key, value);
  }

  static List<String> getStringList(String key) {
    return pref.getStringList(key) ?? [];
  }

  static Future<void> setStringList(String key, List<String> value) async {
    await pref.setStringList(key, value);
  }

  static Future<void> removeKey(String key) async {
    await pref.remove(key);
  }

  static Future<void> clearAll() async {
    await pref.clear();
  }
}
