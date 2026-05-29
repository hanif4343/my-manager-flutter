import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    assert(_prefs != null, 'SettingsService.init() must be called first');
    return _prefs!;
  }

  static bool get isDark => _p.getBool('isDark') ?? true;
  static Future<void> setDark(bool val) => _p.setBool('isDark', val);

  static bool getBool(String key, {bool defaultValue = false}) =>
      _p.getBool(key) ?? defaultValue;
  static Future<void> setBool(String key, bool val) => _p.setBool(key, val);

  static int getInt(String key, {int defaultValue = 0}) =>
      _p.getInt(key) ?? defaultValue;
  static Future<void> setInt(String key, int val) => _p.setInt(key, val);

  static String getString(String key, {String defaultValue = ''}) =>
      _p.getString(key) ?? defaultValue;
  static Future<void> setString(String key, String val) => _p.setString(key, val);
}
